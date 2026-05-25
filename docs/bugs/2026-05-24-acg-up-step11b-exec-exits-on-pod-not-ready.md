# Bug: acg-up step 11b kubectl exec exits script when product-catalog pod not ready

**Date:** 2026-05-24
**File:** `bin/acg-up`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

Step 11b checks for a DB_PASSWORD mismatch by exec-ing into the running pod:

```bash
_pc_db_pw=$(kubectl exec -n shopping-cart-apps --context ubuntu-k3s \
  deploy/product-catalog -- sh -c 'echo $DB_PASSWORD' 2>/dev/null | tr -d '[:space:]')
```

On a fresh cluster rebuild the `product-catalog` deployment exists (deployed by an earlier
step) but the pod is still starting or in CrashLoopBackOff. `kubectl exec` returns non-zero.
With `set -euo pipefail` the unguarded assignment exits the script:

```
INFO: [acg-up] ESO force-sync triggered for product-catalog-secrets
make: *** [up] Error 1
```

The mismatch check and rollout restart are unnecessary when the pod hasn't started yet —
the pod will pick up the correct ESO-synced secret on first start.

---

## Root Cause

Line 1430–1431 — `_pc_db_pw=$(kubectl exec ...)` is unguarded. If exec fails (pod not
ready), `set -e` fires and kills the script.

The condition on line 1433 also does not gate on whether exec produced a non-empty result,
so even if the assignment were guarded with `|| _pc_db_pw=""`, it would trigger a
rollout restart unnecessarily (restarting a pod that is still initialising).

---

## Fix

### Change 1 — `bin/acg-up`: guard exec assignment and add `-n` check to mismatch condition

**Exact old block (lines 1430–1433):**

```bash
  _pc_db_pw=$(kubectl exec -n shopping-cart-apps --context ubuntu-k3s \
    deploy/product-catalog -- sh -c 'echo $DB_PASSWORD' 2>/dev/null | tr -d '[:space:]')
  if [[ "${_pc_db_pw}" != "${_pg_pass_products}" ]]; then
```

**Exact new block:**

```bash
  _pc_db_pw=$(kubectl exec -n shopping-cart-apps --context ubuntu-k3s \
    deploy/product-catalog -- sh -c 'echo $DB_PASSWORD' 2>/dev/null | tr -d '[:space:]') || _pc_db_pw=""
  if [[ -n "${_pc_db_pw}" && "${_pc_db_pw}" != "${_pg_pass_products}" ]]; then
```

**What changes:**
- `|| _pc_db_pw=""` — exec failure is no longer fatal; pod not ready → empty string
- `-n "${_pc_db_pw}"` added to condition — skips rollout restart when pod was unreachable

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Guard `_pc_db_pw` assignment; add `-n` to mismatch condition |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] Line 1431 ends with `|| _pc_db_pw=""`
- [ ] Line 1433 condition starts with `[[ -n "${_pc_db_pw}" && "${_pc_db_pw}" != ...`
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-up): guard step-11b exec — skip mismatch check when product-catalog pod not ready
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
- Do NOT remove or restructure the surrounding `if kubectl get deployment` block — only touch lines 1430–1433
