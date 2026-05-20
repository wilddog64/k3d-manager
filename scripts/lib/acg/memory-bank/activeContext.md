# Active Context — lib-acg

## Current Branch: `docs/next-improvements`

**Repo created:** 2026-04-25
**Status:** PR #14 merged to main (2026-05-19); PR #15 merged (2026-05-19); PR #16 merged to main (2026-05-20); enforce_admins restored.

- **COMPLETE:** PR #16 merged — `acg_extend.js` midnight-wrap guard now uses forward-looking 360-minute threshold; expired sandboxes report negative TTL; merged to main as `04ffd365`.

## Just Merged: PR #16 — midnight-wrap guard forward-looking threshold

- [x] `acg_extend.js`: replace backward-gap logic with forward-looking 360-min threshold
- [x] Copilot review 9 findings: logic inversion, Playwright waiter, button-click timing
- [x] Merged to main as `04ffd365` (2026-05-20)
- [x] Branch protection enforce_admins re-enabled
- [x] Retrospective: `docs/retro/2026-05-20-pr16-midnight-wrap-retrospective.md`

## Just Merged: PR #15 — Sandbox TTL Check

- [x] `acg_extend.js`: add `--check` mode to probe remaining sandbox TTL without extending
- [x] `acg.sh`: add `acg_check_ttl()` wrapper function for TTL queries
- [x] Copilot review 2 findings: Button First click path running before flag check, help text mismatch
- [x] Merged to main as `9c9b9b44` (2026-05-19)
- [x] Branch protection enforce_admins re-enabled
- [x] Retrospective: `docs/retro/2026-05-19-pr15-sandbox-ttl-check-retrospective.md`

## Just Merged: PR #14 — acg_extend.js CDP disconnect hang fix

- [x] `_cdpBrowser.disconnect()` in finally block to release WebSocket and prevent Node event loop hang
- [x] Detect "Session extended" toast at startup; exit 0 if already visible instead of looping forever
- [x] Copilot review 5 findings: memory-bank descriptions, bug spec wording clarity, "Do NOT create a PR" removed from bug docs
- [x] Merged to main as `b7d1dd7` (2026-05-19)
- [x] Branch protection enforce_admins re-enabled
- [x] Retrospective: `docs/retro/2026-05-19-pr14-retrospective.md`

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
- PR #14 is now on main; subtree pull will bring in the CDP disconnect fix

## Consumed By

- `k3d-manager` — pulled via git subtree at `scripts/lib/acg/` (Phase 4 complete)
