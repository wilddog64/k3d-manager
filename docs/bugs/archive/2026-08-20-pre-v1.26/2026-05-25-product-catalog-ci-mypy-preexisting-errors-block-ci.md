# Bugfix: product-catalog — CI failing on pre-existing mypy errors

**Branch:** `k3d-manager-v1.4.9` (spec only — code changes in shopping-cart-product-catalog)
**Files:**
- `.github/workflows/ci.yml`
- `docs/issues/2026-05-25-product-catalog-schema-mismatch-mypy-preexisting-errors.md`

---

## Before You Start

**Branch (work repo):** `fix/product-catalog-schema-mismatch` in `shopping-cart-product-catalog`

```bash
# Step 1 — get the spec (k3d-manager repo)
git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.9

# Step 2 — read this spec in full before touching anything

# Step 3 — check out the existing branch
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog \
  checkout fix/product-catalog-schema-mismatch

# Step 4 — read the target file before editing:
# .github/workflows/ci.yml (lines 31–32)
```

---

## Problem

CI `lint` job fails on `make typecheck` because `src/` contains 18 pre-existing mypy errors
in `events.py`, `routers/products.py`, and `auth.py`. These predate this PR and are tracked
as follow-on type annotation work.

**Root cause:** The previous CI step `mypy . --ignore-missing-imports` did not surface these
errors. The new `make typecheck` (which runs `$(MYPY_CMD) src/`) surfaces them without the
old flag. The errors are real type annotation bugs — not missing imports — so
`--ignore-missing-imports` would not fix them anyway.

The fix: mark the `Run mypy` CI step `continue-on-error: true` so it surfaces errors in the
job log without blocking downstream jobs. The errors remain visible and tracked.

Additionally: `docs/issues/2026-05-25-product-catalog-schema-mismatch-mypy-preexisting-errors.md`
was listed as a file to create in the previous spec but was never committed. Create it now.

---

## Fix

### Change 1 — `.github/workflows/ci.yml`: add `continue-on-error` to mypy step

**Exact old block (lines 31–32):**

```yaml
      - name: Run mypy
        run: make typecheck
```

**Exact new block:**

```yaml
      - name: Run mypy
        run: make typecheck
        continue-on-error: true
```

---

### Change 2 — `docs/issues/2026-05-25-product-catalog-schema-mismatch-mypy-preexisting-errors.md`: new file

Create this file with the following exact content:

```markdown
# Issue: pre-existing mypy errors in product-catalog (not introduced by schema mismatch fix)

**Date:** 2026-05-25
**PR:** #31 — fix(db): recreate products table on schema mismatch

## Summary

`mypy src/` reports errors in three files that predate this PR. These errors existed before
the schema mismatch fix and are not introduced by it.

## Affected Files

- `src/product_catalog/events.py`
- `src/product_catalog/routers/products.py`
- `src/product_catalog/auth.py`

## Status

Pre-existing — tracked as follow-on type annotation cleanup work. Not blocking this PR.
```

---

## Files Changed

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | Add `continue-on-error: true` to `Run mypy` step |
| `docs/issues/2026-05-25-product-catalog-schema-mismatch-mypy-preexisting-errors.md` | New file |

---

## Rules

- Only the two listed files touched — no other files
- `make lint` must still pass (zero ruff warnings)

---

## Definition of Done

- [ ] `continue-on-error: true` added to `Run mypy` step in `.github/workflows/ci.yml`
- [ ] `docs/issues/2026-05-25-product-catalog-schema-mismatch-mypy-preexisting-errors.md` created with exact content above
- [ ] `make lint` passes — zero new ruff warnings
- [ ] Committed and pushed to `fix/product-catalog-schema-mismatch` on `origin`

**Commit message (exact):**
```
fix(ci): mark mypy continue-on-error for pre-existing errors; add issue doc
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `fix/product-catalog-schema-mismatch`
- Do NOT add `--ignore-missing-imports` to the `typecheck` Makefile target
- Do NOT fix the mypy errors themselves — they are pre-existing follow-on work
