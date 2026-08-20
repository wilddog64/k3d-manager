# Bugfix: product-catalog — Makefile test targets fail when venv not activated

**Branch:** `k3d-manager-v1.4.9` (spec only — code changes in shopping-cart-product-catalog)
**Files:** `Makefile`

---

## Before You Start

**Branch (work repo):** `fix/product-catalog-schema-mismatch` in `shopping-cart-product-catalog`
(same branch — do not create a new branch)

```bash
# Step 1 — get the spec (k3d-manager repo)
git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.9

# Step 2 — read this spec in full before touching anything

# Step 3 — check out the existing branch in the work repo
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-product-catalog \
  checkout fix/product-catalog-schema-mismatch

# Step 4 — read the target file before editing
# Makefile (lines 70–103)
```

---

## Problem

All Makefile test targets invoke `pytest` as a bare command. If the virtualenv is not
activated, `make test-integration` (and all other test targets) fail immediately:

```
make: pytest: No such file or directory
make: *** [test-integration] Error 1
```

**Root cause:** `pytest` is installed inside the virtualenv but not on the system PATH.
Bare `pytest` relies on the caller having activated `source .venv/bin/activate` first.
Using `$(PYTHON) -m pytest` works without venv activation because it resolves through the
Python interpreter, which knows its own site-packages.

---

## Fix

Replace all bare `pytest` invocations in test targets with `$(PYTHON) -m pytest`.
`PYTHON` is already defined at the top of the Makefile as `python3`.

**Exact old block (lines 72–103):**

```makefile
test: ## Run all tests
	@echo "${BLUE}Running all tests...${NC}"
	pytest tests/ -v

test-unit: ## Run unit tests only
	@echo "${BLUE}Running unit tests...${NC}"
	pytest tests/unit/ -v

test-integration: ## Run integration tests only
	@echo "${BLUE}Running integration tests...${NC}"
	pytest tests/integration/ -v

test-security: ## Run security tests only
	@echo "${BLUE}Running security tests...${NC}"
	pytest tests/unit/test_security*.py -v

test-cov: ## Run tests with coverage
	@echo "${BLUE}Running tests with coverage...${NC}"
	pytest tests/ --cov=product_catalog --cov-report=html --cov-report=term-missing
	@echo "${GREEN}Coverage report: htmlcov/index.html${NC}"

test-cov-xml: ## Run tests with coverage (XML for CI)
	@echo "${BLUE}Running tests with XML coverage...${NC}"
	pytest tests/ --cov=product_catalog --cov-report=xml

test-watch: ## Run tests in watch mode
	@echo "${BLUE}Running tests in watch mode...${NC}"
	ptw tests/ -- -v

test-failed: ## Re-run failed tests
	@echo "${BLUE}Re-running failed tests...${NC}"
	pytest tests/ --lf -v
```

**Exact new block:**

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

Note: `test-watch` uses `ptw` (pytest-watch), not `pytest` — leave it unchanged.

---

## Files Changed

| File | Change |
|------|--------|
| `Makefile` | Replace bare `pytest` with `$(PYTHON) -m pytest` in all test targets |

---

## Rules

- Only `Makefile` touched — no other files
- `make test-unit` must succeed without activating the venv (validation command below)

---

## Definition of Done

- [ ] All bare `pytest` calls in test targets replaced with `$(PYTHON) -m pytest`
- [ ] `test-watch` target left unchanged (`ptw` — not a pytest call)
- [ ] `make test-unit` runs successfully without `source .venv/bin/activate`
- [ ] Committed and pushed to `fix/product-catalog-schema-mismatch` on `origin`

**Commit message (exact):**
```
fix(makefile): use python -m pytest — bare pytest fails without venv activation
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `Makefile`
- Do NOT commit to `main` — work on `fix/product-catalog-schema-mismatch`
- Do NOT change `test-watch` — it uses `ptw`, not `pytest`
- Do NOT change any non-test targets
