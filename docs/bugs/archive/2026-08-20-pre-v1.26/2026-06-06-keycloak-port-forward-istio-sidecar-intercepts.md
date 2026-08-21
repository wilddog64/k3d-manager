# Bug: acg-up Keycloak port-forward hits Istio sidecar on port 80 — returns 404

**Branch:** `k3d-manager-v1.6.3`
**Files:** `bin/acg-up`

---

## Problem

`acg-up` step 10d fails to obtain a Keycloak admin token after 5 attempts. The
port-forward is set up as `svc/keycloak:80` but the Keycloak service in the `identity`
namespace runs inside an Istio-enabled cluster. Traffic to port 80 is intercepted by the
Istio sidecar proxy, which returns `404 page not found` for the Keycloak OpenID Connect
path — not Keycloak itself.

Direct port-forward to the pod on container port 8080 bypasses the sidecar and returns a
correct Keycloak JSON response.

**Root cause:** `bin/acg-up` line 719:
```bash
kubectl port-forward svc/keycloak -n identity --context k3d-k3d-cluster "${_kc_pf_port}:80"
```
Port 80 → Istio sidecar → 404. Should target `deployment/keycloak:8080` (container port)
to bypass the sidecar.

---

## Reproduction

```bash
kubectl port-forward svc/keycloak -n identity --context k3d-k3d-cluster 18080:80 &
sleep 2
curl -s http://localhost:18080/realms/master  # → "404 page not found"

kubectl port-forward deployment/keycloak -n identity --context k3d-k3d-cluster 18081:8080 &
sleep 2
curl -s http://localhost:18081/realms/master  # → proper Keycloak JSON
```

---

## Fix

### Change 1 — `bin/acg-up`: change port-forward target from svc:80 to deployment:8080

**Exact old block (line 719):**

```bash
  kubectl port-forward svc/keycloak -n identity --context k3d-k3d-cluster "${_kc_pf_port}:80" \
```

**Exact new block:**

```bash
  kubectl port-forward deployment/keycloak -n identity --context k3d-k3d-cluster "${_kc_pf_port}:8080" \
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Change Keycloak port-forward from `svc/keycloak:80` to `deployment/keycloak:8080` |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `bin/acg-up` line 719: `deployment/keycloak` with port `8080`
- [ ] `shellcheck -S warning bin/acg-up` passes
- [ ] Committed and pushed to `k3d-manager-v1.6.3`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-up): port-forward to deployment/keycloak:8080 to bypass Istio sidecar on svc port 80
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.6.3`
