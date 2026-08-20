# Bug: acg-status Missing Shopping Cart App Health

**File:** `bin/acg-status`
**Branch:** `k3d-manager-v1.2.0`
**Severity:** Medium — operators cannot see shopping-cart app sync/health from `make status`

---

## Symptom

`make status` shows Hub pods and app cluster nodes but provides no visibility into shopping-cart
application health. The `=== Pods — all namespaces (ubuntu-k3s) ===` section floods output
with system pods (kube-system, istio-system, etc.) and the `=== ArgoCD Apps ===` section
prints raw `kubectl get applications` output with no SYNC or HEALTH columns visible in the
default narrow format.

---

## Root Cause

Two issues in `bin/acg-status`:

1. **App cluster pods section** (lines 46–49) runs `kubectl get pods -A` on the app cluster —
   shows all system pods with no namespace filter, burying any shopping-cart pods.
2. **ArgoCD Apps section** (lines 51–54) uses default column output which omits SYNC STATUS
   and HEALTH STATUS columns — the most useful fields for operators.

---

## Fix

### Change 1 — Replace app cluster pods section with shopping-cart namespace filter

**Old (lines 46–49):**
```bash
echo ""
echo "=== Pods — all namespaces (${APP_CONTEXT}) ==="
kubectl get pods -A --context "${APP_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach app cluster"
```

**New:**
```bash
echo ""
echo "=== App Pods — shopping-cart namespaces (${APP_CONTEXT}) ==="
_app_pod_output="$(kubectl get pods -A --context "${APP_CONTEXT}" 2>/dev/null \
  | awk 'NR==1 || /^shopping-cart/' || true)"
if [[ -z "${_app_pod_output}" || "${_app_pod_output}" == "$(echo "${_app_pod_output}" | head -1)" ]]; then
  echo "No shopping-cart pods found — run make sync-apps"
else
  echo "${_app_pod_output}"
fi
```

### Change 2 — Replace ArgoCD Apps section with SYNC + HEALTH table

**Old (lines 51–54):**
```bash
echo ""
echo "=== ArgoCD Apps ==="
kubectl get applications.argoproj.io -A --context "${INFRA_CONTEXT}" 2>/dev/null \
  || echo "Cannot reach Hub cluster or ArgoCD CRDs not installed"
```

**New:**
```bash
echo ""
echo "=== ArgoCD App Health ==="
kubectl get applications.argoproj.io -A --context "${INFRA_CONTEXT}" \
  -o custom-columns='NAMESPACE:.metadata.namespace,NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' \
  2>/dev/null \
  || echo "Cannot reach Hub cluster or ArgoCD CRDs not installed"
```

---

## Expected Output After Fix

```
=== App Pods — shopping-cart namespaces (ubuntu-k3s) ===
NAMESPACE                    NAME                                    READY   STATUS    RESTARTS   AGE
shopping-cart-basket         basket-7d9f8b-xk2pq                    1/1     Running   0          5m
shopping-cart-order          order-6c4d9f-tn3rs                      1/1     Running   0          5m

=== ArgoCD App Health ===
NAMESPACE   NAME              SYNC      HEALTH
cicd        basket            Synced    Healthy
cicd        order             Synced    Healthy
cicd        rollout-demo      Synced    Healthy
```

---

## Definition of Done

- [ ] Change 1 applied: app cluster pods section filters to `shopping-cart` namespaces only
- [ ] Change 2 applied: ArgoCD Apps section uses custom-columns showing SYNC + HEALTH
- [ ] `shellcheck bin/acg-status` passes with zero new warnings
- [ ] Committed on branch `k3d-manager-v1.2.0` with message:
  `fix(acg-status): show shopping-cart pod filter and ArgoCD sync/health columns`
- [ ] SHA reported; pushed to origin before reporting done

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-status`
- Do NOT commit to `main`
- Do NOT add error handling for scenarios that cannot happen (kubectl is always available when the script runs)
