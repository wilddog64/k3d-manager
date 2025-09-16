# Ensure SCRIPT_DIR is set when this library is sourced directly.
if [[ -z "${SCRIPT_DIR:-}" ]]; then
  SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd)"
fi

# Load Jenkins plugin helpers so Jenkins tests have their dependencies.
if [[ -f "${SCRIPT_DIR}/plugins/jenkins.sh" ]]; then
  # shellcheck source=../plugins/jenkins.sh
  source "${SCRIPT_DIR}/plugins/jenkins.sh"
fi

function test_nfs_direct() {
  echo "Testing NFS connectivity directly from a pod..."

  # Create a pod that mounts NFS directly
  cat <<EOF | _kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: nfs-test-direct
spec:
  containers:
  - name: nfs-mount-test
    image: busybox
    command: ["sh", "-c", "mount | grep nfs; echo 'Testing NFS mount...'; mkdir -p /mnt/test; mount -t nfs -o vers=3,nolock host.k3d.internal:/Users/$(whoami)/k3d-nfs /mnt/test && echo 'Mount successful' || echo 'Mount failed'; ls -la /mnt/test; sleep 3600"]
    securityContext:
      privileged: true
  restartPolicy: Never
EOF

  echo "Waiting for pod to be ready..."
  sleep 5
  _kubectl logs nfs-test-direct
}


function test_istio() {
    echo "Testing Istio installation and functionality..."
    trap '_cleanup_istio_test_namespace' EXIT TERM
    PF_PIDS=()

    # 1. Create a very simple test deployment and service

    # Deploy a minimal nginx pod
    _kubectl apply -f - -n istio-test <<EOF
apiVersion: v1
kind: Namespace
metadata:
  labels:
    istio-injection: enabled
    kubernetes.io/metadata.name: istio-test
  name: istio-test
spec:
  finalizers:
  - kubernetes
status:
  phase: Active
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-test
  namespace: istio-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx-test
  template:
    metadata:
      labels:
        app: nginx-test
    spec:
      containers:
      - name: nginx
        image: nginx:stable
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-test
  namespace: istio-test
spec:
  ports:
  - port: 80
  selector:
    app: nginx-test
EOF

    # Wait for deployment
    _kubectl rollout status deployment/nginx-test -n istio-test --timeout=120s

    # Verify that the Istio proxy has been injected
    echo "Checking for Istio sidecar..."
    if _kubectl get pod -n istio-test -l app=nginx-test -o jsonpath='{.items[0].spec.containers[*].name}' | grep -q istio-proxy; then
        echo "Istio sidecar injection is working!"
    else
        echo "Istio sidecar was not injected! Check your Istio installation."
        return 1
    fi

    # Test direct access first (bypassing Istio)
    echo "Testing direct pod access..."
    _kubectl port-forward -n istio-test svc/nginx-test 8888:80 &
    PF_PIDS+=($!)
    sleep 3
    if _curl -s localhost:8888 | grep -q "Welcome to nginx"; then
        echo "Direct access to the pod is working!"
    else
        echo "Failed to access the pod directly"
        return 1
    fi

    # Create Istio Gateway and VirtualService
    _kubectl apply -f - -n istio-test <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: Gateway
metadata:
  name: test-gateway
  namespace: istio-test
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*"
---
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: test-vs
  namespace: istio-test
spec:
  hosts:
  - "*"
  gateways:
  - test-gateway
  http:
  - route:
    - destination:
        host: nginx-test
        port:
          number: 80
EOF

    # Verify Gateway creation
    if _kubectl get gateway -n istio-test test-gateway; then
        echo "Istio Gateway created successfully"
    else
        echo "Failed to create Istio Gateway"
        return 1
    fi

    # Verify VirtualService creation
    if _kubectl get virtualservice -n istio-test test-vs; then
        echo "Istio VirtualService created successfully"
    else
        echo "Failed to create Istio VirtualService"
        return 1
    fi

    # Test through Istio gateway
    echo "Testing through Istio gateway..."
    _kubectl port-forward -n istio-system svc/istio-ingressgateway 8085:80 &
    PF_PIDS+=($!)
    sleep 15

    echo "Making request through Istio Gateway..."
    if _curl -s localhost:8085 | grep -q "Welcome to nginx"; then
        echo "Request through Istio Gateway successful!"
        echo "ISTIO IS WORKING CORRECTLY!"
    else
        echo "Failed to access through Istio Gateway"
        echo "Detailed response:"
        return 1
    fi

    echo "For a more complete test, you could try accessing the Istio ingress gateway's external IP:"
    _kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    echo ""
    trap '_cleanup_istio_test_namespace' EXIT TERM
}

function _cleanup_istio_test_namespace() {

    echo "Cleaning up Istio test namespace..."
    echo "warning: port forwarding will not remove if process failed"
    for pid in "${PF_PIDS[@]}"; do
       kill "$pid" 2>/dev/null || true
    done
    _kubectl delete namespace istio-test --ignore-not-found
}

function _wait_for_port_forward() {
    local pid="$1"
    local url="http://127.0.0.1:8080/login"
    local timeout=30
    local interval=2
    local elapsed=0

    until _run_command --quiet --no-exit -- curl -fsS "$url" >/dev/null 2>&1; do
        sleep "$interval"
        elapsed=$((elapsed + interval))
        if (( elapsed >= timeout )); then
            echo "Port-forward to Jenkins did not become ready" >&2
            kill "$pid" 2>/dev/null || true
            return 1
        fi
    done
}


function test_jenkins() {
    echo "Testing Jenkins deployment..."
    JENKINS_NS="${JENKINS_NS:-jenkins}"
    VAULT_NS="${VAULT_NS:-vault}"
    local AUTH_FILE
    AUTH_FILE="$(mktemp)"
    trap "_cleanup_jenkins_test; rm -f '${AUTH_FILE}'" EXIT TERM
    PF_PIDS=()
    CREATED_JENKINS=0
    CREATED_VAULT=0
    CREATED_JENKINS_NS=""
    CREATED_VAULT_NS=""

    if ! declare -F deploy_jenkins >/dev/null || ! declare -F _wait_for_jenkins_ready >/dev/null; then
        echo "Required Jenkins helpers (deploy_jenkins/_wait_for_jenkins_ready) are unavailable." >&2
        echo "Ensure scripts/plugins/jenkins.sh is sourced before running test_jenkins." >&2
        return 1
    fi

    if ! _kubectl --no-exit get ns "$JENKINS_NS" >/dev/null 2>&1; then
        CREATED_JENKINS=1
        CREATED_JENKINS_NS="$JENKINS_NS"
        if ! _kubectl --no-exit get ns "$VAULT_NS" >/dev/null 2>&1; then
            CREATED_VAULT=1
            CREATED_VAULT_NS="$VAULT_NS"
        fi
        deploy_jenkins "$JENKINS_NS"
    fi

    _wait_for_jenkins_ready "$JENKINS_NS"

    if [[ "$CREATED_JENKINS" -eq 0 ]]; then
        deploy_jenkins "$JENKINS_NS"
        _wait_for_jenkins_ready "$JENKINS_NS"
    fi

    # Verify the Jenkins pod mounts the expected PVC
    local pvc
    pvc=$(_kubectl get pod jenkins-0 -n "$JENKINS_NS" -o jsonpath='{..persistentVolumeClaim.claimName}')
    if [[ "$pvc" != "jenkins-home" ]]; then
        echo "Unexpected PVC: $pvc" >&2
        return 1
    fi

    # Ensure Istio routing resources exist
    _kubectl get gateway jenkins-gw -n istio-system >/dev/null
    _kubectl get virtualservice jenkins -n "$JENKINS_NS" >/dev/null
    _kubectl get destinationrule jenkins -n "$JENKINS_NS" >/dev/null

    _kubectl -n "$JENKINS_NS" port-forward svc/jenkins 8080:8080 >/tmp/jenkins-test-pf.log 2>&1 &
    pf_pid=$!
    PF_PIDS+=($!)
    if ! _wait_for_port_forward "$pf_pid"; then
         return 1
    fi

    # Confirm TLS termination and fetch the Jenkins landing page
    if ! _curl --insecure -v --resolve jenkins.dev.local.me:8443:127.0.0.1 \
        https://jenkins.dev.local.me:8443/ 2>&1 | grep -q 'subject: CN=jenkins.dev.local.me'; then
        echo "TLS certificate not issued by Vault" >&2
        return 1
    fi

    if ! _curl --insecure --resolve jenkins.dev.local.me:8443:127.0.0.1 \
        https://jenkins.dev.local.me:8443/login | grep -q Jenkins; then
        echo "Unable to reach Jenkins landing page" >&2
        return 1
    fi

    # Verify required Vault policies are installed
    local policies
    policies=$(_kubectl -n vault exec vault-0 -- vault policy list)
    if ! echo "$policies" | grep -q jenkins-admin || \
       ! echo "$policies" | grep -q jenkins-jcasc-read || \
       ! echo "$policies" | grep -q jenkins-jcasc-write; then
        echo "Required Vault policies missing" >&2
        return 1
    fi

    # Authenticate to Jenkins using the admin secret
    _kubectl -n "$JENKINS_NS" port-forward svc/jenkins 8080:8080 &
    PF_PIDS+=($!)
    sleep 5

    local admin_user admin_pass auth_status
    admin_user=$(_kubectl -n "$JENKINS_NS" get secret jenkins-admin -o jsonpath='{.data.username}' | base64 -d)
    admin_pass=$(_kubectl -n "$JENKINS_NS" get secret jenkins-admin -o jsonpath='{.data.password}' | base64 -d)
    auth_status=$(_curl -u "$admin_user:$admin_pass" -s -o "$AUTH_FILE" -w '%{http_code}' http://127.0.0.1:8080/whoAmI/api/json)
    if [[ "$auth_status" != "200" ]] || ! grep -q '"authenticated":true' "$AUTH_FILE"; then
        echo "Jenkins authentication failed" >&2
        return 1
    fi
}

function _cleanup_jenkins_test() {
    echo "Cleaning up Jenkins test resources..."
    for pid in "${PF_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    if [[ "$CREATED_JENKINS" -eq 1 ]]; then
        _kubectl delete gateway jenkins-gw -n istio-system --ignore-not-found
        local namespace_to_delete="${CREATED_JENKINS_NS:-$JENKINS_NS}"
        if [[ -n "$namespace_to_delete" ]]; then
            _kubectl delete namespace "$namespace_to_delete" --ignore-not-found
        fi
    fi
    if [[ "$CREATED_VAULT" -eq 1 ]]; then
        local vault_namespace_to_delete="${CREATED_VAULT_NS:-$VAULT_NS}"
        if [[ -n "$vault_namespace_to_delete" ]]; then
            _kubectl delete namespace "$vault_namespace_to_delete" --ignore-not-found
        fi
    fi
}

function test_nfs_connectivity() {
  echo "Testing basic connectivity to NFS server..."

  # Create a pod with networking tools
  _kubectl run nfs-connectivity-test --image=nicolaka/netshoot --rm -it --restart=Never -- bash -c "
    echo 'Attempting to reach NFS port on host...'
    nc -zv host.k3d.internal 2049
    echo 'DNS lookup for host...'
    nslookup host.k3d.internal
    echo 'Tracing route to host...'
    traceroute host.k3d.internal
    echo 'Testing rpcinfo...'
    rpcinfo -p host.k3d.internal 2>/dev/null || echo 'RPC failed'
  "
}

function test_eso() {
  echo "Testing External Secrets Operator with Vault..."

  local vault_ns="vault"
  local store_name="vault-test"
  local es_name="eso-test"
  local es_ns="default"
  local vault_secret_path="eso/test"
  local secret_key="magic"
  local secret_val="swordfish"

  local root_token
  local vault_started=0

  if ! _kubectl --no-exit get ns "$vault_ns" >/dev/null 2>&1 || \
     ! _kubectl --no-exit -n "$vault_ns" get secret vault-root >/dev/null 2>&1; then
    echo "Vault not detected; deploying..."
    "${SCRIPT_DIR}/k3d-manager" deploy_vault ha "$vault_ns"
    vault_started=1
  fi

  root_token=$(_kubectl -n "$vault_ns" get secret vault-root -o jsonpath='{.data.root_token}' | base64 -d)

  trap "_cleanup_eso_test '$vault_ns' '$vault_secret_path' '$root_token' '$es_ns' '$es_name' '$store_name' '$vault_started'" EXIT TERM

  echo "Creating secret in Vault..."
  _kubectl -n "$vault_ns" exec -i vault-0 -- \
    sh -c "VAULT_TOKEN='$root_token' vault kv put secret/$vault_secret_path $secret_key='$secret_val'"

  echo "Creating ClusterSecretStore..."
  cat <<EOF | _kubectl apply -f -
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: ${store_name}
spec:
  provider:
    vault:
      server: "https://vault.${vault_ns}.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "eso-reader"
      tls:
        insecureSkipVerify: true
EOF

  echo "Creating ExternalSecret..."
  cat <<EOF | _kubectl apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: ${es_name}
  namespace: ${es_ns}
spec:
  refreshInterval: 15s
  secretStoreRef:
    name: ${store_name}
    kind: ClusterSecretStore
  target:
    name: ${es_name}
  data:
  - secretKey: ${secret_key}
    remoteRef:
      key: ${vault_secret_path}
      property: ${secret_key}
EOF

  echo "Waiting for ExternalSecret to be synced..."
  _kubectl -n "$es_ns" wait --for=condition=Ready externalsecret/${es_name} --timeout=120s

  local synced
  synced=$(_kubectl -n "$es_ns" get secret "$es_name" -o jsonpath='{.data.${secret_key}}' | base64 -d)

  if [[ "$synced" == "$secret_val" ]]; then
    echo "ESO synced secret successfully."
  else
    echo "Secret value mismatch: expected '$secret_val', got '$synced'"
    return 1
  fi

  echo "ESO test completed successfully."
}

function _cleanup_eso_test() {
  local vault_ns="$1"
  local vault_secret_path="$2"
  local root_token="$3"
  local es_ns="$4"
  local es_name="$5"
  local store_name="$6"
  local vault_started="${7:-0}"

  echo "Cleaning up ESO test resources..."
  _kubectl -n "$es_ns" delete externalsecret "$es_name" --ignore-not-found >/dev/null 2>&1
  _kubectl -n "$es_ns" delete secret "$es_name" --ignore-not-found >/dev/null 2>&1
  _kubectl delete clustersecretstore "$store_name" --ignore-not-found >/dev/null 2>&1
  _kubectl -n "$vault_ns" exec -i vault-0 -- \
    sh -c "VAULT_TOKEN='$root_token' vault kv delete secret/$vault_secret_path" >/dev/null 2>&1 || true

  if [[ "$vault_started" -eq 1 ]]; then
    "${SCRIPT_DIR}/k3d-manager" undeploy_vault "$vault_ns" >/dev/null 2>&1 || true
  fi
}

function test_vault() {
  echo "Testing Vault deployment and Kubernetes auth..."
  local vault_ns="vault"
  local test_ns="vault-test"
  local sa="vault-test-sa"

  trap '_cleanup_vault_test' EXIT TERM

  # Deploy Vault in HA mode
  "${SCRIPT_DIR}/k3d-manager" deploy_vault ha "$vault_ns"

  # Ensure jenkins-admin policy exists
  source "${SCRIPT_DIR}/plugins/jenkins.sh"
  _create_jenkins_admin_vault_policy "$vault_ns"

  # Verify required policies
  for policy in eso-reader jenkins-admin; do
    if ! _kubectl -n "$vault_ns" exec vault-0 -- vault policy list | grep -q "$policy"; then
      echo "Missing policy: $policy"
      return 1
    fi
  done

  # Prepare test namespace and service account
  _kubectl create namespace "$test_ns"
  _kubectl create sa "$sa" -n "$test_ns"

  # Bind service account to Vault role
  _kubectl -n "$vault_ns" exec -i vault-0 -- \
    vault write auth/kubernetes/role/$sa \
      bound_service_account_names="$sa" \
      bound_service_account_namespaces="$test_ns" \
      policies=eso-reader \
      ttl=1h

  # Seed a test secret
  _kubectl -n "$vault_ns" exec -i vault-0 -- \
    vault kv put secret/eso/test message=success

  # Launch pod to read secret
  cat <<POD | _kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: vault-read
  namespace: $test_ns
spec:
  serviceAccountName: $sa
  containers:
  - name: vault
    image: hashicorp/vault:1.13.3
    env:
    - name: VAULT_ADDR
      value: http://vault.$vault_ns.svc.cluster.local:8200
    command:
    - sh
    - -c
    - |
      vault login -method=kubernetes role=$sa >/tmp/token
      vault kv get -field=message secret/eso/test > /tmp/secret
      sleep 3600
POD

  _kubectl wait --for=condition=Ready pod/vault-read -n "$test_ns" --timeout=120s
  local secret
  secret=$(_kubectl -n "$test_ns" exec vault-read -- cat /tmp/secret)
  if [[ "$secret" != "success" ]]; then
    echo "Failed to read secret via pod"
    return 1
  fi

  # Kubernetes auth token exchange
  local sa_jwt
  sa_jwt=$(_kubectl create token "$sa" -n "$test_ns")
  local vault_token
  vault_token=$(_kubectl -n "$vault_ns" exec -i vault-0 -- \
    sh -c "vault write -field=token auth/kubernetes/login role=$sa jwt=$sa_jwt")
  local value
  value=$(_kubectl -n "$vault_ns" exec -i vault-0 -- \
    sh -c "VAULT_TOKEN=$vault_token vault kv get -field=message secret/eso/test")
  if [[ "$value" != "success" ]]; then
    echo "Kubernetes auth token exchange failed"
    return 1
  fi

  echo "Vault test succeeded"
}

function _cleanup_vault_test() {
  echo "Cleaning up Vault test resources..."
  _kubectl delete namespace vault-test --ignore-not-found
  _helm uninstall vault -n vault 2>/dev/null || true
  _kubectl delete namespace vault --ignore-not-found
}
