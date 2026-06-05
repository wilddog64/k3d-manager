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
  acg.sh public API: `acg_import_credentials()`, `acg_get_credentials()`, `acg_provision()`,
  `acg_status()`, `acg_extend()`, `acg_check_ttl()`, `acg_watch()`, `acg_watch_start()`,
  `acg_watch_stop()`, `acg_chrome_cdp_install()`, `acg_chrome_cdp_uninstall()`, `acg_teardown()`.
- **Shared constants**: `scripts/vars.sh` — `PLAYWRIGHT_AUTH_DIR`, `PLAYWRIGHT_CDP_PORT`, URLs.
- **Configuration**: `ACG_CLUSTER_TEMPLATE` (env var) — CloudFormation template path for `acg_provision()` (default: `${_LIB_ACG_ROOT}/scripts/etc/acg-cluster.yaml`); callers like k3d-manager override this to use their own template.
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
- **Transient toast/overlay dismissal** during pointer actions must use `page.addLocatorHandler()` —
  it's the canonical pattern for handling overlays that appear mid-click without blocking polling loops
  (see PR #27 for pattern: detect overlay, press Escape, click target, let handler retry silently).
  Do not use `page.evaluate()` DOM clicks for toast dismissal in polling paths.
- **Modal dialog dismissal** (e.g. "Extend Your Session") uses `page.evaluate()` DOM clicks — this
  is intentional because Escape closes the sandbox panel, not just the dialog. `waitForFunction`
  close-confirmation after the dismiss click is acceptable here.

### Shell Injection (OWASP A03)
- All variable expansions must be double-quoted: `"$var"`, not `$var`.
- Never pass external input to `eval`.
- Use `--` to separate options from arguments where arguments may contain hyphens.

### Code Style
- `set -euo pipefail` on all new bash scripts.
- `node --check` must pass on all `.js` files.
- `shellcheck -S warning` must pass on all shell scripts in `bin/` and `scripts/`.
- No inline comments unless the WHY is non-obvious.
