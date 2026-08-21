# Bug: Step 11b psql product count exits script on fresh cluster

**Date:** 2026-05-24
**File:** `bin/acg-up`
**Branch:** `k3d-manager-v1.4.9`

---

## Problem

`make up` exits with `Error 1` immediately after printing:

```
INFO: [acg-up] product-catalog not yet deployed — skipping DB_PASSWORD mismatch check
```

No further output. The deployment existence check (added earlier) correctly skips the
restart block, but the very next statement is an unguarded command substitution:

```bash
_product_count=$(kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
  psql -U postgres -d products -tAc "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d '[:space:]')
```

**Root cause:** On a fresh cluster the `products` database may not exist yet or
`postgresql-products-0` may not be ready. The `psql` call fails (non-zero exit). With
`set -euo pipefail` a command-substitution assignment propagates that non-zero exit,
terminating the script before Step 12 runs.

---

## Fix

### Change 1 — `bin/acg-up`: guard `_product_count` psql with `|| _product_count=0`

**Exact old block (lines 1422–1423):**

```bash
_product_count=$(kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
  psql -U postgres -d products -tAc "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d '[:space:]')
```

**Exact new block:**

```bash
_product_count=$(kubectl exec -n shopping-cart-data --context ubuntu-k3s postgresql-products-0 -- \
  psql -U postgres -d products -tAc "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d '[:space:]') \
  || _product_count=0
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add `|| _product_count=0` guard to psql command substitution at line 1422 |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `bin/acg-up` updated — `|| _product_count=0` added after the psql command substitution
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-up): guard step-11b psql product-count — unguarded on fresh cluster exits script
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
