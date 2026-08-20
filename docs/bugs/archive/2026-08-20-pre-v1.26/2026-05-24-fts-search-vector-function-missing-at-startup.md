# Bug: products_search_vector function only created by PostSync job — API 500s before hook runs

**Date:** 2026-05-24
**Repo:** `shopping-cart-product-catalog`
**Branch:** `docs/next-improvements`
**Copilot finding:** PR #25, comments on `src/product_catalog/routers/products.py` line 47
  and `k8s/base/fts-index-job.yaml` line 45

---

## Problem

`GET /api/products?q=...` 500s with `undefined function: products_search_vector` any time
the ArgoCD PostSync hook has not yet run — including the PostSync window itself, local dev,
and tests. The API calls `products_search_vector(...)` at query time but the function is
only created by the `product-catalog-fts-index` PostSync Job.

---

## Fix

### Change 1 — `src/product_catalog/database.py`: create function in `init_db()`

Add a `text()` DDL execute after `create_all` so the function always exists when the app
starts, regardless of whether the PostSync hook has run.

**Add `text` to the existing sqlalchemy imports.**

**Exact old `init_db` block:**

```python
def init_db() -> None:
    """Initialize database tables."""
    Base.metadata.create_all(bind=engine)
```

**Exact new `init_db` block:**

```python
def init_db() -> None:
    """Initialize database tables."""
    Base.metadata.create_all(bind=engine)
    with engine.connect() as conn:
        conn.execute(text("""
            CREATE OR REPLACE FUNCTION products_search_vector(
                name text,
                description text,
                category text
            )
            RETURNS tsvector LANGUAGE sql IMMUTABLE AS $$
                SELECT to_tsvector('pg_catalog.english', concat_ws(' ', name, description, category))
            $$
        """))
        conn.commit()
```

**Import line to add** (add `text` to the existing sqlalchemy import at the top of database.py):

```python
from sqlalchemy import create_engine, text
```

---

### Change 2 — `k8s/base/fts-index-job.yaml`: remove function creation — keep only CREATE INDEX

Since the function is now created by `init_db()` at app startup, the PostSync job only
needs to create the index.

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
| `src/product_catalog/database.py` | Add `products_search_vector` DDL to `init_db()`; add `text` to sqlalchemy import |
| `k8s/base/fts-index-job.yaml` | Remove `CREATE OR REPLACE FUNCTION` block — keep only `CREATE INDEX IF NOT EXISTS` |

---

## Rules

- No other files touched
- `kubectl kustomize k8s/base/` must produce zero warnings after change

---

## Definition of Done

- [ ] `src/product_catalog/database.py` updated — `text` imported, function DDL in `init_db()`
- [ ] `k8s/base/fts-index-job.yaml` updated — only `CREATE INDEX IF NOT EXISTS` remains
- [ ] `kubectl kustomize k8s/base/` produces no warnings
- [ ] Committed with message: `fix(db): create products_search_vector in init_db — not only in PostSync hook`
- [ ] Pushed to `origin docs/next-improvements`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(db): create products_search_vector in init_db — not only in PostSync hook
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed above
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT remove the `IF NOT EXISTS` from the CREATE INDEX
