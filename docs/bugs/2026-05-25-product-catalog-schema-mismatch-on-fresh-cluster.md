# Bugfix: product-catalog — products table schema mismatch on fresh cluster

**Branch:** `k3d-manager-v1.4.9` (spec only — code changes in shopping-cart-product-catalog)
**Files:** `src/product_catalog/database.py`, `tests/unit/test_database.py`

---

## Before You Start

**Branch (work repo):** `fix/product-catalog-schema-mismatch` in `shopping-cart-product-catalog`

```bash
# Step 1 — get the spec (k3d-manager repo)
git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.9

# Step 2 — read this spec in full before touching anything

# Step 3 — create feature branch in the work repo
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog \
  checkout -b fix/product-catalog-schema-mismatch origin/main

# Step 4 — read the target files before editing
# src/product_catalog/database.py
# tests/unit/ (existing tests for style reference)
```

---

## Problem

On a fresh cluster, the `products` table is sometimes created with an old schema
(`id INTEGER`, `inventory_count`, no `currency`) instead of the SQLAlchemy model
schema (`id UUID`, `quantity`, `currency`). When this happens, `create_all()` sees
the table already exists and skips it. The seed job then fails:

```
psycopg2.errors.UndefinedColumn: column "currency" of relation "products" does not exist
```

**Root cause:** `create_all()` never alters existing tables — it only creates missing
ones. If the `products` table was created by an old DDL (before the init-SQL cleanup in
v0.5.0) or by an earlier pod run with a stale image, `create_all()` silently no-ops
and the mismatch persists across restarts.

---

## Reproduction

1. Create a `products` table in PostgreSQL with the old schema:
   ```sql
   CREATE TABLE products (
     id SERIAL PRIMARY KEY,
     sku VARCHAR(50) UNIQUE NOT NULL,
     name VARCHAR(255) NOT NULL,
     description TEXT,
     price NUMERIC(10,2) NOT NULL,
     inventory_count INTEGER NOT NULL DEFAULT 0
   );
   ```
2. Start `product-catalog` — `init_db()` runs, `create_all()` no-ops (table exists).
3. Run the seed job — fails on `INSERT` with `UndefinedColumn: currency`.

---

## Fix

### Change 1 — `src/product_catalog/database.py`: schema-mismatch guard in `init_db()`

Add a check before `create_all()`: inspect the live `products` table's columns against
the model's expected column set. If any model column is absent **and** the environment
is not `production`, drop the table so `create_all()` recreates it correctly.

**Exact old block (lines 43–56):**

```python
def init_db() -> None:
    """Initialize database tables."""
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
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
```

**Exact new block:**

```python
def init_db() -> None:
    """Initialize database tables."""
    _recreate_products_if_schema_mismatch()
    Base.metadata.create_all(bind=engine)
    with engine.begin() as conn:
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


def _recreate_products_if_schema_mismatch() -> None:
    from sqlalchemy import inspect as sa_inspect
    from .models import Product

    inspector = sa_inspect(engine)
    if not inspector.has_table("products"):
        return

    actual_cols = {c["name"] for c in inspector.get_columns("products")}
    expected_cols = {col.name for col in Product.__table__.columns}
    missing = expected_cols - actual_cols

    if not missing:
        return

    if settings.environment == "production":
        import logging
        logging.getLogger(__name__).warning(
            "products schema mismatch detected in production — skipping recreation; "
            "missing columns: %s", missing
        )
        return

    with engine.begin() as conn:
        conn.execute(text("DROP TABLE IF EXISTS products CASCADE"))
```

---

## Tests

### New file: `tests/unit/test_database.py`

Three cases must pass. Use `unittest.mock` — no real DB required.

```python
"""Unit tests for database schema-mismatch guard."""

from unittest.mock import MagicMock, patch, call
import pytest


class TestRecreatProductsIfSchemaMismatch:
    """Tests for _recreate_products_if_schema_mismatch."""

    def _call(self):
        from product_catalog.database import _recreate_products_if_schema_mismatch
        _recreate_products_if_schema_mismatch()

    def test_no_op_when_table_missing(self):
        """Should not DROP when products table does not exist yet."""
        mock_inspector = MagicMock()
        mock_inspector.has_table.return_value = False

        with patch("product_catalog.database.sa_inspect", return_value=mock_inspector), \
             patch("product_catalog.database.engine") as mock_engine:
            self._call()
            mock_engine.begin.assert_not_called()

    def test_no_op_when_schema_correct(self):
        """Should not DROP when all model columns are present."""
        from product_catalog.models import Product
        all_cols = [{"name": c.name} for c in Product.__table__.columns]

        mock_inspector = MagicMock()
        mock_inspector.has_table.return_value = True
        mock_inspector.get_columns.return_value = all_cols

        with patch("product_catalog.database.sa_inspect", return_value=mock_inspector), \
             patch("product_catalog.database.engine") as mock_engine:
            self._call()
            mock_engine.begin.assert_not_called()

    def test_drops_table_when_columns_missing_in_sandbox(self):
        """Should DROP products when model columns are absent and env != production."""
        old_schema_cols = [
            {"name": "id"}, {"name": "sku"}, {"name": "name"},
            {"name": "price"}, {"name": "inventory_count"},
        ]
        mock_inspector = MagicMock()
        mock_inspector.has_table.return_value = True
        mock_inspector.get_columns.return_value = old_schema_cols

        mock_conn = MagicMock()
        mock_ctx = MagicMock(__enter__=MagicMock(return_value=mock_conn),
                             __exit__=MagicMock(return_value=False))

        with patch("product_catalog.database.sa_inspect", return_value=mock_inspector), \
             patch("product_catalog.database.engine") as mock_engine, \
             patch("product_catalog.database.settings") as mock_settings:
            mock_engine.begin.return_value = mock_ctx
            mock_settings.environment = "sandbox"
            self._call()

        mock_engine.begin.assert_called_once()
        executed_sql = mock_conn.execute.call_args[0][0].text
        assert "DROP TABLE" in executed_sql.upper()
        assert "products" in executed_sql

    def test_skips_drop_in_production(self):
        """Should NOT DROP even when columns are missing if env == production."""
        old_schema_cols = [{"name": "id"}, {"name": "sku"}]
        mock_inspector = MagicMock()
        mock_inspector.has_table.return_value = True
        mock_inspector.get_columns.return_value = old_schema_cols

        with patch("product_catalog.database.sa_inspect", return_value=mock_inspector), \
             patch("product_catalog.database.engine") as mock_engine, \
             patch("product_catalog.database.settings") as mock_settings:
            mock_settings.environment = "production"
            self._call()

        mock_engine.begin.assert_not_called()
```

---

## Files Changed

| File | Change |
|------|--------|
| `src/product_catalog/database.py` | Add `_recreate_products_if_schema_mismatch()` called at top of `init_db()` |
| `tests/unit/test_database.py` | New file — 4 unit tests for the guard |

---

## Rules

- `ruff check src/ tests/` — zero new warnings
- `mypy src/` — zero new errors
- `pytest tests/unit/test_database.py -v` — all 4 tests pass
- No other files touched

---

## Definition of Done

- [ ] `_recreate_products_if_schema_mismatch()` implemented exactly as above
- [ ] `tests/unit/test_database.py` created with all 4 tests
- [ ] `pytest tests/unit/test_database.py -v` passes — all 4 green
- [ ] `ruff check src/ tests/` passes with zero new warnings
- [ ] `mypy src/` passes with zero new errors
- [ ] **Integration smoke test** (manual, in cluster):
  - Drop products table in PostgreSQL
  - Restart product-catalog deployment
  - Confirm `\d products` shows UUID PK + `currency` + `quantity`
  - Confirm seed job Succeeds
  - Confirm `GET /products` returns 1000 items
- [ ] Committed and pushed to feature branch in `shopping-cart-product-catalog`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(db): recreate products table on schema mismatch in non-production environments
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the listed targets
- Do NOT commit to `main` — work on a new feature branch in `shopping-cart-product-catalog`
- Do NOT use Alembic — this fix is intentionally scoped to sandbox/dev detection only
- Do NOT drop the table in production — the production guard must remain

---

## Why Integration Tests Belong in CI, Not `make up`

The seed job failure was a **schema regression** that should have been caught in
`shopping-cart-product-catalog`'s own CI pipeline, not at provision time. `make up`
is a provisioning tool — it cannot be the primary test gate for application-layer schema
correctness.

The right CI gate to add to `shopping-cart-product-catalog` (separate follow-on work):

```yaml
# .github/workflows/integration-test.yml
- name: Start PostgreSQL
  run: docker run -d -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:15

- name: Create products table with OLD schema (regression fixture)
  run: |
    psql postgresql://postgres:postgres@localhost/postgres -c "
      CREATE DATABASE products;"
    psql postgresql://postgres:postgres@localhost/products -c "
      CREATE TABLE products (
        id SERIAL PRIMARY KEY, sku VARCHAR(50) UNIQUE NOT NULL,
        name VARCHAR(255) NOT NULL, price NUMERIC(10,2) NOT NULL,
        inventory_count INTEGER NOT NULL DEFAULT 0
      );"

- name: Start service — must self-heal schema
  run: ENVIRONMENT=sandbox ... uvicorn ...

- name: Assert schema correct after startup
  run: |
    psql ... -c "\d products" | grep -q "uuid"
    psql ... -c "\d products" | grep -q "currency"
```

This test would have caught both the missing `currency` column and the INTEGER PK
mismatch before the image was pushed.
