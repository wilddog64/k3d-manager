# Follow-on: product-catalog — schema self-heal integration test in CI

**Branch:** `k3d-manager-v1.4.9` (spec only — code changes in shopping-cart-product-catalog)
**Files:**
- `.github/workflows/ci.yml`
- `tests/integration/test_schema_selfheal.py`
- `pyproject.toml`

---

## Before You Start

**Branch (work repo):** `fix/product-catalog-schema-mismatch` in `shopping-cart-product-catalog`
(same branch as the schema mismatch fix — do not create a new branch)

```bash
# Step 1 — get the spec (k3d-manager repo)
git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.9

# Step 2 — read this spec in full before touching anything

# Step 3 — check out the existing branch in the work repo
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog \
  checkout fix/product-catalog-schema-mismatch

# Step 4 — read the target files before editing
# .github/workflows/ci.yml
# pyproject.toml
# tests/integration/__init__.py  (exists — empty)
```

---

## Context

`_recreate_products_if_schema_mismatch()` was implemented in the previous task (SHA `939a02c`).
The unit tests cover it with mocks. This task adds a real-database integration test to CI
so the self-heal is verified end-to-end on every PR — not just in unit mocks.

---

## Problem

`pytest --maxfail=1 --disable-warnings -q` in the `build` CI job runs ALL tests in
`testpaths = ["tests"]`, including any files placed in `tests/integration/`. Without a
PostgreSQL service, integration tests will fail in the `build` job.

The fix: mark integration tests with `@pytest.mark.integration`, exclude them from the
`build` job, and run them in a dedicated `integration-test` job with a real PostgreSQL
service container.

---

## Fix

### Change 1 — `pyproject.toml`: register the `integration` marker

**Exact old block:**

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
```

**Exact new block:**

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
asyncio_mode = "auto"
markers = [
    "integration: tests that require a live database (deselect with '-m not integration')",
]
```

---

### Change 2 — `.github/workflows/ci.yml`: exclude integration tests from `build` job

**Exact old line (inside the `build` job's "Run tests" step):**

```yaml
      - name: Run tests
        run: pytest --maxfail=1 --disable-warnings -q
```

**Exact new line:**

```yaml
      - name: Run tests
        run: pytest -m "not integration" --maxfail=1 --disable-warnings -q
```

---

### Change 3 — `.github/workflows/ci.yml`: add `integration-test` job

Add this job after the `build` job (before `security-scan`):

```yaml
  integration-test:
    name: Integration Test — Schema Self-Heal
    needs: [lint]
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_DB: products
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    env:
      DATABASE_URL: postgresql://postgres:postgres@localhost:5432/products
      ENVIRONMENT: sandbox
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install .[dev]

      - name: Run integration tests
        run: pytest -m integration -v
```

---

### Change 4 — `tests/integration/test_schema_selfheal.py`: new file

```python
"""Integration test: schema self-heal on stale products table."""

import pytest
from sqlalchemy import inspect as sa_inspect, text

from product_catalog import database as db_module


@pytest.mark.integration
def test_init_db_recreates_stale_products_table():
    """init_db() must drop and recreate products when old schema is present."""
    with db_module.engine.begin() as conn:
        conn.execute(text("DROP TABLE IF EXISTS products CASCADE"))
        conn.execute(text("""
            CREATE TABLE products (
                id SERIAL PRIMARY KEY,
                sku VARCHAR(50) UNIQUE NOT NULL,
                name VARCHAR(255) NOT NULL,
                price NUMERIC(10,2) NOT NULL,
                inventory_count INTEGER NOT NULL DEFAULT 0
            )
        """))

    db_module.init_db()

    inspector = sa_inspect(db_module.engine)
    cols = {c["name"] for c in inspector.get_columns("products")}
    assert "currency" in cols
    assert "quantity" in cols
    assert "inventory_count" not in cols
```

---

## Files Changed

| File | Change |
|------|--------|
| `pyproject.toml` | Add `markers` entry under `[tool.pytest.ini_options]` |
| `.github/workflows/ci.yml` | Exclude integration tests from `build` job; add `integration-test` job |
| `tests/integration/test_schema_selfheal.py` | New file — 1 integration test |

---

## Rules

- `ruff check src/ tests/` — zero new warnings
- `pytest -m "not integration" --maxfail=1 --disable-warnings -q` — all unit tests still pass
- No other files touched

---

## Definition of Done

- [ ] `pyproject.toml` has `markers` entry as shown above
- [ ] `build` job's pytest command is `-m "not integration" --maxfail=1 --disable-warnings -q`
- [ ] `integration-test` job added to `ci.yml` exactly as shown, with `needs: [lint]`
- [ ] `tests/integration/test_schema_selfheal.py` created with `@pytest.mark.integration`
- [ ] `ruff check src/ tests/` passes with zero new warnings
- [ ] `pytest -m "not integration" --maxfail=1 --disable-warnings -q` passes locally (no DB needed)
- [ ] Committed and pushed to `fix/product-catalog-schema-mismatch` on `origin`

**Commit message (exact):**
```
test(ci): add integration test for products schema self-heal
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the listed targets
- Do NOT commit to `main` — work on `fix/product-catalog-schema-mismatch`
- Do NOT run the integration test locally — it requires a live PostgreSQL instance
- Do NOT add `asyncio_mode` or any other pytest config changes beyond the `markers` entry
