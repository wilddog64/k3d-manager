# ArgoCD CLI Port-Forward Issue

## Problem Summary

The `argocd` CLI login fails when using `kubectl port-forward` due to k3s networking issues. The error manifests as:

```
error dial proxy: dial tcp 127.0.0.1:8080: connect: connection refused
```

With port-forward logs showing:

```
failed to execute portforward in network namespace "/var/run/netns/cni-...":
writeto tcp4 127.0.0.1:X->127.0.0.1:8080: read: connection reset by peer
error: lost connection to pod
```

## Root Cause

The k3s cluster has a networking/CNI issue that causes `kubectl port-forward` connections to reset during the `argocd login` handshake. The port-forward briefly establishes connectivity (verified by `nc -z`), but drops the connection when the ArgoCD CLI attempts to communicate with the server.

## Verification

ArgoCD server is confirmed **working correctly**:

```bash
kubectl run -n argocd curl-test --image=curlimages/curl:latest --rm -i --restart=Never \
  --command -- curl -s http://argocd-server.argocd.svc.cluster.local:80/api/version
# Returns: {"Version":"v3.2.1+8c4ab63"}
```

## Workarounds

### Option 1: In-Cluster Testing (Recommended)

Deploy a test pod with the `argocd` CLI inside the cluster:

```bash
kubectl run -n argocd argocd-cli-test --image=argoproj/argocd:latest --rm -it --restart=Never -- bash

# Inside the pod:
ADMIN_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)
argocd login argocd-server.argocd.svc.cluster.local:80 --insecure --grpc-web --username admin --password "$ADMIN_PASS"
argocd cluster list
argocd app list
```

### Option 2: Direct API Testing

Use curl to test ArgoCD functionality without the CLI:

```bash
# Get admin password
ADMIN_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)

# Login and get auth token
kubectl run -n argocd curl-test --image=curlimages/curl:latest --rm -i --restart=Never -- \
  curl -s -X POST http://argocd-server.argocd.svc.cluster.local:80/api/v1/session \
  -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}"

# Use token for subsequent requests
```

### Option 3: NodePort Service (If Available)

Expose ArgoCD server via NodePort for stable external access:

```bash
kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'
NODE_PORT=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}')
argocd login localhost:$NODE_PORT --insecure --grpc-web --username admin --password "$ADMIN_PASS"
```

## Impact on Testing

The `bin/test-argocd-cli.sh` script cannot run successfully with `kubectl port-forward`. The script should be updated to use **Option 1** (in-cluster testing) for reliable execution.

## Related Investigation

- ArgoCD server pod: healthy, no errors in logs
- ArgoCD ConfigMap: Dex LDAP configured correctly
- Admin user: enabled and password retrievable
- Network connectivity within cluster: working
- Issue specific to: `kubectl port-forward` on this k3s installation

## Recommended Fix

Update `bin/test-argocd-cli.sh` to deploy a test pod inside the cluster that runs the `argocd` CLI commands against the in-cluster service endpoint (`argocd-server.argocd.svc.cluster.local:80`).

## References

- ArgoCD version: v3.2.1+8c4ab63
- Test date: 2025-12-04
- Environment: k3s on Linux (parallels@k3s-automation)
