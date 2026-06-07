# Progress — lib-acg

## v0.1.3 Track — `feat/v0.1.3` (IN PROGRESS — PR #38 open, Copilot review)

- **Bug spec:** `docs/bugs/2026-06-07-sandbox-start-button-click-force-missing.md` — `playwright/lib/sandbox.js` missing `{ force: true }` on Start/Resume Sandbox clicks; regression from v0.1.2 where scroll was added but force flag was omitted. Layout shift post-scroll (from `addLocatorHandler` for "sandbox has been extended") still fails the click.
- **Fix committed:** `07a9b29` (`fix(sandbox): add force:true to Start/Resume Sandbox clicks — survive layout shift after handler fires`) — adds `{ force: true }` to `startButton`, `startButton2`, `resumeButton`.
- **CHANGELOG updated:** `a0ccd95` — added entry to [Unreleased] section describing the fix.
- **PR #38 open** — CI green; Copilot review in progress.

## v0.1.2 Track — (MERGED PR #37)

- **MERGED PR #37** (`4d5aa477`): `playwright/lib/sandbox.js` — `scrollIntoViewIfNeeded()` added before `startButton`, `startButton2`, and `resumeButton` clicks; commit `86472da` (`fix(sandbox): scrollIntoViewIfNeeded before Start/Resume Sandbox clicks`). Bug spec: `docs/bugs/2026-06-05-sandbox-start-button-outside-viewport.md`. Retrospective: `docs/retro/2026-06-05-v0.1.2-retrospective.md`. Next branch: `feat/v0.1.3`.

## v0.1.1 Track — `feat/v0.1.1` (MERGED PR #36)

- **MERGED PR #36** (`f63b7ca3`): `playwright/lib/sandbox.js` — removed `navLink.click()` conditional in `navigateToSandbox()` that navigated to `s2.pluralsight.com/404.html`; always uses `window.location.assign()`. Commit: `21d6e27` (`fix(sandbox): remove navLink.click() path — always use window.location.assign()`). Bug spec: `docs/bugs/2026-06-05-sandbox-navlink-click-regression.md`. Retrospective: `docs/retro/2026-06-05-v0.1.1-retrospective.md`. Enforce_admins restored.

## Playwright Screenshot Diagnosis Track — `fix/playwright-screenshot-diagnosis` (merged to main)

- **COMPLETE:** phase A screenshot diagnosis on `fix/playwright-screenshot-diagnosis` finished. `playwright/acg_credentials.js` and `playwright/acg_restart.js` now save `/tmp/k3dm-acg-screenshot-<ts>.png` on unhandled errors and print `INFO: Screenshot saved to ...` to stderr; `acg_restart.js` hoists `page` to outer scope so the catch block can capture screenshots. Commit: `77c7dcc` (`feat(playwright): save screenshot on failure for AI diagnosis`). Validation: `node --check playwright/acg_credentials.js`, `node --check playwright/acg_restart.js`.

## v0.3.0 Track — `fix/next-improvements-7` (merged)

- **COMPLETE:** v0.3.1 bugfix sweep on `fix/next-improvements-7` finished. `scripts/hooks/pre-commit` now iterates deleted references safely with `read` instead of unquoted `$_refs`; `scripts/plugins/acg.sh` now returns `1` on missing `node` and `-1` when TTL output is unparseable; `package.json` and `package-lock.json` now both report `0.3.0`. Commits: `4e55392`, `4f7a1f3`, `7f1261c`. Pushed to `origin/fix/next-improvements-7`. Validation: `shellcheck -S warning scripts/hooks/pre-commit`, `shellcheck -S warning scripts/plugins/acg.sh`, `node --check playwright/*.js`.

- **MERGED PR #28** (`ee87aeb2`): Visibility guard — three-part check (`offsetParent !== null && getComputedStyle(d).display !== 'none' && getComputedStyle(d).visibility !== 'hidden'`) across `acg_credentials.js` and `acg_restart.js` to fix false-positive "Extend Your Session" detection. Bug doc: `docs/bugs/2026-05-24-acg-credentials-false-positive-extend-dialog.md`. Retro: `docs/retro/2026-05-24-pr28-retrospective.md`.

- **MERGED PR #27** (`7c17da72`): 14 bug fixes on `fix/next-improvements-5` → main. Root cause: toast-dismiss block inside async polling loop was architecturally wrong. Fixed by removing dismiss block from `_waitForCredentials`, consolidating toast handling to `addLocatorHandler` in pointer-action paths, correcting CDP Browser lifecycle (`close()` not `disconnect()`), and extending toast detection windows to match async server response timing (15s/10s instead of 5s/3s). Retro: `docs/retro/2026-05-23-pr27-retrospective.md`.

- **COMPLETE:** `playwright/acg_extend.js` now waits 2 seconds before checking for the "Session extended" toast and increases the visible window to 15s in the immediate path and 10s in the non-immediate path, matching the async server response timing; committed as `e635d1e` (`fix(acg-extend): increase toast detection timeout — async server response arrives after 5s window`) and pushed to `origin/fix/next-improvements-5`. Validation used `node --check playwright/acg_extend.js`.

- **COMPLETE:** `playwright/acg_credentials.js` now removes the toast-dismiss block from `_waitForCredentials`, leaving only the credential-input polling and preserving the `addLocatorHandler` toast handling for pointer actions; committed as `08f322e` (`fix(acg-credentials): remove toast dismiss from _waitForCredentials — DOM queries are never blocked by overlays`) and pushed to `origin/fix/next-improvements-5`. Validation used `node --check playwright/acg_credentials.js`.

- **COMPLETE:** `playwright/acg_extend.js`, `playwright/acg_credentials.js`, and `playwright/acg_restart.js` now anchor the "Session extended" toast dismiss on the leaf text node and closest button-bearing ancestor, fixing the broad `:has-text()` selector that could click the wrong button; committed as `bf57ee1` (`fix(acg): anchor toast dismiss on leaf text + XPath ancestor — broad :has-text selector clicked wrong button`) and pushed to `origin/fix/next-improvements-5`. Validation used `node --check playwright/acg_extend.js`, `node --check playwright/acg_credentials.js`, and `node --check playwright/acg_restart.js`.

- **COMPLETE:** `bin/acg-extend-test` now runs `node` normally, parses `--provider` from the remaining args, and re-validates AWS credentials with `aws sts get-caller-identity` after extend for AWS runs so broken sessions fail fast before `make all`/`make up` continue; committed as `0344eb3` (`fix(acg-extend-test): drop exec — add AWS credential re-validation after extend`) and pushed to `origin/fix/next-improvements-5`. Validation used `shellcheck -S warning bin/acg-extend-test`.

- **COMPLETE:** `playwright/acg_extend.js`, `playwright/acg_credentials.js`, and `playwright/acg_restart.js` now use Playwright locator handlers to dismiss the "Session extended" toast, and `acg_extend.js` now replaces the DOM evaluate dismiss path with a locator-based close button click in both immediate and non-immediate exit paths; committed as `e66d028` (`fix(acg): replace DOM evaluate toast dismiss with Playwright locator + addLocatorHandler`) and pushed to `origin/fix/next-improvements-5`. Validation used `node --check playwright/acg_extend.js`, `node --check playwright/acg_credentials.js`, and `node --check playwright/acg_restart.js`.

- **COMPLETE:** `playwright/acg_extend.js` now waits for the "Session extended" toast to appear and dismisses it before exiting in both the immediate and non-immediate paths, preventing the toast from persisting into the next CDP-backed script run; committed as `97fca3c` (`fix(acg-extend): dismiss Session extended toast before exit — it persists and blocks next script`) and pushed to `origin/fix/next-improvements-5`. Validation used `node --check playwright/acg_extend.js`.

- **COMPLETE:** `playwright/acg_credentials.js` now re-opens the panel inside `_waitForCredentials` when `Open Sandbox` becomes visible again, dismissing any dialog and re-clicking `Open Sandbox` so the credential wait no longer hangs after the panel closes; committed as `7d04391` (`fix(acg-credentials): re-open panel inside waitForCredentials when Open Sandbox button reappears`) and pushed to `origin/fix/next-improvements-5`. Validation used `node --check playwright/acg_credentials.js`.

- **COMPLETE:** `playwright/acg_credentials.js` and `playwright/acg_restart.js` now dismiss the "Session extended" success toast in addition to the existing "Extend Your Session" dialog, and `acg_credentials.js` now pre-dismisses plus `force: true` clicks `Open Sandbox` so the toast no longer blocks pointer events; committed as `e5e38d6` (`fix(acg): dismiss Session extended toast — it shares alertdialog role and blocks Open Sandbox click`) and pushed to `origin/fix/next-improvements-5`. Validation used `node --check playwright/acg_credentials.js` and `node --check playwright/acg_restart.js`.

- **COMPLETE:** `playwright/acg_extend.js` now uses `_cdpBrowser.close()` instead of `_cdpBrowser.disconnect()` for the CDP cleanup path, matching Playwright's connectOverCDP behavior and avoiding the `disconnect is not a function` error; committed as `52dffbc` (`fix(acg-extend): replace .disconnect() with .close() — CDP Browser has no disconnect method`) and pushed to `origin/fix/next-improvements-5`. Validation used `node --check playwright/acg_extend.js`.

- **COMPLETE:** `playwright/acg_restart.js` now polls for `Delete Sandbox` after `Open Sandbox` and dismisses the "Extend Your Session" dialog on every 500 ms tick until the button appears, replacing the one-shot `waitForSelector` path that could stall behind a late modal; committed as `a9cb1c1` (`fix(acg-restart): poll + dismiss Extend dialog while waiting for Delete Sandbox button`) and pushed to `origin/fix/next-improvements-5`. Validation used `node --check playwright/acg_restart.js`.

- **COMPLETE:** `playwright/acg_restart.js` now scrolls the `Delete Sandbox` button back into view and retries the click up to 3 times with an 800 ms settle pause, preventing the panel animation viewport shift from leaving the element outside the viewport; committed as `fd50c7f` (`fix(acg-restart): scroll + retry Delete Sandbox click — panel animation causes viewport shift`) and pushed to `origin/fix/next-improvements-5`. Validation used `node --check playwright/acg_restart.js`.

- **MERGED PR #26:** `fix/next-improvements-4` → main (`fbcecc24`). Visibility guard fix for "Extend Your Session" dialog: `offsetParent !== null && getComputedStyle(d).display !== 'none'` added to both detection and selection paths. Copilot caught incomplete fix (guard missing from `.find()` path). Retro: `docs/retro/2026-05-23-pr26-retrospective.md`.

- **MERGED PR #25:** `fix/next-improvements-3` → main (`2e698cf`). Extend Your Session modal robustness (background watcher + point-in-time dismissals) + LaunchDaemon plist idempotency. Retro: `docs/retro/2026-05-22-fix-next-improvements-3-retrospective.md`.

- **MERGED PR #23:** `fix/next-improvements` → main (`48afc0a4`). Credential masking in `bin/acg-credential-test`; extraction progress visibility in `playwright/acg_credentials.js`. Copilot: caught locator divergence + CHANGELOG wording.

- **COMPLETE:** `acg_extend.js` midnight-wrap guard now only rolls to tomorrow when the time gap is ≤ 60 minutes, so expired sandboxes report negative TTL instead of a wrapped next-day value; committed as `05ae7d1` (`fix(acg-extend): narrow midnight-wrap guard to 60 min so expired sandboxes report negative TTL`) and pushed to `origin/fix/acg-extend-midnight-wrap`.

- **COMPLETE:** `extend provider scope + CFn template removal` — `fix/stale-cred-restart` now selects the provider-specific `Open Sandbox` card via its heap id (`AWS Sandbox`, `Azure Sandbox`, `Google Cloud Sandbox`), keeps `bin/acg-extend-test` pinned to the existing CDP session so it cannot spawn a second Chrome, and removes `scripts/etc/acg-cluster.yaml` from lib-acg. Committed as `80df13d` (`fix(acg-extend): provider-scoped button selection; remove misplaced CFn template`) and pushed to `origin/fix/stale-cred-restart`. Validation used `node --check playwright/acg_extend.js`, `shellcheck bin/acg-extend-test`, and a direct CDP websocket probe because Playwright's browser-level CDP attach failed on Chrome 147 (`Browser.setDownloadBehavior` unsupported). Issue doc: `docs/issues/2026-05-21-acg-extend-cdp-attach-fails-on-chrome-147.md`.

- **COMPLETE:** `playwright/acg_credentials.js` now scopes GCP credential visibility and extraction to the Google Cloud provider card, and `playwright/acg_restart.js` now guards `_cdpBrowser.disconnect()` with `try/catch`; committed as `b3195c3` (`fix(acg-credentials): scope GCP extraction to provider card; fix restart disconnect TypeError`) and pushed to `origin/fix/stale-cred-restart`. Validation used `node --check playwright/acg_credentials.js` and `node --check playwright/acg_restart.js`.

- **COMPLETE:** `playwright/acg_credentials.js` now reduces the provider-label DOM walk depth from 12 to 6, `playwright/acg_restart.js` now scopes Start Sandbox selection to the active provider card and uses provider-specific delete-confirmation text, and `bin/acg-credential-test` forwards `--provider` through restart; committed as `fc7b5e9` (`fix(acg-credentials): reduce DOM walk depth; provider-scope restart Start Sandbox`) and pushed to `origin/fix/stale-cred-restart`. Validation used `node --check playwright/acg_credentials.js`, `node --check playwright/acg_restart.js`, `shellcheck -S warning bin/acg-credential-test`, and `_agent_audit`.

- **COMPLETE:** `playwright/acg_credentials.js` now provider-scopes Open/Start button lookup and `_waitForCredentials` to the active provider card; committed as `ed054a6` (`fix(acg-credentials): provider-scope Open/Start buttons and waitForCredentials`) and pushed to `origin/fix/stale-cred-restart`. Validation used `node --check playwright/acg_credentials.js`.

- **COMPLETE:** Reverted `acg_credentials.js` to AWS-working state (pre-GCP-scoping); GCP credential extraction scoping preserved on `fix/gcp-credentials-scoping` branch for follow-on work. Provider-scoped restart fixed and `--provider` arg forwarded through `bin/acg-credential-test`. Committed as `0c8a9c9` (`revert(acg-credentials): restore AWS-working credential extraction`). CHANGELOG updated with all three fixes for this PR. Ready for PR creation on `fix/stale-cred-restart`.

## v0.1.0 Track (branch: `main`)

- **COMPLETE:** `acg_extend.js` now exposes a `--check` mode that prints `REMAINING_MINS:<n>` without extending, and `scripts/plugins/acg.sh` now provides `acg_check_ttl()`; merged to main as `9c9b9b44` (PR #15).
- **COMPLETE:** `acg_extend` now calls `_cdpBrowser.disconnect()` on exit instead of skipping cleanup for CDP-attached sessions, preventing the Node process from hanging after a successful extend; merged to main as `b7d1dd7` (`fix(acg-extend): disconnect CDP browser on exit to prevent node process hang`); PR: https://github.com/wilddog64/lib-acg/pull/14
- [x] **Repo skeleton** — COMPLETE. CLAUDE.md, README.md, package.json, placeholder
      scripts/lib/cdp.sh, scripts/plugins/acg.sh, scripts/plugins/gcp.sh, scripts/vars.sh,
      playwright/, memory-bank/.
- [x] **lib-foundation subtree** — COMPLETE. Present under scripts/lib/foundation/.
- [x] **Phase 3 migration** — COMPLETE (`5c0e8e2`). Copied acg.sh, gcp.sh, playwright/*.js, vars.sh from
      k3d-manager; extracted _browser_launch + _cdp_ensure_acg_session into cdp.sh.
- [x] **Pre-commit hooks / CI** — COMPLETE (`5c0e8e2`). GitHub Actions and pre-commit hook are present.
- [x] **ACG credential extraction misses visible sandbox** — MERGED PR #2 (`7cb7f64`). Copilot review comments addressed; CI green. Bug: `docs/bugs/2026-04-28-acg-credentials-cdp-context-miss.md`.
- [x] **ACG extend surface timing gap** — FIXED, MERGED PR #3. `playwright/acg_extend.js` dismisses lingering confirmation modals, bounds per-selector waits to the remaining deadline, sanitizes failure screenshot labels. Bug: `docs/bugs/2026-04-26-acg-extend-session-extended-modal-blocks-button.md`.
- [x] **acg_credentials waitForFunction timeout** — FIXED (`076f65d`). `playwright/acg_credentials.js` now passes `null` as the `waitForFunction` arg so the 60s credential timeout is applied as intended. Spec: `docs/plans/bugfix-acg-credentials-waitforfunction-timeout.md`.
- [x] **acg_credentials timeout values + _waitForSandboxEntry arg-slot bug** — MERGED PR #5 (`f744901`). `playwright/acg_credentials.js`: `_waitForSandboxEntry` null arg fixed; `_waitForCredentials` 60s→180s; `OVERALL_TIMEOUT_MS` simplified to 300s constant. Retro: `docs/retro/2026-05-02-pr5-acg-credentials-timeout-values-retrospective.md`.
- [x] **acg_credentials provision timeout + waitForFunction CDP reliability** — MERGED PR #6 (`671b8b23`). Locator polling 420s; `OVERALL_TIMEOUT_MS` raised to 780s (300s waitForURL + 420s creds + 60s buffer). Copilot: error message clarity + OVERALL_TIMEOUT_MS math fix. Retro: `docs/retro/2026-05-02-pr6-acg-credentials-provision-timeout-retrospective.md`.
- [x] **CDP empty-contexts fix** — MERGED PR #7 (`027b5765`). PUT `/json/new` blank tab + disconnect guard. Retro: `docs/retro/2026-05-02-pr7-cdp-empty-contexts-retrospective.md`.
- [x] **CDP reconnect after blank tab** — MERGED PR #8 (`30917444`). `contexts()` stale after blank tab — disconnect+reconnect required. Retro: `docs/retro/2026-05-02-pr8-cdp-reconnect-retrospective.md`.
- [x] **Chrome SingletonLock collision** — MERGED PR #9 (`79a6acdd`). `cdp.sh` stops the chrome-cdp launchd agent + removes stale `SingletonLock` before launching. Post-merge fix: `launchctl bootout` replaces deprecated `launchctl unload`. Retro: `docs/retro/2026-05-03-pr9-chrome-singleton-lock-retrospective.md`.
- [x] **_browser_launch dead Linux else-block** — FIXED (`5f45069`). Replace 17-line unreachable Linux
      branch with _err one-liner. Spec: `docs/bugs/2026-05-07-browser-launch-linux-dead-code.md`.
      Branch: `fix/post-merge-pr9-cleanup`.
- [x] **extend provider scope + CFn template removal** — COMPLETE (`80df13d`). Spec: `docs/plans/v0.2.0-bugfix-extend-provider-scope.md`. Branch: `fix/stale-cred-restart`.
- [ ] **BATS tests** — PLANNED. Add tests/lib/cdp.bats for cdp.sh primitives.
- [x] **Extend Your Session dialog handling + test wrappers** — FIXED (`be80fbe`). `playwright/acg_credentials.js` now detects the dialog during sandbox entry and credential polling, dismisses it with bringToFront+Enter (best-effort; WARN fallback if dialog persists — credentials populate via Extend path regardless). The repo has new `bin/acg-credential-test` and `bin/acg-extend-test` wrappers for direct Playwright runs.
- [x] **Makefile setup/check/lint targets** — FIXED (`c5c6d2f`). Added repo-root `Makefile` with `setup`, `check`, `lint`, and `help`; validated `make help`, `make check`, `make lint`, and `make -n setup`.
- [x] **Copilot instructions + pre-commit hook** — FIXED (`afde6a8`). Added `.github/copilot-instructions.md`, executable `.githooks/pre-commit`, and replaced `Makefile` with `setup`, `check`, `lint`, `credential-test`, `extend-test`, and `help`; validated `shellcheck -S warning .githooks/pre-commit`.
- [x] **CI shellcheck for bin/ scripts** — FIXED (`4f32016`). Added a `Run shellcheck on bin/ scripts` step to `.github/workflows/ci.yml` before the node syntax checks; validated `yamllint .github/workflows/ci.yml`.
