# Bug: fts-index-job CREATE FUNCTION fails — busybox ash strips $$ in heredoc

**Date:** 2026-05-24
**File:** `shopping-cart-product-catalog/k8s/base/fts-index-job.yaml`
**Branch:** `docs/next-improvements` (shopping-cart-product-catalog)

---

## Problem

`product-catalog-fts-index` PostSync Job fails with:

```
ERROR:  syntax error at or near "$"
LINE 9: AS $
           ^
```

**Root cause:** `postgres:15-alpine` uses busybox `ash` as `/bin/sh`. Busybox ash silently
strips one `$` from `$$` in a single-quoted heredoc (`<<'SQL'`), even though POSIX requires
`$$` to be passed verbatim in a quoted heredoc. PostgreSQL's dollar-quoting `$$...$$ ` arrives
as `$...$` and fails to parse.

The function `products_search_vector` was re-added to the PostSync job by PR #26's merge
from main, re-introducing the `$$` quoting issue that the original fix (commit `73c03f0`)
had already resolved by moving the function to `init_db()`.

**Why removing it is now safe:** The product-catalog Deployment has a readiness probe
(`/ready`). ArgoCD only runs PostSync hooks after the Deployment is healthy (readiness
probe passing). By that point, `init_db()` has already executed and
`products_search_vector` exists in PostgreSQL.

---

## Fix

### Change 1 — `k8s/base/fts-index-job.yaml`: remove function creation, keep only index

**Exact old SQL block in the job container command:**

```sql
            CREATE OR REPLACE FUNCTION products_search_vector(
              name text,
              description text,
              category text
            )
            RETURNS tsvector
            LANGUAGE sql
            IMMUTABLE
            AS $$
              SELECT to_tsvector(
                'pg_catalog.english',
                concat_ws(' ', name, description, category)
              );
            $$;

            CREATE INDEX IF NOT EXISTS products_fts_idx
              ON products
              USING GIN(products_search_vector(name, description, category));
```

**Exact new SQL block:**

```sql
            CREATE INDEX IF NOT EXISTS products_fts_idx
              ON products
              USING GIN(products_search_vector(name, description, category));
```

---

## Files Changed

| File | Change |
|------|--------|
| `k8s/base/fts-index-job.yaml` | Remove `CREATE OR REPLACE FUNCTION` block — keep only `CREATE INDEX IF NOT EXISTS` |

---

## Rules

- `kubectl kustomize k8s/base/` must produce zero warnings after change
- No other files touched

---

## Definition of Done

- [ ] `k8s/base/fts-index-job.yaml` updated — only `CREATE INDEX IF NOT EXISTS` remains
- [ ] `kubectl kustomize k8s/base/` produces no warnings
- [ ] Committed with message: `fix(fts-index): remove CREATE FUNCTION from PostSync job — busybox ash strips $$ in heredoc`
- [ ] Pushed to `origin docs/next-improvements`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(fts-index): remove CREATE FUNCTION from PostSync job — busybox ash strips $$ in heredoc
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `k8s/base/fts-index-job.yaml`
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT remove the `IF NOT EXISTS` from the CREATE INDEX
- Do NOT add the function back using named dollar quoting — the function belongs in `init_db()` only
