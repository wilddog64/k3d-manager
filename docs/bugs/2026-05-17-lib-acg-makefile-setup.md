# Bug: lib-acg — `playwright` module not found; no Makefile setup target

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `Makefile` — new file

---

## Before You Start

```
git -C ~/src/gitrepo/personal/lib-acg fetch origin
git -C ~/src/gitrepo/personal/lib-acg checkout fix/acg-credentials-extend-dialog
```

Read this spec in full before touching any file.

---

## Problem

`bin/acg-credential-test` fails immediately with `Cannot find module 'playwright'` because
`node_modules/` does not exist in a fresh clone. `package.json` already declares
`playwright` as a dependency; there is no `make setup` or equivalent to bootstrap the repo.

**Root cause:** No Makefile exists in lib-acg; new contributors and CI have no documented
path to install dependencies and Playwright browsers before running the bin harness.

---

## Fix

### Change 1 — `Makefile`: new file

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

---

## Files Changed

| File | Change |
|------|--------|
| `Makefile` | New file — setup, check, lint, credential-test, extend-test, help targets |

---

## Rules

- `make check` must pass after `make setup`
- `make lint` must pass (zero new shellcheck warnings)
- No other files modified
- Do NOT touch `package.json` — it already has the correct dependency

---

## Definition of Done

- [ ] `Makefile` created at repo root
- [ ] `make setup` runs `npm install` then `npx playwright install chromium`
- [ ] `make check` runs `node --check playwright/*.js`
- [ ] `make lint` runs `shellcheck -S warning bin/acg-credential-test bin/acg-extend-test`
- [ ] `make credential-test SANDBOX_URL=<url>` invokes `bin/acg-credential-test`; exits 1 with usage if `SANDBOX_URL` unset
- [ ] `make extend-test SANDBOX_URL=<url>` invokes `bin/acg-extend-test`; exits 1 with usage if `SANDBOX_URL` unset
- [ ] `make help` prints all target descriptions
- [ ] `.PHONY` includes: `setup check lint credential-test extend-test help`
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in lib-acg with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
chore(makefile): add setup/check/lint targets for local development
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `Makefile`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify `package.json`
- Do NOT modify k3d-manager — this spec is lib-acg only
