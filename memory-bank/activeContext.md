# Active Context — lib-acg

## Current Branch: `fix/next-improvements-4`

**Repo created:** 2026-04-25  
**Status:** PR #25 merged to main (2026-05-22, `2e698cf`); enforce_admins restored; next branch active.

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
