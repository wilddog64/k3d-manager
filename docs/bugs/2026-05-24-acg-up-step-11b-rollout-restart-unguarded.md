# Bug: Step 11b rollout restart fails on fresh cluster — product-catalog not yet deployed

**Date:** 2026-05-24
**File:** `bin/acg-up`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

`make up` exits with `Error 1` immediately after printing:

```
INFO: [acg-up] PostgreSQL products password reconciled with Vault
```

**Root cause:** On a fresh cluster, `product-catalog` deployment does not exist yet
(ArgoCD is still syncing). Step 11b reaches the DB_PASSWORD mismatch check: empty
`_pc_db_pw` ≠ non-empty `_pg_intended_pw`, so it enters the restart block and runs:

```bash
kubectl rollout restart deployment/product-catalog \
  -n shopping-cart-apps --context ubuntu-k3s >/dev/null
```

The deployment does not exist → `kubectl rollout restart` exits non-zero → `set -euo pipefail`
terminates the script. The `kubectl rollout status` line on the next line has a `|| _info`
guard but the `rollout restart` line does not.

---

## Fix

### Change 1 — `bin/acg-up`: guard rollout restart with deployment existence check

**Exact old block (lines 1409–1416):**

```bash
  _pc_db_pw=$(kubectl exec -n shopping-cart-apps --context ubuntu-k3s \
    deploy/product-catalog -- sh -c 'echo $DB_PASSWORD' 2>/dev/null | tr -d '[:space:]')
  if [[ "${_pc_db_pw}" != "${_pg_intended_pw}" ]]; then
    _info "[acg-up] product-catalog DB_PASSWORD mismatch — restarting to pick up ESO secret..."
    kubectl rollout restart deployment/product-catalog \
      -n shopping-cart-apps --context ubuntu-k3s >/dev/null
    kubectl rollout status deployment/product-catalog \
      -n shopping-cart-apps --context ubuntu-k3s --timeout=120s 2>/dev/null \
      || _info "[acg-up] WARN: product-catalog rollout did not finish within 120s"
  fi
```

**Exact new block:**

```bash
  if kubectl get deployment product-catalog \
      -n shopping-cart-apps --context ubuntu-k3s >/dev/null 2>&1; then
    _pc_db_pw=$(kubectl exec -n shopping-cart-apps --context ubuntu-k3s \
      deploy/product-catalog -- sh -c 'echo $DB_PASSWORD' 2>/dev/null | tr -d '[:space:]')
    if [[ "${_pc_db_pw}" != "${_pg_intended_pw}" ]]; then
      _info "[acg-up] product-catalog DB_PASSWORD mismatch — restarting to pick up ESO secret..."
      kubectl rollout restart deployment/product-catalog \
        -n shopping-cart-apps --context ubuntu-k3s >/dev/null \
        || _info "[acg-up] WARN: could not restart product-catalog"
      kubectl rollout status deployment/product-catalog \
        -n shopping-cart-apps --context ubuntu-k3s --timeout=120s 2>/dev/null \
        || _info "[acg-up] WARN: product-catalog rollout did not finish within 120s"
    fi
  else
    _info "[acg-up] product-catalog not yet deployed — skipping DB_PASSWORD mismatch check"
  fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Guard rollout restart with deployment existence check; skip mismatch block when deployment absent |

---

## Definition of Done

- [ ] `bin/acg-up` updated with guarded block
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] `make up` completes past Step 11b on fresh cluster

**Commit message (exact):**
```
fix(acg-up): guard step-11b rollout restart — deployment absent on fresh cluster
```
