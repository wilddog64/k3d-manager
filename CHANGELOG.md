# Changelog

All notable changes to lib-acg will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [0.1.5] - 2026-06-11

### Fixed
- `playwright/lib/sandbox.js`: scope `addLocatorHandler` trigger to `h3` and `h2` heading elements — broad text regex matched both heading and paragraph, causing Playwright strict-mode violation when the toast appeared
- `playwright/lib/sandbox.js`: use `Escape` key in `addLocatorHandler` to dismiss "Session extended" toast — previous close-button click was unscoped and closed the credential panel instead of the toast
- `playwright/lib/sandbox.js`: parse conflicting provider name from conflict warning text — previous detection used a broken "Auto Shutdown" selector that never matched AWS, so `_deleteConflictingSandbox` never ran and the warning loop spun forever
- `playwright/lib/sandbox.js`: check for "Hang tight" / "Finalizing your playground" provisioning banner in `_waitForCredentials` before triggering reopen or throw — panel auto-closes during Azure sandbox startup; without this check the `reopenAttempted` guard fired immediately and aborted while the sandbox was still provisioning
- `playwright/lib/sandbox.js`: remove `panelInStartState` heuristic — global DOM check caused bidirectional regression when both provider panels were visible
- `playwright/lib/sandbox.js`: add unscoped `Start Sandbox` fallback in `acg_restart.js` for detached panel overlay flow
- `bin/acg-credential-test`: remove portal-only restart loop — replace with fail-fast error so MFA failures surface immediately instead of looping
- `bin/acg-credential-test`: automate Azure device code sign-in via CDP browser automation — when `az login --username --password` fails due to MFA enforcement, run `az login --use-device-code` in background, parse device URL and code from stderr, and drive sign-in via Playwright `acg_azure_device_login.js`; removes manual browser prompt entirely
- `bin/acg-credential-test`: persist `az login` to `~/.azure` after SP validation

## [0.4.0] - 2026-06-10

### Added
- `playwright/lib/sandbox.js`: Azure provider support — add `_findScopedButton` and `_deleteConflictingSandbox`, scope `startSandbox(page, targetUrl, provider)` button lookups to the provider card, delete conflicting active sandboxes before opening Azure, and keep the yellow-band conflict warning as a retry safety net; `playwright/acg_credentials.js` now passes `provider` through to `startSandbox`; `playwright/providers/azure.js` now extracts Azure username/password/subscription/tenant credentials from copyable inputs

### Changed
- `playwright/acg_credentials.js`: refactored from 672-line monolith into provider pattern — `lib/browser.js` (CDP connect), `lib/sandbox.js` (navigation/sign-in/sandbox start/extend-dialog), `lib/output.js` (credential output), `providers/aws.js`, `providers/gcp.js`, `providers/azure.js` (stub); AWS and GCP behavior unchanged; Jest unit tests added (`npm test` — 7/7 pass)
- `package.json` + `package-lock.json`: align version fields to `0.3.0` (were `0.2.0` and `0.1.0` respectively)

### Fixed
- `bin/acg-credential-test`: make Azure CLI auth branches exclusive so `az login --service-principal` / `az login --identity` failures do not silently fall back to portal/TAP when CLI auth metadata is already present; only use portal login when no CLI auth path exists, and keep the `az account get-access-token` probe as the success gate
- `bin/acg-credential-test`: authenticate Azure portal TAP creds in a clean `AZURE_CONFIG_DIR`, verify with `az account get-access-token`, prefer the portal username/password path over cached auth, and emit Azure portal/resource-group snapshot metadata for failure debugging
- `playwright/lib/sandbox.js`: remove the stale Hands-on intermediate retry hop in `startSandbox()` — when an expired sandbox redirects the resumed Playwright session to login (`/id`, `sign-in`, or `login`), fail fast instead of continuing through the old recovery route that loses the sandbox context
- `bin/acg-credential-test`: validate Azure service-principal credentials with `az login --service-principal` after extraction, auto-discovering tenant from OIDC endpoint when not present in Pluralsight UI, and discovering subscription from `az account show` when unavailable in UI; output shows account name only (subscription ID masked)
- `playwright/providers/azure.js`: detect `clientSecret` before `clientId` in Application ID field label scan (Azure layout ordering); add multi-pass scan with UUID-pattern fallback for subscription/tenant when not found on first pass; correctly set fallback field positions for 4-field layout variant
- `bin/acg-credential-test`: add OIDC tenant discovery when Azure tenant is not visible in Pluralsight UI — query `https://login.microsoftonline.com/<domain>/.well-known/openid-configuration` to extract tenant ID from username domain
- `bin/acg-credential-test`: mask tenant ID and subscription ID in terminal output; expose `az login` error messages to stderr
- `bin/acg-credential-test`: validate Azure portal username/password with `az login --username ... --password ...`, discover tenant from the username domain when missing, and keep service-principal validation as a fallback when `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` are present
- `playwright/lib/sandbox.js`: add `.first()` to the `addLocatorHandler` trigger locator in `startSandbox` so Playwright strict mode does not raise a "resolved to 2 elements" error when both the toast heading and body text match the regex — brings sandbox.js into line with the `.first()` pattern already used in `acg_extend.js` and `acg_restart.js`
- `playwright/lib/sandbox.js`: add `addLocatorHandler` in `startSandbox` to dismiss "Session extended" / "sandbox has been extended" toast by clicking its close button, re-opening the credential panel if toast dismissal collapsed it
- `playwright/lib/sandbox.js` and `playwright/providers/azure.js`: exclude shared-container DOM elements from conflicting sandbox detection — walk stops at provider-keyword ancestor to prevent false-positive matches on containers visible in multiple provider cards
- `playwright/lib/sandbox.js` and `playwright/acg_restart.js`: scope the post-Open-Sandbox `startButton2` fallback and the restart-flow Delete/Open/Start button lookups to the target provider card so AWS no longer wins the DOM-first fallback when Azure is the intended sandbox
- `playwright/providers/azure.js`: add Application Client ID and Secret extraction so Azure service-principal creds are emitted as `AZURE_CLIENT_ID` and `AZURE_CLIENT_SECRET` when the sandbox shows those fields instead of username/password
- `playwright/lib/sandbox.js`: make `_dismissExtendYourSessionDialog` click the Extend button with `force: true` and check `credentialsAlreadyVisible` before `_deleteConflictingSandbox` so already-running sandboxes skip the unnecessary delete attempt
- `playwright/lib/sandbox.js`: increase the post-Open-Sandbox `startButton2` search timeout to 30s and add a visible/enabled fallback search so Azure can still start when the scoped lookup misses the button on a slow panel transition
- `playwright/lib/sandbox.js`: remove the intermediate `https://app.pluralsight.com/hands-on` hop from the sandbox retry block so a drifted page goes directly back to `targetUrl` instead of landing on Pluralsight's 404 page and losing the sandbox context
- `playwright/lib/sandbox.js` and `playwright/providers/azure.js`: add provider exclusion checks to ancestor walks so shared containers no longer match the wrong provider card when multiple sandbox providers are visible
- `playwright/lib/sandbox.js`: replace the raw DOM `dispatchEvent(new MouseEvent(...))` confirm-dialog path with a Playwright `confirmBtn.click({ force: true })` so React's synthetic event system sees the Delete Sandbox confirmation and actually closes the conflicting sandbox
- `playwright/lib/sandbox.js`: scope `_waitForCredentials(page, providerLabel)` to the active provider card and update all three call sites so AWS credentials no longer short-circuit Azure startup; `playwright/providers/azure.js` now reads only Azure-scoped copyable inputs before mapping Username/Password/Subscription/Tenant into `AZURE_*` variables
- `playwright/lib/sandbox.js`: scope the early-exit credential check (`credentialsAlreadyVisible`) to the active provider card so Azure no longer returns early when AWS creds are visible; the provider-aware sandbox log now says `Looking for ${providerLabel} sandbox buttons...`
- `playwright/lib/sandbox.js`: add `{ force: true }` to `startButton`, `startButton2`, and `resumeButton` clicks in `startSandbox()` — prevents `locator.click: Element is outside of the viewport` regression introduced in v0.1.2 where `scrollIntoViewIfNeeded()` was added but `{ force: true }` was omitted, so a post-scroll layout shift (triggered by the `addLocatorHandler` for "sandbox has been extended") still fails the click; `openButton` already had the correct pattern
- `playwright/acg_restart.js`: add `scrollIntoViewIfNeeded()` before `_startBtnEarly.click({ force: true })` and `_startBtnPanel.click({ force: true })` in the restart flow to prevent `Element is outside of the viewport` failures when the sandbox panel renders below the fold
- `startSandbox()`: add `scrollIntoViewIfNeeded()` before `Start Sandbox`, `Start Sandbox (Step 2)`, and `Resume Sandbox` clicks to prevent `Element is outside of the viewport` failures
- `playwright/acg_credentials.js`: replace `navLink.click()` with `window.location.assign()` for cloud-sandboxes SPA navigation — "Extend Your Session" dialog intercepts pointer events and caused `navLink.click()` to timeout when the dialog reappeared between dismiss and click
- `scripts/hooks/pre-commit`: replace unquoted `$_refs` in `printf` with a `read` loop — prevents word-splitting on filenames with spaces
- `scripts/plugins/acg.sh` (`acg_check_ttl`): add `return 1` after missing-node error; return `-1` sentinel instead of empty string when TTL is unparseable
- `bin/acg-credential-test`: remove `2>&1` from `_extract_credentials()` so Playwright INFO/WARN/ERROR messages stream to the terminal in real time instead of being buffered until `$_tmpout` is printed
- `bin/acg-credential-test`: add `_print_masked` helper using `sed 's/=.*/=***/'` to mask credential values in terminal output (e.g., `AWS_ACCESS_KEY_ID=***`); replace all `cat "$_tmpout" >&2` calls with `_print_masked` so key names are visible but values are never printed
- `playwright/acg_credentials.js`: add `page.evaluate` fallback in `_waitForCredentials` when React-managed inputs return empty from `inputValue()` after CDP reconnect
- `playwright/acg_credentials.js`: replace `EXTEND_DIALOG_BLOCKED` throw in `_waitForCredentials` with inline dismiss-and-retry loop — dialog reappears after sandbox restart and was incorrectly treated as a hard failure instead of a transient obstacle
- `playwright/acg_credentials.js`: detect "Extend Your Session" dialog on page entry (before navigation logic) and force a hard `page.goto` reload to reset SPA timer state — React re-triggers the dialog from in-memory state after `acg_restart.js` dismisses it via DOM click, causing `acg_credentials.js` to see it again immediately on attach
- `playwright/acg_restart.js`: add `clearTimeout` + explicit `process.exit(0)` on success — the 240s timeout timer kept the Node event loop alive after `RESTART_OK` was printed, causing `acg-credential-test` to hang indefinitely waiting for the node process to exit
- `playwright/acg_restart.js`, `playwright/acg_credentials.js`: fix "Extend Your Session" dialog detection — Pluralsight renders it as `role="alertdialog"` (not `role="dialog"`), so all nine `querySelectorAll('[role="dialog"]')` calls silently matched nothing; updated to `[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]`
- `playwright/acg_credentials.js`: hoist `_dismissExtendYourSessionDialog` before the SPA navigation block and call it before `navLink.click()` — fixes timeout when modal intercepts pointer events on the nav link
- `playwright/acg_restart.js`: call `_dismissExtendYourSessionDialog` after `openBtn.click()` and before `waitForSelector('Delete Sandbox')` — fixes timeout when modal appears during panel expand
- `playwright/acg_restart.js`: add visibility guard to `_dismissExtendYourSessionDialog` to prevent false-positive "Extend Your Session" dialog detection — check `offsetParent !== null && getComputedStyle(d).display !== 'none'` before attempting dismiss

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
