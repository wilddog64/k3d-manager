# Changelog

All notable changes to lib-acg will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Fixed
- `bin/acg-credential-test`: remove `2>&1` from `_extract_credentials()` so Playwright INFO/WARN/ERROR messages stream to the terminal in real time instead of being buffered until `$_tmpout` is printed
- `bin/acg-credential-test`: add `_print_masked` helper using `sed 's/=.*/=***/'` to mask credential values in terminal output (e.g., `AWS_ACCESS_KEY_ID=***`); replace all `cat "$_tmpout" >&2` calls with `_print_masked` so key names are visible but values are never printed
- `playwright/acg_credentials.js`: add `page.evaluate` fallback in `_waitForCredentials` when React-managed inputs return empty from `inputValue()` after CDP reconnect
- `playwright/acg_credentials.js`: replace `EXTEND_DIALOG_BLOCKED` throw in `_waitForCredentials` with inline dismiss-and-retry loop — dialog reappears after sandbox restart and was incorrectly treated as a hard failure instead of a transient obstacle
- `playwright/acg_credentials.js`: detect "Extend Your Session" dialog on page entry (before navigation logic) and force a hard `page.goto` reload to reset SPA timer state — React re-triggers the dialog from in-memory state after `acg_restart.js` dismisses it via DOM click, causing `acg_credentials.js` to see it again immediately on attach
- `playwright/acg_restart.js`: add `clearTimeout` + explicit `process.exit(0)` on success — the 240s timeout timer kept the Node event loop alive after `RESTART_OK` was printed, causing `acg-credential-test` to hang indefinitely waiting for the node process to exit
- `playwright/acg_restart.js`, `playwright/acg_credentials.js`: fix "Extend Your Session" dialog detection — Pluralsight renders it as `role="alertdialog"` (not `role="dialog"`), so all nine `querySelectorAll('[role="dialog"]')` calls silently matched nothing; updated to `[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]`

## [0.3.0] - 2026-05-21

### Changed
- `scripts/plugins/acg.sh`: make CloudFormation template path configurable via `ACG_CLUSTER_TEMPLATE` env var (default: `${_LIB_ACG_ROOT}/scripts/etc/acg-cluster.yaml`); callers (e.g. k3d-manager) can set `ACG_CLUSTER_TEMPLATE` to a repo-local template instead of relying on the bundled copy

### Fixed
- `scripts/etc/acg-cluster.yaml`: restore CloudFormation template deleted in v0.2.0 without updating the `_LIB_ACG_ROOT/scripts/etc/acg-cluster.yaml` reference in `acg.sh` — broke `make up` with `Invalid template path`
- `scripts/hooks/pre-commit`: add dangling-reference gate — fails if a file staged for deletion is still referenced by name in any `.sh` or `.js` file remaining in the index; prevents the class of bug where a file is deleted without updating its reference in code
- `acg_restart.js`: provider-scope the "Start Sandbox" button lookup to the target provider card (AWS/GCP/Azure) — prevents restart from opening the wrong card when multiple providers are visible
- `bin/acg-credential-test`: forward `--provider` argument through to `acg_restart.js` so the restart flow targets the correct sandbox card on credential extraction failure
- `acg_credentials.js`: restore AWS-working credential extraction path (reverted to pre-GCP-scoping state); GCP-specific scoping work preserved on `fix/gcp-credentials-scoping` branch for follow-on work
- `acg_extend.js`: wait for SPA render after Ghost State re-navigation and increase Delete Sandbox button visibility timeout to 30s so SPA re-navigation can find the button reliably

## [0.2.0] - 2026-05-20

### Fixed
- `acg_restart.js`: use `dispatchEvent(new MouseEvent('click', {bubbles:true}))` instead of `.click()` to reliably trigger React's delegated event handlers on the `[role="alertdialog"]` confirm button
- `acg_restart.js`: scope confirm button lookup to `document.querySelector('[role="alertdialog"]')` — prevents matching the listing-page "Delete Sandbox" button behind the modal (`role="dialog"` vs `role="alertdialog"` distinction)
- `acg_restart.js`: add fast-path for already-deleted sandbox — if "Start Sandbox" is visible and neither "Delete" nor "Open" Sandbox are present, click Start directly without re-deleting
- `acg_restart.js`: increase Start Sandbox wait from 120s → 180s; overall script timeout 120s → 240s — AWS backend deletion can exceed 2 minutes
- `acg_restart.js`: add post-click alertdialog-still-open check with pointer-event sequence fallback
- `acg_restart.js`: log button text found inside alertdialog for easier failure diagnosis
- `bin/acg-credential-test`: add mandatory final `sts:GetCallerIdentity` gate that runs on all exit paths (first-try success, extraction-fail-restart, ghost-state-restart)
- `bin/acg-credential-test`: refactor into `_extract_credentials` / `_sts_valid` helpers; previously the extraction-fail→restart path skipped sts validation entirely
- `acg_extend.js`: add `--provider aws|gcp|azure` argument (default `aws`); scope extend button lookup to provider card by walking up the DOM — prevents always selecting the first (AWS) sandbox when multiple providers are visible
- `acg_extend.js`: change `--check` flag detection from positional `process.argv[3]` to `process.argv.includes('--check')` — survives argument reordering

### Added
- `tests/fixtures/sandbox.html`: self-contained Pluralsight sandbox page fixture with document-level event delegation, `role="alertdialog"` confirm modal, state machine (card→panel→confirm→deleted→started), and "Extend Your Session" dialog
- `tests/acg-restart.spec.js`: 7 Playwright fixture tests covering full delete flow, alertdialog dismiss via `dispatchEvent`, fast-path already-deleted state, extend dialog dismissal, and selector role scoping
- `playwright.config.js`: `@playwright/test` configuration pointing at `tests/` directory
- Makefile `test` target: runs fixture-based Playwright tests locally without a live Pluralsight session
- CI `e2e` job: installs Chromium and runs fixture tests on every PR

### Removed
- `scripts/etc/acg-cluster.yaml`: CloudFormation template removed from lib-acg — it belongs in k3d-manager where it already exists at `scripts/etc/acg-cluster.yaml`

## [0.1.0] - 2026-05-19

### Fixed
- `acg_extend.js`: narrow midnight-wrap guard to ≤ 60 min so expired sandboxes report a negative TTL instead of a large positive value
- `acg_extend.js`: add `--check` mode to print remaining sandbox TTL without extending
- `scripts/plugins/acg.sh`: add `acg_check_ttl()` wrapper for sandbox TTL checks
- `acg_extend.js`: skip "Open Sandbox" click when sandbox is expired (TTL ≤ 0) so Ghost State Recovery can find the "Delete Sandbox" button on the listing page; re-navigate to listing URL at top of Ghost State as safety net
- `acg_extend.js`: disconnect CDP browser in finally block to release WebSocket and prevent Node event loop from hanging indefinitely after successful TTL extension
- `acg_extend.js`: detect "Session extended" toast at startup — if already visible, extension already succeeded; exit 0 immediately instead of looping forever trying to dismiss via CDP mouse click
- `_waitForSandboxEntry`: pass `null` as `waitForFunction` arg so the timeout option reaches the options slot (same arg-slot bug as `_waitForCredentials`)
- `_waitForCredentials`: fix arg-slot bug (pass `null` as `waitForFunction` arg) and increase timeout from 60s to 180s — sandbox provisioning can take 60–120s
- `OVERALL_TIMEOUT_MS`: simplify redundant conditional to a single 300s constant — both first-run and non-first-run now use the same deadline
- `_waitForCredentials`: replace unreliable `waitForFunction` (in-page DOM query broken in CDP mode) with Playwright locator polling loop; increase credential wait from 180s to 420s to handle slower sandbox provisioning
- `OVERALL_TIMEOUT_MS`: increase from 300s to 780s (300s waitForURL + 420s credential polling + 60s buffer) to accommodate worst-case first-run flows
- CDP empty-contexts: open blank tab via `/json/new` HTTP API when `_cdpBrowser.contexts()` returns `[]` (Chrome has no open tabs); re-query after 500ms to expose the profile context and avoid falling through to `launchPersistentContext` which fails with a profile-lock error
- CDP disconnect guard: wrap `_cdpBrowser.disconnect()` in `if (!browserContext)` so the browser is only disconnected when the blank-tab recovery also fails — prevents disconnecting a context that was successfully recovered
- CDP blank-tab reconnect: after PUT `/json/new`, disconnect and reconnect via `connectOverCDP` instead of re-querying the stale `contexts()` list — Playwright does not materialize BrowserContext from `Target.targetCreated` events post-connect, so a fresh connection is required to see the new tab
- Chrome SingletonLock collision: stop the `chrome-cdp` launchd agent before taking over the shared profile and remove stale `SingletonLock` files only when the profile is not in use
- `_cdp_stop_chrome_cdp_agent`: replace deprecated `launchctl unload <plist>` with `launchctl bootout "gui/$(id -u)/<label>"` — required on macOS 15+ (Darwin 25); `2>/dev/null` was silently masking failures from the deprecated call; also removed redundant plist-file existence check since `launchctl list` already confirms service state
- `_browser_launch`: remove 17-line dead Linux else-block; library is macOS-only by design — non-Darwin callers now get a clear `_err` instead of silently entering unreachable code

### Added
- `bin/acg-credential-test`: AWS credential extraction with write to `~/.aws/credentials [default]`, validation via `sts:GetCallerIdentity`, credential value suppression from terminal
- `playwright/acg_credentials.js`: "Extend Your Session" dialog handling via bringToFront+Enter with best-effort dismiss (WARN logged if dismiss fails; credentials still populate via Extend path)
- Makefile `setup`, `check`, `lint` targets for local development
- CI workflow: shellcheck, node --check, yamllint on PRs to main
- Pre-commit hook: subtree guard + shellcheck + node --check on staged files
- Phase 3 migration: acg.sh, gcp.sh, cdp.sh, vars.sh, playwright scripts, acg-cluster.yaml
