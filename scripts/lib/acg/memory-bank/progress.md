# Progress — lib-acg

## v0.1.0 Track (branch: `main`)

- [x] **Repo skeleton** — COMPLETE. CLAUDE.md, README.md, package.json, placeholder
      scripts/lib/cdp.sh, scripts/plugins/acg.sh, scripts/plugins/gcp.sh, scripts/vars.sh,
      playwright/, memory-bank/.
- [x] **lib-foundation subtree** — COMPLETE. Present under scripts/lib/foundation/.
- [x] **Phase 3 migration** — COMPLETE (`5c0e8e2`). Copied acg.sh, gcp.sh, playwright/*.js, vars.sh from
      k3d-manager; extracted _browser_launch + _cdp_ensure_acg_session into cdp.sh.
- [x] **Pre-commit hooks / CI** — COMPLETE (`5c0e8e2`). GitHub Actions and pre-commit hook are present.
- [x] **ACG credential extraction misses visible sandbox** — FIXED in PR #2 (`https://github.com/wilddog64/lib-acg/pull/2`). Copilot review comments addressed and both inline threads resolved. Latest code commit `1ddbf7c` has GitHub Actions CI green; local checks passed (`npm run check`, `node --check playwright/acg_credentials.js`, `shellcheck scripts/**/*.sh`). Merge is blocked only because the PR is still draft: connector ready-for-review mutation failed with a response-shape error, shell GitHub token returned 401, and GitHub rejected merge with `Pull Request is still a draft`. Bug: `docs/bugs/2026-04-28-acg-credentials-cdp-context-miss.md`.
- [ ] **ACG extend surface timing gap** — REVIEW FIXES COMPLETE. `playwright/acg_extend.js` now dismisses lingering confirmation modals, bounds per-selector waits to the remaining deadline, and sanitizes failure screenshot labels. PR #3 (`https://github.com/wilddog64/lib-acg/pull/3`), commits `c442490` and `11df1fb`. Copilot review threads were addressed and resolved. Bug: `docs/bugs/2026-04-26-acg-extend-session-extended-modal-blocks-button.md`.
- [x] **acg_credentials waitForFunction timeout** — FIXED (`076f65d`). `playwright/acg_credentials.js` now passes `null` as the `waitForFunction` arg so the 60s credential timeout is applied as intended. Spec: `docs/plans/bugfix-acg-credentials-waitforfunction-timeout.md`.
- [x] **acg_credentials timeout values + _waitForSandboxEntry arg-slot bug** — MERGED PR #5 (`f744901`). `playwright/acg_credentials.js`: `_waitForSandboxEntry` null arg fixed; `_waitForCredentials` 60s→180s; `OVERALL_TIMEOUT_MS` simplified to 300s constant. Retro: `docs/retro/2026-05-02-pr5-acg-credentials-timeout-values-retrospective.md`.
- [x] **acg_credentials provision timeout + waitForFunction CDP reliability** — MERGED PR #6 (`671b8b23`). Locator polling 420s; `OVERALL_TIMEOUT_MS` raised to 780s (300s waitForURL + 420s creds + 60s buffer). Copilot: error message clarity + OVERALL_TIMEOUT_MS math fix. Retro: `docs/retro/2026-05-02-pr6-acg-credentials-provision-timeout-retrospective.md`.
- [x] **CDP empty-contexts fix** — MERGED PR #7 (`027b5765`). PUT `/json/new` blank tab + disconnect guard. Retro: `docs/retro/2026-05-02-pr7-cdp-empty-contexts-retrospective.md`.
- [x] **CDP reconnect after blank tab** — DONE (`73771ba`). Branch: `fix/acg-credentials-cdp-reconnect`. Bug: `docs/bugs/2026-05-02-acg-credentials-cdp-reconnect-after-blank-tab.md`. `contexts()` stale after blank tab — disconnect+reconnect required.
- [ ] **Chrome SingletonLock Collision** — OPEN (2026-05-02). Chrome fails to launch because a previous instance or the background agent is holding the profile lock. Spec: `docs/bugs/2026-05-02-chrome-singleton-lock-collision.md`.
- [ ] **BATS tests** — PLANNED. Add tests/lib/cdp.bats for cdp.sh primitives.
