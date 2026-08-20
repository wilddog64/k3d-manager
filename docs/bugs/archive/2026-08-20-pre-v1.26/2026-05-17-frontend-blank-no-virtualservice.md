# Bug: frontend.shopping-cart.local blank — no VirtualService routes to ubuntu-k3s frontend

**Branch:** `k3d-manager-v1.4.6`
**Files:**
- `bin/acg-up` — Step 10f block (after line 944, before line 947)

---

## Before You Start

```
git pull origin k3d-manager-v1.4.6
```

Read this spec in full before touching any file.

---

## Problem

`frontend.shopping-cart.local` resolves to `127.0.0.1` (Mac `/etc/hosts`). Port 80 on the
Mac is forwarded to the local k3d Istio ingressgateway via launchd. The ingressgateway has a
`default-gateway` Gateway resource (applied in Step 10f) but **no VirtualService for
`frontend.shopping-cart.local`**, so every request returns a blank 404/no-route response.

The frontend pod runs on the remote `ubuntu-k3s` cluster as ClusterIP only — there is no
NodePort and no path from the k3d ingressgateway to the pod.

**Root cause:** `acg-up` never creates:
1. A NodePort service for `frontend` on `ubuntu-k3s`
2. A ServiceEntry in k3d pointing to that NodePort
3. A VirtualService in k3d routing `frontend.shopping-cart.local` to the ServiceEntry

---

## Fix

Add a new **Step 10g** block immediately after the Step 10f block ends (after line 944,
before the `_info "[acg-up] Step 11/14..."` line at line 947).

### Exact insertion point

**Line 944 (end of Step 10f block):**
```bash
_info "[acg-up] ArgoCD SSO wired: login at https://argocd.shopping-cart.local → Keycloak realm shopping-cart"
```

**Line 947 (start of Step 11 — insert new Step 10g between these two):**
```bash
_info "[acg-up] Step 11/14 — Verifying ClusterSecretStore..."
```

### Exact new block (insert between line 944 and line 947):

```bash
_info "[acg-up] Step 10g/14 — Wiring frontend.shopping-cart.local → ubuntu-k3s frontend (NodePort + ServiceEntry + VirtualService)..."

# 1. Create / reconcile NodePort 30080 for the frontend service on ubuntu-k3s.
#    NodePort 30080 is reserved for frontend; 30081 = order-service, 30082 = product-catalog.
kubectl apply --context ubuntu-k3s -f - <<'FRONTEND_NP_EOF'
apiVersion: v1
kind: Service
metadata:
  name: frontend-nodeport
  namespace: shopping-cart-apps
spec:
  type: NodePort
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080
FRONTEND_NP_EOF

# 2. Get the ubuntu-k3s control-plane public IP from the kubeconfig server URL.
_ubuntu_k3s_ip=$(kubectl config view \
  --context ubuntu-k3s --minify \
  -o jsonpath='{.clusters[0].cluster.server}' \
  | sed 's|https://||; s|:.*||')

# 3. Apply a ServiceEntry in k3d so Istio can route to the remote NodePort.
kubectl apply --context k3d-k3d-cluster -f - <<FRONTEND_SE_EOF
apiVersion: networking.istio.io/v1beta1
kind: ServiceEntry
metadata:
  name: frontend-ubuntu-k3s
  namespace: istio-system
spec:
  hosts:
    - frontend-ubuntu-k3s.external
  addresses:
    - ${_ubuntu_k3s_ip}/32
  ports:
    - number: 30080
      name: http
      protocol: HTTP
  location: MESH_EXTERNAL
  resolution: STATIC
  endpoints:
    - address: ${_ubuntu_k3s_ip}
FRONTEND_SE_EOF

# 4. Apply VirtualService in k3d: frontend.shopping-cart.local → ServiceEntry host:30080.
kubectl apply --context k3d-k3d-cluster -f - <<'FRONTEND_VS_EOF'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: frontend
  namespace: istio-system
spec:
  hosts:
    - frontend.shopping-cart.local
  gateways:
    - istio-system/default-gateway
  http:
    - route:
        - destination:
            host: frontend-ubuntu-k3s.external
            port:
              number: 30080
FRONTEND_VS_EOF

_info "[acg-up] frontend.shopping-cart.local wired: ingressgateway → ${_ubuntu_k3s_ip}:30080 → frontend pod"
```

Also replace the stale Step 13 info line:

**Exact old line (line 968):**
```bash
_info "[acg-up] Step 13/14 — Frontend is served via the Istio ingress HTTP listener at http://frontend.shopping-cart.local (Step 10e). No separate port-forward needed."
```

**Exact new line:**
```bash
_info "[acg-up] Step 13/14 — Frontend wired via NodePort 30080 on ubuntu-k3s (Step 10g). URL: http://frontend.shopping-cart.local"
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add Step 10g between Step 10f and Step 11; update Step 13 info line |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files modified
- The NodePort 30080 must not conflict: 30081 = order-service-nodeport, 30082 = product-catalog-nodeport (both pre-existing)
- `_ubuntu_k3s_ip` is derived at runtime from the kubeconfig — do NOT hardcode the IP

---

## Definition of Done

- [ ] Step 10g block inserted between line 944 and line 947 (exact new block above)
- [ ] Step 13 info line replaced (exact new line above)
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

**Commit message (exact):**
```
fix(acg-up): wire frontend.shopping-cart.local via NodePort + ServiceEntry + VirtualService
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT hardcode `34.221.28.242` — the IP must be read from kubeconfig at runtime
- Do NOT touch the frontend selector label without checking `kubectl get deployment frontend -n shopping-cart-apps --context ubuntu-k3s -o jsonpath='{.spec.selector.matchLabels}'`
