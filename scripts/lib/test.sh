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

function test_jenkins() {
    echo "Testing Jenkins deployment..."
    trap '_cleanup_jenkins_test_namespace' EXIT TERM
    PF_PIDS=()

    deploy_jenkins
    _wait_for_jenkins_ready jenkins

    # Verify the Jenkins pod mounts the expected PVC
    local pvc
    pvc=$(_kubectl get pod jenkins-0 -n jenkins -o jsonpath='{..persistentVolumeClaim.claimName}')
    if [[ "$pvc" != "jenkins-home" ]]; then
        echo "Unexpected PVC: $pvc" >&2
        return 1
    fi

    # Ensure Istio routing resources exist
    _kubectl get gateway jenkins-gw -n istio-system >/dev/null
    _kubectl get virtualservice jenkins -n jenkins >/dev/null
    _kubectl get destinationrule jenkins -n jenkins >/dev/null

    # Port-forward the Istio ingress gateway for HTTPS access to Jenkins
    _kubectl -n istio-system port-forward svc/istio-ingressgateway 8443:443 &
    PF_PIDS+=($!)
    sleep 15

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
    local admin_pass http_code
    admin_pass=$(_kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d)
    http_code=$(_curl --insecure --resolve jenkins.dev.local.me:8443:127.0.0.1 \
        -s -o /dev/null -w '%{http_code}' -L -X POST \
        -d "j_username=jenkins-admin&j_password=${admin_pass}&Submit=Sign+in" \
        https://jenkins.dev.local.me:8443/j_acegi_security_check)
    if [[ "$http_code" != "200" ]]; then
        echo "Jenkins authentication failed with HTTP $http_code" >&2
        return 1
    fi
}

function _cleanup_jenkins_test_namespace() {
    echo "Cleaning up Jenkins test namespace..."
    echo "warning: port forwarding will not remove if process failed"
    for pid in "${PF_PIDS[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    _kubectl delete gateway jenkins-gw -n istio-system --ignore-not-found
    _kubectl delete namespace jenkins --ignore-not-found
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
  root_token=$(_kubectl -n "$vault_ns" get secret vault-root -o jsonpath='{.data.root_token}' | base64 -d)

  trap "_cleanup_eso_test '$vault_ns' '$vault_secret_path' '$root_token' '$es_ns' '$es_name' '$store_name'" EXIT TERM

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

  echo "Cleaning up ESO test resources..."
  _kubectl -n "$es_ns" delete externalsecret "$es_name" --ignore-not-found >/dev/null 2>&1
  _kubectl -n "$es_ns" delete secret "$es_name" --ignore-not-found >/dev/null 2>&1
  _kubectl delete clustersecretstore "$store_name" --ignore-not-found >/dev/null 2>&1
  _kubectl -n "$vault_ns" exec -i vault-0 -- \
    sh -c "VAULT_TOKEN='$root_token' vault kv delete secret/$vault_secret_path" >/dev/null 2>&1 || true
}
