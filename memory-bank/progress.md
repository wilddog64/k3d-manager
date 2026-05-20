# Progress — lib-acg

## v0.1.0 Track — `fix/acg-extend-midnight-wrap` (active)

- **MERGED PR #15:** `fix/acg-sandbox-ttl-check` → main (`9c9b9b44`). `acg_extend.js` `--check` flag + `acg_check_ttl()` in `acg.sh`. Copilot: fixed Button First click bypass + help text mismatch.

- **COMPLETE:** `acg_extend.js` midnight-wrap guard now only rolls to tomorrow when the time gap is ≤ 60 minutes, so expired sandboxes report negative TTL instead of a wrapped next-day value; committed as `05ae7d1` (`fix(acg-extend): narrow midnight-wrap guard to 60 min so expired sandboxes report negative TTL`) and pushed to `origin/fix/acg-extend-midnight-wrap`.

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
- [ ] **BATS tests** — PLANNED. Add tests/lib/cdp.bats for cdp.sh primitives.
- [x] **Extend Your Session dialog handling + test wrappers** — FIXED (`be80fbe`). `playwright/acg_credentials.js` now detects the dialog during sandbox entry and credential polling, dismisses it with bringToFront+Enter (best-effort; WARN fallback if dialog persists — credentials populate via Extend path regardless). The repo has new `bin/acg-credential-test` and `bin/acg-extend-test` wrappers for direct Playwright runs.
- [x] **Makefile setup/check/lint targets** — FIXED (`c5c6d2f`). Added repo-root `Makefile` with `setup`, `check`, `lint`, and `help`; validated `make help`, `make check`, `make lint`, and `make -n setup`.
- [x] **Copilot instructions + pre-commit hook** — FIXED (`afde6a8`). Added `.github/copilot-instructions.md`, executable `.githooks/pre-commit`, and replaced `Makefile` with `setup`, `check`, `lint`, `credential-test`, `extend-test`, and `help`; validated `shellcheck -S warning .githooks/pre-commit`.
- [x] **CI shellcheck for bin/ scripts** — FIXED (`4f32016`). Added a `Run shellcheck on bin/ scripts` step to `.github/workflows/ci.yml` before the node syntax checks; validated `yamllint .github/workflows/ci.yml`.
