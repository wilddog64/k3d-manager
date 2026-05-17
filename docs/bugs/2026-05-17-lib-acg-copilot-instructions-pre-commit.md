# Chore: lib-acg — add copilot-instructions.md and pre-commit hook

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `.github/copilot-instructions.md` — new file
- `.githooks/pre-commit` — new file
- `Makefile` — update `setup` target to wire the hook

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

lib-acg has no Copilot review instructions and no pre-commit hook. PRs receive unfocused
Copilot suggestions (unaware of CDP session rules, Playwright selector fragility, or
credential hygiene). Contributors can commit broken JS or shell without being warned.

---

## Fix

### Change 1 — `.github/copilot-instructions.md`: new file

```markdown
# GitHub Copilot Instructions — lib-acg

lib-acg is a browser automation library for ACG/GCP sandbox credential extraction and
session management. It provides Chrome CDP bootstrap, Playwright scripts, and
provider-specific credential flows (AWS, GCP). Consumed by `k3d-manager` as a git subtree.

---

## Architecture

- **Playwright scripts**: `playwright/acg_credentials.js` (AWS/GCP credential extraction),
  `playwright/acg_extend.js` (sandbox TTL extension), `playwright/gcp_login.js` (Google OAuth).
  All connect to Chrome via CDP (`localhost:9222`).
- **CDP layer**: `scripts/lib/cdp.sh` — Chrome launch, session attach, port probe.
- **Plugin scripts**: `scripts/plugins/acg.sh` (sandbox lifecycle), `scripts/plugins/gcp.sh`
  (GCP identity bridge). Public functions: no underscore prefix. Private: `_` prefix.
- **Shared constants**: `scripts/vars.sh` — `PLAYWRIGHT_AUTH_DIR`, `PLAYWRIGHT_CDP_PORT`, URLs.
- **Test harness**: `bin/acg-credential-test`, `bin/acg-extend-test` — CDP check + invoke
  Playwright scripts directly; no k3d-manager required.

---

## Review Focus

### Credential Hygiene (OWASP A02)
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN` must never appear in
  log output — even at INFO level. Use redacted placeholders or omit entirely.
- `PLURALSIGHT_EMAIL` and `PLURALSIGHT_PASSWORD` must never be logged or echoed.
- No hardcoded credentials, tokens, or IP addresses in any file.

### CDP Session Safety
- In the `finally` block of any Playwright script, only call `browserContext.close()` when
  the context was launched by the script (i.e., `!_cdpBrowser`). Never call `browser.close()`
  on a CDP-attached session — it shuts down the entire Chrome process.
- Chrome must always be launched with `--password-store=basic` and a dedicated
  `--user-data-dir` — flag any launch path that omits these.

### Playwright Selector Fragility
- Selectors like `input[aria-label="Copyable input"]` are fragile — flag hardcoded
  positional index fallbacks that assume a fixed UI layout without a comment explaining why.
- Dialog detection must use `[role="dialog"]` + `innerText` contains check — not CSS class
  selectors that may change with UI updates.
- All dialog interaction must use `page.evaluate()` with direct DOM `.click()` — never
  `addLocatorHandler` (it only fires on locator actions, not on `waitForFunction`).

### Shell Injection (OWASP A03)
- All variable expansions must be double-quoted: `"$var"`, not `$var`.
- Never pass external input to `eval`.
- Use `--` to separate options from arguments where arguments may contain hyphens.

### Code Style
- `set -euo pipefail` on all new bash scripts.
- `node --check` must pass on all `.js` files.
- `shellcheck -S warning` must pass on all shell scripts in `bin/` and `scripts/`.
- No inline comments unless the WHY is non-obvious.
```

---

### Change 2 — `.githooks/pre-commit`: new file

```bash
#!/usr/bin/env bash
set -euo pipefail

staged_js=$(git diff --cached --name-only | grep '\.js$' || true)
if [[ -n "$staged_js" ]]; then
  while IFS= read -r f; do
    node --check "$f"
  done <<< "$staged_js"
fi

staged_sh=$(git diff --cached --name-only | grep -E '^(bin/|scripts/)' | grep -v '\.js$' || true)
if [[ -n "$staged_sh" ]]; then
  while IFS= read -r f; do
    shellcheck -S warning "$f"
  done <<< "$staged_sh"
fi
```

Make executable: `chmod +x .githooks/pre-commit`

---

### Change 3 — `Makefile`: add hook wiring to `setup` target

**Exact old block:**

```makefile
setup:
	npm install
	npx playwright install chromium
```

**Exact new block:**

```makefile
setup:
	npm install
	npx playwright install chromium
	git config core.hooksPath .githooks
```

---

## Files Changed

| File | Change |
|------|--------|
| `.github/copilot-instructions.md` | New file — Copilot review instructions |
| `.githooks/pre-commit` | New file — `node --check` + `shellcheck` on staged files |
| `Makefile` | Add `git config core.hooksPath .githooks` to `setup` target |

---

## Rules

- `shellcheck -S warning .githooks/pre-commit` — zero warnings
- `make setup` must complete without error (runs npm install + playwright install + git config)
- No other files modified

---

## Definition of Done

- [ ] `.github/copilot-instructions.md` created
- [ ] `.githooks/pre-commit` created and executable
- [ ] `Makefile` `setup` target includes `git config core.hooksPath .githooks`
- [ ] `shellcheck -S warning .githooks/pre-commit` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in lib-acg with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
chore(repo): add copilot-instructions and pre-commit hook
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed above
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT add `addLocatorHandler` to copilot-instructions as a recommendation — it is
  explicitly prohibited in this repo
