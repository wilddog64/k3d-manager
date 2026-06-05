# Active Context — lib-acg

## Current Branch: `feat/v0.1.1`

## Current Status (2026-06-05 — sandbox navLink.click() regression fix)
- **COMPLETE:** `playwright/lib/sandbox.js` `navigateToSandbox()` — removed `navLink.click()` conditional path that caused navigation to `s2.pluralsight.com/404.html`; always uses `window.location.assign()` for cloud-sandboxes SPA navigation, matching pre-refactor behavior; committed as `21d6e27` (`fix(sandbox): remove navLink.click() path — always use window.location.assign()`) and pushed to `origin/feat/v0.1.1`. Validation: `node --check playwright/lib/sandbox.js`. PR #36 open, CI green, Copilot findings fixed (`e0057c3`), all threads resolved.

## Previous Branch: `fix/playwright-screenshot-diagnosis`

## Current Status (2026-06-04 — Phase A screenshot diagnosis complete)
- **COMPLETE:** playwright screenshot diagnosis phase A — lib-acg commit `77c7dcc` on `fix/playwright-screenshot-diagnosis`; spec: `docs/plans/v1.6.0-playwright-screenshot-diagnosis.md`; `playwright/acg_credentials.js` and `playwright/acg_restart.js` now save `/tmp/k3dm-acg-screenshot-<ts>.png` on unhandled errors and print `INFO: Screenshot saved to ...` to stderr, and `acg_restart.js` hoists `page` to outer scope so the catch block can capture screenshots; validation used `node --check playwright/acg_credentials.js` and `node --check playwright/acg_restart.js`; commit message: `feat(playwright): save screenshot on failure for AI diagnosis`
- **PHASE B NOTE:** webhook screenshot ingestion remains a k3d-manager follow-on and is not part of this lib-acg branch.

## Previous Status (2026-05-25 — v0.3.1 bugfix sweep complete)
- **COMPLETE:** `scripts/hooks/pre-commit` now prints deleted filename references through a `while IFS= read -r _ref` loop instead of expanding `$_refs` unquoted, preventing word-splitting and format-string surprises; committed as `4e55392` (`fix(pre-commit): quote $_refs in printf — prevent word-splitting on filenames with spaces`) and pushed to `origin/fix/next-improvements-7`. Validation passed for `shellcheck -S warning scripts/hooks/pre-commit`.
- **COMPLETE:** `scripts/plugins/acg.sh` now returns `1` immediately when `node` is missing in `acg_check_ttl`, and emits `-1` when `REMAINING_MINS:` is absent by storing the parse result in `remaining`; committed as `4f7a1f3` (`fix(acg): acg_check_ttl — return 1 on missing node; return -1 sentinel when TTL unparseable`) and pushed to `origin/fix/next-improvements-7`. Validation passed for `shellcheck -S warning scripts/plugins/acg.sh`.
- **COMPLETE:** `package.json` and `package-lock.json` now both report version `0.3.0`, matching the shipped release; committed as `7f1261c` (`chore(package): align package.json and package-lock.json version to 0.3.0`) and pushed to `origin/fix/next-improvements-7`. Validation passed for `node --check playwright/*.js`.

**Repo created:** 2026-04-25  
**Status:** PR #28 merged to main (2026-05-24, `ee87aeb2`); enforce_admins restored on main; next branch active (`fix/next-improvements-7`). Retrospective written to `docs/retro/2026-05-24-pr28-retrospective.md`. Next subtree pull into k3d-manager to bring visibility guard fixes.

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

- **MERGED PR #27** — `fix/next-improvements-5` → main (`7c17da72`). Playwright automation reliability: toast dismissal architecture fixed (removed blocking dismiss from polling loop, consolidated to `addLocatorHandler` handlers), CDP Browser lifecycle corrected (`close()` instead of `disconnect()`), credential re-validation added to extend-test. 14 inter-related toast/CDP bugs collapsed to single coherent fix. Copilot caught button-selection ambiguity + disconnect guard. Retrospective: `docs/retro/2026-05-23-pr27-retrospective.md`.

- **MERGED PR #26** — `fix/next-improvements-4` → main (`fbcecc24`). Visibility guard fix for "Extend Your Session" dialog detection: added CSS check (`offsetParent !== null && getComputedStyle(d).display !== 'none'`) to `_dismissExtendYourSessionDialog`. Copilot caught incomplete fix (guard missing from `.find()` selection path). Retrospective: `docs/retro/2026-05-23-pr26-retrospective.md`.

- **MERGED PR #28** — `fix/next-improvements-6` → main (`ee87aeb2`). Visibility guard fix: three-part CSS check (`offsetParent !== null && getComputedStyle(d).display !== 'none' && getComputedStyle(d).visibility !== 'hidden'`) added to `acg_credentials.js` and `acg_restart.js` to fix false-positive "Extend Your Session" dialog detection. Pluralsight SPA keeps dismissed dialogs in DOM with `visibility:hidden`, but `innerText` still returns non-empty text. Copilot caught guard missing in a third location + `acg_restart.js` missing part of guard despite bug doc claim. Retrospective: `docs/retro/2026-05-24-pr28-retrospective.md`.

- **MERGED PR #23** — `fix/next-improvements` → main (`48afc0a4`). Two usability fixes: credential masking in terminal output (`bin/acg-credential-test` + `sed 's/=.*/=***/'`); extraction progress visibility in `playwright/acg_credentials.js` (`inputs.first().evaluate()` guarantees same-node evaluation). Copilot review caught locator divergence (Playwright CDN vs file-based) and CHANGELOG wording precision. All threads resolved cleanly. Retrospective: `docs/retro/2026-05-22-fix-credential-masking-retrospective.md`.


## Phase Status

- [x] **Phase 2** — COMPLETE. Repo skeleton created; lib-foundation subtree present.
- [x] **Phase 3** — COMPLETE. Migrated acg.sh, gcp.sh, playwright scripts, vars.sh, and
      extracted _browser_launch + _cdp_ensure_acg_session into scripts/lib/cdp.sh.
      Source commit on main: `5c0e8e2`.
- [x] **ACG credential extraction misses visible sandbox** — FIXED, MERGED PR #2.
      Bug: `docs/bugs/2026-04-28-acg-credentials-cdp-context-miss.md`.
- [x] **ACG extend surface timing gap** — FIXED, MERGED PR #3.
      Bug: `docs/bugs/2026-04-26-acg-extend-session-extended-modal-blocks-button.md`.
- [x] **acg_credentials waitForFunction timeout** — FIXED, MERGED PR #4 (`076f65d`).
      Spec: `docs/plans/bugfix-acg-credentials-waitforfunction-timeout.md`.
- [x] **acg_credentials timeout values** — FIXED, MERGED PR #5 (`f744901`).
- [x] **acg_credentials provision timeout** — FIXED, MERGED PR #6 (`671b8b23`).
- [x] **CDP empty-contexts fix** — MERGED PR #7 (`027b5765`).
      Retro: `docs/retro/2026-05-02-pr7-cdp-empty-contexts-retrospective.md`.
- [x] **CDP reconnect after blank tab** — MERGED PR #8 (`30917444`).
      Bug: `docs/bugs/2026-05-02-acg-credentials-cdp-reconnect-after-blank-tab.md`.
      Retro: `docs/retro/2026-05-02-pr8-cdp-reconnect-retrospective.md`.
- [x] **Chrome SingletonLock collision** — MERGED PR #9 (`79a6acdd`).
      Bug: `docs/bugs/2026-05-02-chrome-singleton-lock-collision.md`.
      Retro: `docs/retro/2026-05-03-pr9-chrome-singleton-lock-retrospective.md`.
      Post-merge fix: `launchctl bootout` replaces deprecated `launchctl unload`.

## Done: Extend Your Session dialog handling + test wrappers

- [x] Add `Extend Your Session` dialog detection/dismissal in `playwright/acg_credentials.js`
- [x] Add `bin/acg-credential-test` and `bin/acg-extend-test`
- [x] Validate with `node --check playwright/acg_credentials.js`, `node --check playwright/acg_extend.js`, and `shellcheck bin/acg-credential-test bin/acg-extend-test`
- [x] Commit `be80fbe` and push to `origin/fix/acg-credentials-extend-dialog`

## Done: Makefile setup/check/lint targets

- [x] Add root `Makefile` with `setup`, `check`, `lint`, and `help` targets
- [x] Validate `make help`, `make check`, `make lint`, and `make -n setup`
- [x] Commit `c5c6d2f` (`chore(makefile): add setup/check/lint targets for local development`) and push to `origin/fix/acg-credentials-extend-dialog`

## Done: Copilot instructions + pre-commit hook

- [x] Add `.github/copilot-instructions.md` with lib-acg review guidance
- [x] Add executable `.githooks/pre-commit` hook for staged `node --check` and `shellcheck`
- [x] Replace `Makefile` with `setup`, `check`, `lint`, `credential-test`, `extend-test`, and `help` targets
- [x] Validate `shellcheck -S warning .githooks/pre-commit`
- [x] Commit `afde6a8` (`chore(repo): add copilot-instructions and pre-commit hook`) and push to `origin/fix/acg-credentials-extend-dialog`

## Done: CI shellcheck for bin/ scripts

- [x] Add `Run shellcheck on bin/ scripts` step to `.github/workflows/ci.yml` before node syntax checks
- [x] Validate `yamllint .github/workflows/ci.yml`
- [x] Commit `4f32016` (`chore(ci): add shellcheck step for bin/ scripts`) and push to `origin/fix/acg-credentials-extend-dialog`

## Done: Post-merge PR #9 cleanup + browser-launch dead-code fix

Branch: `fix/post-merge-pr9-cleanup`
- [x] Fix `launchctl unload` → `launchctl bootout` in `scripts/lib/cdp.sh` (`dc53804`)
- [x] Add missing retros for PR #7, #8, #9 under `docs/retro/` (`dc53804`)
- [x] Correct stale memory-bank (activeContext.md + progress.md) (`dc53804`)
- [x] Remove dead Linux else-block from `_browser_launch` in `scripts/lib/cdp.sh` (`5f45069`)
      Spec: `docs/bugs/2026-05-07-browser-launch-linux-dead-code.md`

## Done: PR #11 — AWS credential extraction and dialog handling

- [x] `fix/acg-credentials-extend-dialog` merged to main (`feeb8e80`) — 2026-05-17
- [x] `bin/acg-credential-test`: writes to `~/.aws/credentials [default]`, validates with `sts:GetCallerIdentity`, suppresses credential stdout
- [x] `playwright/acg_credentials.js`: Extend Your Session dialog — bringToFront+Enter WARN fallback
- [x] Makefile, CI shellcheck, copilot-instructions, pre-commit hook
- [x] PR #12 open: `feat/acg-multi-provider` — fix `acg_extend.js` hang on Session extended toast

## Next: Subtree pull into k3d-manager

- k3d-manager `scripts/lib/acg/` is a git subtree of lib-acg main
- PR #23 is now on main; subtree pull will bring in credential masking + extraction visibility

## Consumed By

- `k3d-manager` — pulled via git subtree at `scripts/lib/acg/` (Phase 4 complete)
