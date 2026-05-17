# Fix: lib-acg — `credential-test`/`extend-test` require explicit SANDBOX_URL; no default

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `Makefile` — add `SANDBOX_URL ?=` default, remove exit-1 guard

---

## Before You Start

```
git -C ~/src/gitrepo/personal/lib-acg fetch origin
git -C ~/src/gitrepo/personal/lib-acg checkout fix/acg-credentials-extend-dialog
git -C ~/src/gitrepo/personal/lib-acg pull origin fix/acg-credentials-extend-dialog
```

Read this spec in full before touching any file.

---

## Problem

`make credential-test` and `make extend-test` currently exit with a usage error unless
`SANDBOX_URL` is set explicitly. `bin/acg-up` (in k3d-manager) defaults to the ACG portal
URL when no URL is given; the lib-acg Makefile should follow the same pattern so testing
is consistent and muscle memory transfers.

**Root cause:** The Makefile targets use `@if [ -z "$(SANDBOX_URL)" ]; then ... exit 1`
instead of `SANDBOX_URL ?= <default>` at the top of the file.

---

## Fix

### Change 1 — `Makefile`: add `SANDBOX_URL ?=` default, remove exit-1 guards

**Exact old block (entire file):**

```makefile
.PHONY: setup check lint credential-test extend-test help

help:
	@printf 'Targets:\n'
	@printf '  setup             — npm install + download Playwright Chromium browser\n'
	@printf '  check             — node --check all playwright/*.js files\n'
	@printf '  lint              — shellcheck all bin/ scripts\n'
	@printf '  credential-test   — run bin/acg-credential-test (requires SANDBOX_URL=<url>)\n'
	@printf '                      optional: PROVIDER=aws|gcp\n'
	@printf '  extend-test       — run bin/acg-extend-test (requires SANDBOX_URL=<url>)\n'

setup:
	npm install
	npx playwright install chromium
	git config core.hooksPath .githooks

check:
	node --check playwright/*.js

lint:
	shellcheck -S warning bin/acg-credential-test bin/acg-extend-test

credential-test:
	@if [ -z "$(SANDBOX_URL)" ]; then printf 'Usage: make credential-test SANDBOX_URL=<url> [PROVIDER=aws|gcp]\n' >&2; exit 1; fi
	bin/acg-credential-test "$(SANDBOX_URL)" $(if $(PROVIDER),--provider "$(PROVIDER)",)

extend-test:
	@if [ -z "$(SANDBOX_URL)" ]; then printf 'Usage: make extend-test SANDBOX_URL=<url>\n' >&2; exit 1; fi
	bin/acg-extend-test "$(SANDBOX_URL)"
```

**Exact new block (entire file):**

```makefile
.PHONY: setup check lint credential-test extend-test help

SANDBOX_URL ?= https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
PROVIDER ?=

help:
	@printf 'Targets:\n'
	@printf '  setup             — npm install + download Playwright Chromium browser\n'
	@printf '  check             — node --check all playwright/*.js files\n'
	@printf '  lint              — shellcheck all bin/ scripts\n'
	@printf '  credential-test   — run bin/acg-credential-test (default: ACG portal URL)\n'
	@printf '                      optional: PROVIDER=aws|gcp SANDBOX_URL=<url>\n'
	@printf '  extend-test       — run bin/acg-extend-test (default: ACG portal URL)\n'
	@printf '                      optional: SANDBOX_URL=<url>\n'

setup:
	npm install
	npx playwright install chromium
	git config core.hooksPath .githooks

check:
	node --check playwright/*.js

lint:
	shellcheck -S warning bin/acg-credential-test bin/acg-extend-test

credential-test:
	bin/acg-credential-test "$(SANDBOX_URL)" $(if $(PROVIDER),--provider "$(PROVIDER)",)

extend-test:
	bin/acg-extend-test "$(SANDBOX_URL)"
```

---

## Files Changed

| File | Change |
|------|--------|
| `Makefile` | Add `SANDBOX_URL ?=` default; remove exit-1 guards; update help text |

---

## Rules

- `make credential-test` (no args) must invoke `bin/acg-credential-test` with the default portal URL — no error
- `make credential-test SANDBOX_URL=<url> PROVIDER=aws` must pass both args through correctly
- No other files modified

---

## Definition of Done

- [ ] `Makefile` has `SANDBOX_URL ?= https://app.pluralsight.com/hands-on/playground/cloud-sandboxes`
- [ ] `credential-test` and `extend-test` targets invoke bin scripts directly with no exit-1 guard
- [ ] Help text updated to say `(default: ACG portal URL)` instead of `(requires SANDBOX_URL=<url>)`
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in lib-acg with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(makefile): default SANDBOX_URL to ACG portal; remove exit-1 guard
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `Makefile`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT change `.PHONY`, `setup`, `check`, or `lint` targets
