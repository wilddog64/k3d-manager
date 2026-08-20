# Bug: Step 11b psql final-count exits script after seed job completes or fails

**Date:** 2026-05-24
**File:** `bin/acg-up`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

After the seed job loop exits (either `_seed_failed=True` or `_seed_done=true`), the
script runs an unguarded command substitution:

```bash
_final_count=$(kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
  psql -U postgres -d products -tAc "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d '[:space:]')
```

**Root cause:** On a fresh cluster the seed job may fail because `product-catalog-secrets`
is not yet provisioned (ESO takes time to sync from Vault) or `postgresql-products-0` is
not fully ready. When the seed job fails, the WARN on line 1447 fires and breaks the loop,
then the unguarded psql on line 1452 fails. With `set -euo pipefail` a command-substitution
assignment propagates the non-zero exit, terminating the script before Step 12 runs.

---

## Fix

### Change 1 — `bin/acg-up`: guard `_final_count` psql with `|| _final_count=0`

**Exact old block (lines 1452–1453):**

```bash
    _final_count=$(kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
      psql -U postgres -d products -tAc "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d '[:space:]')
```

**Exact new block:**

```bash
    _final_count=$(kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
      psql -U postgres -d products -tAc "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d '[:space:]') \
      || _final_count=0
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add `|| _final_count=0` guard to psql command substitution at line 1452 |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `bin/acg-up` updated — `|| _final_count=0` added after the psql command substitution
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-up): guard step-11b psql final-count — unguarded after seed job exits script
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
