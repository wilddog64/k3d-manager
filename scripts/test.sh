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
        echo "✅ Istio sidecar injection is working!"
    else
        echo "❌ Istio sidecar was not injected! Check your Istio installation."
        return 1
    fi

    # Test direct access first (bypassing Istio)
    echo "Testing direct pod access..."
    _kubectl port-forward -n istio-test svc/nginx-test 8888:80 &
    PF_PID=$!
    sleep 3
    if _curl -s localhost:8888 | grep -q "Welcome to nginx"; then
        echo "✅ Direct access to the pod is working!"
    else
        echo "❌ Failed to access the pod directly"
        exit -1
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
        echo "✅ Istio Gateway created successfully"
    else
        echo "❌ Failed to create Istio Gateway"
        exit -1
    fi

    # Verify VirtualService creation
    if _kubectl get virtualservice -n istio-test test-vs; then
        echo "✅ Istio VirtualService created successfully"
    else
        echo "❌ Failed to create Istio VirtualService"
        exit -1
    fi

    # Test through Istio gateway
    echo "Testing through Istio gateway..."
    _kubectl port-forward -n istio-system svc/istio-ingressgateway 8085:80 &
    sleep 15

    echo "Making request through Istio Gateway..."
    if _curl -s localhost:8085 | grep -q "Welcome to nginx"; then
        echo "✅ Request through Istio Gateway successful!"
        echo "🎉 ISTIO IS WORKING CORRECTLY! 🎉"
    else
        echo "❌ Failed to access through Istio Gateway"
        echo "Detailed response:"
        exit -1
    fi

    echo "For a more complete test, you could try accessing the Istio ingress gateway's external IP:"
    _kubectl get svc -n istio-system istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    echo ""
    trap 'cleanup_istio_test_namespace' EXIT TERM
}

function cleanup_istio_test_namespace() {

    echo "Cleaning up Istio test namespace..."
    echo "warning: port forwarding will not remove if process failed"
    if [[ $? == 0 ]]; then
       # Kill the port-forwarding process if it exists
       ps aux | grep kubectl | awk '{ print $2 }' | xargs kill
       _kubectl delete namespace istio-test --ignore-not-found
    fi
}
