# Bug: frontend 504 — product-catalog and order-service ClusterIP ports don't match nginx upstream config

**Branch (spec repo):** `k3d-manager-v1.4.6`
**Branch (all work repos):** `fix/argocd-shared-namespace`
**Files:**
- `shopping-cart-product-catalog` — `k8s/base/service.yaml`
- `shopping-cart-order` — `k8s/base/service.yaml`

---

## Before You Start

```bash
# Get the spec
git pull origin k3d-manager-v1.4.6   # in k3d-manager repo

# Work repos — already on the right branch
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog pull origin fix/argocd-shared-namespace
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-order pull origin fix/argocd-shared-namespace
```

Read this spec in full before touching any file.

---

## Problem

The frontend nginx config proxies API calls to backend services using their container ports:

```
/api/products  → product-catalog.shopping-cart-apps.svc.cluster.local:8082
/api/orders    → order-service.shopping-cart-apps.svc.cluster.local:8081
```

But the ClusterIP services for both expose `port: 80`, not the container ports. kube-proxy
only NATs traffic destined for the service port (80), so requests on 8082 and 8081 time out
with 504. The frontend spinner never resolves.

**Root cause:** `product-catalog` and `order-service` ClusterIP services use `port: 80`
instead of matching what the frontend nginx expects (8082 and 8081 respectively).

---

## Fix

### Change 1 — `shopping-cart-product-catalog/k8s/base/service.yaml`

**Exact old block:**
```yaml
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 80
    targetPort: http
    protocol: TCP
```

**Exact new block:**
```yaml
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 8082
    targetPort: http
    protocol: TCP
```

---

### Change 2 — `shopping-cart-order/k8s/base/service.yaml`

**Exact old block:**
```yaml
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 80
    targetPort: http
    protocol: TCP
```

**Exact new block:**
```yaml
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 8081
    targetPort: http
    protocol: TCP
```

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| `shopping-cart-product-catalog` | `k8s/base/service.yaml` | ClusterIP port 80 → 8082 |
| `shopping-cart-order` | `k8s/base/service.yaml` | ClusterIP port 80 → 8081 |

---

## Rules

- No other files modified in either repo
- NodePort services in the same files are NOT touched — they stay on port 80
- Do NOT touch `shopping-cart-basket` — its service already exposes port 8083 correctly

---

## Definition of Done

- [ ] `shopping-cart-product-catalog/k8s/base/service.yaml` ClusterIP port changed to 8082
- [ ] `shopping-cart-order/k8s/base/service.yaml` ClusterIP port changed to 8081
- [ ] Committed to `fix/argocd-shared-namespace` in each repo
- [ ] `git push origin fix/argocd-shared-namespace` in each repo — do NOT report done until both pushes succeed
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` (in k3d-manager) with commit SHAs and task status
- [ ] Report back: one SHA per repo + `git show <sha> --stat` for each

**Commit message (exact, both repos):**
```
fix(service): set ClusterIP port to match frontend nginx upstream config
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT touch NodePort service definitions
- Do NOT touch `shopping-cart-basket`
- Do NOT commit to `main`
