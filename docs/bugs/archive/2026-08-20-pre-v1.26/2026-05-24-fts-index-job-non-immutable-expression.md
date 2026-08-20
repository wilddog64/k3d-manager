# Bug: product-catalog-fts-index job fails — to_tsvector non-IMMUTABLE in GIN index

**Date:** 2026-05-24
**File:** `shopping-cart-product-catalog/k8s/base/fts-index-job.yaml`
**Branch:** `docs/next-improvements` (shopping-cart-product-catalog)

---

## Problem

`product-catalog-fts-index` ArgoCD PostSync Job fails with:

```
ERROR: functions in index expression must be marked IMMUTABLE
```

**Root cause:** PostgreSQL 15 requires all functions in a GIN index expression to be
IMMUTABLE. `to_tsvector(text, text)` where the first arg is a `text` literal (not a
`regconfig` literal) involves a non-IMMUTABLE cast from `text` → `regconfig` internally,
causing PG to reject the index creation even with `'pg_catalog.english'::regconfig`.

The current job SQL:
```sql
CREATE INDEX IF NOT EXISTS products_fts_idx
  ON products
  USING GIN(to_tsvector('english', concat_ws(' ', name, description, category)));
```

The API (`routers/products.py` lines 44–48) generates the same `to_tsvector('english', ...)`
expression at runtime — which works fine in queries (IMMUTABLE requirement is only for
index expressions). So FTS search works via sequential scan; the index just doesn't get created.

**Workaround applied manually:** Created an `IMMUTABLE` wrapper function + index directly
in PostgreSQL so FTS search benefits from the GIN index for the current cluster. The job
still needs to be fixed so it works on the next cluster rebuild.

---

## Fix

### Change 1 — `k8s/base/fts-index-job.yaml`: use IMMUTABLE wrapper function

Replace the single `CREATE INDEX` statement with a two-step approach: create the IMMUTABLE
wrapper function first, then create the index on it.

**Exact old SQL block in the job container command:**

```sql
CREATE INDEX IF NOT EXISTS products_fts_idx
  ON products
  USING GIN(to_tsvector('english', concat_ws(' ', name, description, category)));
```

**Exact new SQL block:**

```sql
CREATE OR REPLACE FUNCTION products_search_vector(name text, description text, category text)
RETURNS tsvector LANGUAGE sql IMMUTABLE AS $$
  SELECT to_tsvector('pg_catalog.english', concat_ws(' ', name, description, category))
$$;

CREATE INDEX IF NOT EXISTS products_fts_idx
  ON products
  USING GIN(products_search_vector(name, description, category));
```

### Change 2 — `src/product_catalog/routers/products.py` lines 44–48: use wrapper function

The API must use the same expression as the index or the index will not be used.

**Exact old block:**

```python
        search_vector = func.to_tsvector(
            "english",
            func.concat_ws(" ", Product.name, Product.description, Product.category),
        )
        query = query.filter(search_vector.op("@@")(func.plainto_tsquery("english", q)))
```

**Exact new block:**

```python
        search_vector = func.products_search_vector(
            Product.name, Product.description, Product.category
        )
        query = query.filter(search_vector.op("@@")(func.plainto_tsquery("pg_catalog.english", q)))
```

---

## Files Changed

| File | Change |
|------|--------|
| `k8s/base/fts-index-job.yaml` | Replace direct `to_tsvector` GIN index with IMMUTABLE wrapper function + index |
| `src/product_catalog/routers/products.py` | Update FTS query to call `products_search_vector` so index is used |

---

## Rules

- `kubectl kustomize k8s/base/` must produce zero warnings
- `node --check` is not applicable (Python file)
- No other files touched

---

## Definition of Done

- [ ] `k8s/base/fts-index-job.yaml` updated with two-step SQL
- [ ] `src/product_catalog/routers/products.py` updated to call `products_search_vector`
- [ ] `kubectl kustomize k8s/base/` produces no warnings
- [ ] Committed with message: `fix(fts-index): use IMMUTABLE wrapper function — to_tsvector non-IMMUTABLE in GIN index`
- [ ] Pushed to `origin docs/next-improvements`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(fts-index): use IMMUTABLE wrapper function — to_tsvector non-IMMUTABLE in GIN index
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed above
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT remove the `IF NOT EXISTS` from the CREATE INDEX — idempotency required
