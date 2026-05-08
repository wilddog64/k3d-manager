# Active Context — lib-acg

## Current Branch: `bug/chrome-singleton-lock-collision`

**Repo created:** 2026-04-25
**Status:** Fix committed and pushed (`cbd5234`). Chrome `SingletonLock` collision blocks automation launch. Branch: `bug/chrome-singleton-lock-collision`.

## Phase Status

- [x] **Phase 2** — COMPLETE. Repo skeleton created; lib-foundation subtree pending.
- [x] **Phase 3** — COMPLETE. Migrated acg.sh, gcp.sh, playwright scripts, vars.sh, and
      extracted _browser_launch + _cdp_ensure_acg_session into scripts/lib/cdp.sh.
      Source commit on main: `5c0e8e2`.
- [x] **ACG credential extraction misses visible sandbox** — FIXED in PR #2 (`https://github.com/wilddog64/lib-acg/pull/2`). Copilot review comments addressed and both inline threads resolved. Latest code commit `1ddbf7c` has GitHub Actions CI green; local checks passed (`npm run check`, `node --check playwright/acg_credentials.js`, `shellcheck scripts/**/*.sh`). Merge is blocked only because the PR is still draft: connector ready-for-review mutation failed with a response-shape error, shell GitHub token returned 401, and GitHub rejected merge with `Pull Request is still a draft`. Bug: `docs/bugs/2026-04-28-acg-credentials-cdp-context-miss.md`.
- [ ] **ACG extend surface timing gap** — REVIEW FIXES COMPLETE. `playwright/acg_extend.js` now dismisses lingering confirmation modals, bounds per-selector waits to the remaining deadline, and sanitizes failure screenshot labels. PR #3 (`https://github.com/wilddog64/lib-acg/pull/3`), commits `c442490` and `11df1fb`. Copilot review threads were addressed and resolved. Bug: `docs/bugs/2026-04-26-acg-extend-session-extended-modal-blocks-button.md`.
- [x] **acg_credentials waitForFunction timeout** — FIXED (`076f65d`). `playwright/acg_credentials.js` now passes `null` as the `waitForFunction` arg so the 60s credential timeout is applied as intended. Spec: `docs/plans/bugfix-acg-credentials-waitforfunction-timeout.md`.
- [x] **acg_credentials timeout values** — FIXED (`315e9fe`). `playwright/acg_credentials.js` now passes `null` to `_waitForSandboxEntry`, waits up to 180s for credentials, and extends the non-first-run overall timeout to 300s. Spec: `docs/plans/bugfix-acg-credentials-timeout-values.md`.
- [x] **acg_credentials provision timeout** — FIXED (`9f6bf71`). `playwright/acg_credentials.js` now uses locator polling for credentials up to 420s and extends the non-first-run overall timeout to 660s. Spec: `docs/bugs/2026-05-02-acg-credentials-provision-timeout.md`.

## Merged: CDP empty-contexts fix (PR #7, `027b5765`)
- Open blank tab via PUT `/json/new` when `contexts()` returns `[]`
- Guard `_cdpBrowser.disconnect()` behind `if (!browserContext)`
- Retro: `docs/retro/2026-05-02-pr7-cdp-empty-contexts-retrospective.md`
- enforce_admins: restored on main

## Open: CDP reconnect after blank tab (DONE)
Branch: `fix/acg-credentials-cdp-reconnect`
Bug: `docs/bugs/2026-05-02-acg-credentials-cdp-reconnect-after-blank-tab.md`
Commit: `73771ba`
Root cause: `_cdpBrowser.contexts()` is not live — returns stale `[]` even after PUT
`/json/new` creates a tab, because Playwright doesn't materialize a BrowserContext for
the default context from `Target.targetCreated` events post-connect. Falls through to
`launchPersistentContext`; profile still locked by CDP Chrome → Chrome exits
(`[pid=N] <gracefully close end>`).
Fix: disconnect + reconnect after blank tab so fresh `connectOverCDP` sees the new target.

## Open: Chrome SingletonLock collision (DONE)
Branch: `bug/chrome-singleton-lock-collision`
Bug: `docs/bugs/2026-05-02-chrome-singleton-lock-collision.md`
Chrome fails to launch because a previous instance or the background agent is holding
the profile lock. `scripts/lib/cdp.sh` now stops the Chrome CDP launchd agent before
taking over the browser profile and uses a robust process-in-use check before
removing stale `SingletonLock` files. Commit: `cbd5234`.

## Consumed By

- `k3d-manager` — will pull via git subtree at `scripts/lib/acg/` (Phase 4)
