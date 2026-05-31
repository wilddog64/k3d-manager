# Fix: product-catalog — Makefile venv wiring, CI integration, Copilot fixes

**Branch:** `k3d-manager-v1.4.9` (spec only — code changes in shopping-cart-product-catalog)
**Files:**
- `Makefile`
- `.github/workflows/ci.yml`
- `src/product_catalog/database.py`
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

# Step 4 — read these files before editing:
# Makefile (lines 1–20 for vars, lines 70–135 for test/lint targets)
# .github/workflows/ci.yml
# src/product_catalog/database.py (lines 61–84)
```

---

## Problem

Three distinct issues addressed in one commit:

1. **`make test-unit` fails** — `PYTHON := python3` resolves to system Python (3.14) which has no
   pytest installed. pytest lives in `.venv/bin/`. Codex's fix (`$(PYTHON) -m pytest`) did not
   solve the root cause.

2. **CI does not call `make` targets** — CI invokes `pytest`, `ruff`, and `mypy` directly. If
   a Makefile target is broken, CI never catches it. The Makefile should be the single source
   of truth for how tests and linting are run.

3. **Copilot PR #31 findings** (must address before merge):
   - `ci.yml`: `DATABASE_URL` env var is not read by `Settings` — set `DB_*` vars instead
   - `database.py`: DROP guard too broad — narrow to explicit dev environments
   - `database.py`: uses stdlib `logging` — codebase convention is `structlog`
   - `CHANGELOG.md` references a `docs/issues/` file that does not exist in the repo

---

## Fix

### Change 1 — `Makefile`: use `$(VENV_BIN)/pytest` and `$(VENV_BIN)/ruff`

**Exact old block (lines 12–14):**

```makefile
PYTHON := python3
PIP := pip3
VENV := .venv
VENV_BIN := $(VENV)/bin
```

**Exact new block:**

```makefile
PYTHON := python3
PIP := pip3
VENV := .venv
VENV_BIN := $(VENV)/bin
PYTEST := $(VENV_BIN)/pytest
RUFF_CMD := $(VENV_BIN)/ruff
```

**Exact old block (test targets, lines 72–103):**

```makefile
test: ## Run all tests
	@echo "${BLUE}Running all tests...${NC}"
	$(PYTHON) -m pytest tests/ -v

test-unit: ## Run unit tests only
	@echo "${BLUE}Running unit tests...${NC}"
	$(PYTHON) -m pytest tests/unit/ -v

test-integration: ## Run integration tests only
	@echo "${BLUE}Running integration tests...${NC}"
	$(PYTHON) -m pytest tests/integration/ -v

test-security: ## Run security tests only
	@echo "${BLUE}Running security tests...${NC}"
	$(PYTHON) -m pytest tests/unit/test_security*.py -v

test-cov: ## Run tests with coverage
	@echo "${BLUE}Running tests with coverage...${NC}"
	$(PYTHON) -m pytest tests/ --cov=product_catalog --cov-report=html --cov-report=term-missing
	@echo "${GREEN}Coverage report: htmlcov/index.html${NC}"

test-cov-xml: ## Run tests with coverage (XML for CI)
	@echo "${BLUE}Running tests with XML coverage...${NC}"
	$(PYTHON) -m pytest tests/ --cov=product_catalog --cov-report=xml

test-watch: ## Run tests in watch mode
	@echo "${BLUE}Running tests in watch mode...${NC}"
	ptw tests/ -- -v

test-failed: ## Re-run failed tests
	@echo "${BLUE}Re-running failed tests...${NC}"
	$(PYTHON) -m pytest tests/ --lf -v
```

**Exact new block:**

```makefile
test: ## Run all tests
	@echo "${BLUE}Running all tests...${NC}"
	$(PYTEST) tests/ -v

test-unit: ## Run unit tests only
	@echo "${BLUE}Running unit tests...${NC}"
	$(PYTEST) tests/unit/ -v

test-integration: ## Run integration tests only
	@echo "${BLUE}Running integration tests...${NC}"
	$(PYTEST) tests/integration/ -v

test-security: ## Run security tests only
	@echo "${BLUE}Running security tests...${NC}"
	$(PYTEST) tests/unit/test_security*.py -v

test-cov: ## Run tests with coverage
	@echo "${BLUE}Running tests with coverage...${NC}"
	$(PYTEST) tests/ --cov=product_catalog --cov-report=html --cov-report=term-missing
	@echo "${GREEN}Coverage report: htmlcov/index.html${NC}"

test-cov-xml: ## Run tests with coverage (XML for CI)
	@echo "${BLUE}Running tests with XML coverage...${NC}"
	$(PYTEST) tests/ --cov=product_catalog --cov-report=xml

test-watch: ## Run tests in watch mode
	@echo "${BLUE}Running tests in watch mode...${NC}"
	ptw tests/ -- -v

test-failed: ## Re-run failed tests
	@echo "${BLUE}Re-running failed tests...${NC}"
	$(PYTEST) tests/ --lf -v
```

**Exact old block (lint targets, lines 107–113):**

```makefile
lint: ## Run linter (ruff)
	@echo "${BLUE}Running linter...${NC}"
	ruff check src/ tests/

lint-fix: ## Fix linting issues
	@echo "${BLUE}Fixing linting issues...${NC}"
	ruff check src/ tests/ --fix
```

**Exact new block:**

```makefile
lint: ## Run linter (ruff)
	@echo "${BLUE}Running linter...${NC}"
	$(RUFF_CMD) check src/ tests/

lint-fix: ## Fix linting issues
	@echo "${BLUE}Fixing linting issues...${NC}"
	$(RUFF_CMD) check src/ tests/ --fix
```

---

### Change 2 — `.github/workflows/ci.yml`: create venv in every job, call `make` targets, fix DB env vars

**Exact old `lint` job steps:**

```yaml
      - name: Install lint tools
        run: pip install ruff mypy

      - name: Run ruff
        run: ruff check .

      - name: Run mypy
        run: mypy . --ignore-missing-imports
```

**Exact new `lint` job steps:**

```yaml
      - name: Install dependencies
        run: |
          python -m venv .venv
          .venv/bin/pip install --upgrade pip
          .venv/bin/pip install -e ".[dev]"

      - name: Run ruff
        run: make lint

      - name: Run mypy
        run: make typecheck
```

**Exact old `build` job steps:**

```yaml
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install .[dev]

      - name: Run tests
        run: pytest -m "not integration" --maxfail=1 --disable-warnings -q
```

**Exact new `build` job steps:**

```yaml
      - name: Install dependencies
        run: |
          python -m venv .venv
          .venv/bin/pip install --upgrade pip
          .venv/bin/pip install -e ".[dev]"

      - name: Run tests
        run: make test-unit
```

**Exact old `integration-test` job `env` block:**

```yaml
    env:
      DATABASE_URL: postgresql://postgres:postgres@localhost:5432/products
      ENVIRONMENT: sandbox
```

**Exact new `integration-test` job `env` block:**

```yaml
    env:
      DB_HOST: localhost
      DB_PORT: "5432"
      DB_NAME: products
      DB_USERNAME: postgres
      DB_PASSWORD: postgres
      ENVIRONMENT: sandbox
```

**Exact old `integration-test` job install+run steps:**

```yaml
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install .[dev]

      - name: Run integration tests
        run: pytest -m integration -v
```

**Exact new `integration-test` job install+run steps:**

```yaml
      - name: Install dependencies
        run: |
          python -m venv .venv
          .venv/bin/pip install --upgrade pip
          .venv/bin/pip install -e ".[dev]"

      - name: Run integration tests
        run: make test-integration
```

---

### Change 3 — `src/product_catalog/database.py`: narrow guard allowlist + use structlog

**Exact old block (lines 74–81):**

```python
    if settings.environment == "production":
        import logging

        logging.getLogger(__name__).warning(
            "products schema mismatch detected in production — skipping recreation; missing columns: %s",
            missing,
        )
        return
```

**Exact new block:**

```python
    if settings.environment not in ("development", "sandbox", "test"):
        import structlog

        structlog.get_logger(__name__).warning(
            "products schema mismatch — skipping recreation in non-dev environment",
            missing_columns=sorted(missing),
            environment=settings.environment,
        )
        return
```

---

### Change 4 — `docs/issues/2026-05-25-product-catalog-schema-mismatch-mypy-preexisting-errors.md`: new file

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
| `Makefile` | Add `PYTEST`/`RUFF_CMD` venv vars; use them in all test and lint targets |
| `.github/workflows/ci.yml` | All jobs: create venv, call `make` targets; integration job: `DB_*` vars instead of `DATABASE_URL` |
| `src/product_catalog/database.py` | Narrow DROP allowlist to dev environments; use structlog |
| `docs/issues/2026-05-25-product-catalog-schema-mismatch-mypy-preexisting-errors.md` | New file |

---

## Rules

- `make lint` must pass (zero ruff warnings)
- `make test-unit` must succeed locally (requires `.venv/` with `pip install -e ".[dev]"`)
- No other files touched

---

## Definition of Done

- [ ] `PYTEST := $(VENV_BIN)/pytest` and `RUFF_CMD := $(VENV_BIN)/ruff` defined in Makefile
- [ ] All test targets use `$(PYTEST)`, lint targets use `$(RUFF_CMD)`
- [ ] CI `lint` job creates venv and calls `make lint` + `make typecheck`
- [ ] CI `build` job creates venv and calls `make test-unit`
- [ ] CI `integration-test` job creates venv, uses `DB_*` vars, calls `make test-integration`
- [ ] `database.py` guard uses `not in ("development", "sandbox", "test")` and structlog
- [ ] `docs/issues/` mypy file created
- [ ] `make lint` passes — zero new ruff warnings
- [ ] `make test-unit` passes locally with venv active
- [ ] Committed and pushed to `fix/product-catalog-schema-mismatch` on `origin`

**Commit message (exact):**
```
fix(makefile): wire venv pytest/ruff to CI; narrow schema guard; address Copilot PR#31 findings
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the listed targets
- Do NOT commit to `main` — work on `fix/product-catalog-schema-mismatch`
- Do NOT add `--ignore-missing-imports` to the `typecheck` Makefile target — mypy errors
  in `src/` are pre-existing and tracked separately
- Do NOT change `test-watch` — it uses `ptw`, not pytest
- Do NOT change `security-scan` CI job — it does not use make targets
