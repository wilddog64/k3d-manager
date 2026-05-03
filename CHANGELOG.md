# Changelog

All notable changes to lib-acg will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Fixed
- `_waitForSandboxEntry`: pass `null` as `waitForFunction` arg so the timeout option reaches the options slot (same arg-slot bug as `_waitForCredentials`)
- `_waitForCredentials`: fix arg-slot bug (pass `null` as `waitForFunction` arg) and increase timeout from 60s to 180s — sandbox provisioning can take 60–120s
- `OVERALL_TIMEOUT_MS`: simplify redundant conditional to a single 300s constant — both first-run and non-first-run now use the same deadline
- `_waitForCredentials`: replace unreliable `waitForFunction` (in-page DOM query broken in CDP mode) with Playwright locator polling loop; increase credential wait from 180s to 420s to handle slower sandbox provisioning
- `OVERALL_TIMEOUT_MS`: increase from 300s to 780s (300s waitForURL + 420s credential polling + 60s buffer) to accommodate worst-case first-run flows
- CDP empty-contexts: open blank tab via `/json/new` HTTP API when `_cdpBrowser.contexts()` returns `[]` (Chrome has no open tabs); re-query after 500ms to expose the profile context and avoid falling through to `launchPersistentContext` which fails with a profile-lock error
- CDP disconnect guard: wrap `_cdpBrowser.disconnect()` in `if (!browserContext)` so the browser is only disconnected when the blank-tab recovery also fails — prevents disconnecting a context that was successfully recovered
- CDP blank-tab reconnect: after PUT `/json/new`, disconnect and reconnect via `connectOverCDP` instead of re-querying the stale `contexts()` list — Playwright does not materialize BrowserContext from `Target.targetCreated` events post-connect, so a fresh connection is required to see the new tab
- Chrome SingletonLock collision: stop the `chrome-cdp` launchd agent before taking over the shared profile and remove stale `SingletonLock` files only when the profile is not in use

### Added
- CI workflow: shellcheck, node --check, yamllint on PRs to main
- Pre-commit hook: subtree guard + shellcheck + node --check on staged files
- Phase 3 migration: acg.sh, gcp.sh, cdp.sh, vars.sh, playwright scripts, acg-cluster.yaml
