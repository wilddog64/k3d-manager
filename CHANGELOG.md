# Changelog

All notable changes to lib-acg will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Fixed
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
