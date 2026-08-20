# Bug: make status ArgoCD section fails without an active port-forward

**Branch:** `k3d-manager-v1.2.0`
**File:** `bin/acg-status`

## Root Cause

`bin/acg-status` runs `argocd app list` to show ArgoCD application health. The `argocd` CLI
connects to `localhost:8080`, which requires an active port-forward to the `argocd-server`
service. `acg-status` never starts a port-forward, so the call always fails:

```
=== ArgoCD Apps ===
ArgoCD CLI not logged in — run: argocd login
```

## Fix

Replace `argocd app list` with `kubectl get applications.argoproj.io -A`. ArgoCD
applications are CRDs stored in the hub cluster — readable via kubectl at any time without
a port-forward or CLI login.

**Old:**
```bash
echo "=== ArgoCD Apps ==="
if command -v argocd >/dev/null 2>&1; then
  argocd app list 2>/dev/null || echo "ArgoCD CLI not logged in — run: argocd login"
else
  echo "argocd CLI not installed"
fi
```

**New:**
```bash
echo "=== ArgoCD Apps ==="
kubectl get applications.argoproj.io -A --context "${INFRA_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach Hub cluster or ArgoCD CRDs not installed"
```
