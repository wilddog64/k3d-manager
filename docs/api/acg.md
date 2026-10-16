# ACG Module

`scripts/lib/acg/` is the optional browser-automation module imported from lib-acg.

## Public API

- `acg_*` functions manage the AWS sandbox lifecycle and Chrome CDP wiring.
- `gcp_*` functions extract and manage GCP sandbox credentials.
- `cdp.sh` provides the shared Chrome CDP helpers used by both APIs.

## Layout

- `scripts/lib/acg/cdp.sh` loads `scripts/lib/system.sh` when the host has not already loaded it.
- `scripts/lib/acg/acg.sh` and `scripts/lib/acg/gcp.sh` source `vars.sh` and use the module-local
  `playwright/`, `bin/`, `etc/`, and `tests/` trees. The `acg-credential-test` / `acg-extend-test`
  entry points live in `scripts/lib/acg/bin/` and resolve their `REPO_ROOT` to the module dir. The
  repo-root `Makefile` `cd`s into the module before invoking them, so the live browser flow runs
  with the module as its working directory (matching the upstream lib-acg layout). It wraps the
  dev/test targets (`make check`, `make lint`, `make test`, `make credential-test`).
- Node dependencies are isolated to the module and installed with `npm ci` from the module
  `package-lock.json`.

## Session check and credential gate

`scripts/lib/acg/acg_session_check.js` decides whether the CDP browser holds an authenticated
Pluralsight session, attempting unattended login when it does not. `_cdp_ensure_acg_session`
(`cdp.sh`) is the shell entry point; it loads the credential from the store via
`_secret_load_data k3dm-acg-pluralsight username|password` and passes the values to the script as
`ACG_USERNAME` / `ACG_PASSWORD` environment variables — never as arguments.

Environment:

| Variable | Effect |
|---|---|
| `K3DM_ACG_REQUIRE_CREDENTIALS=1` | fail closed: exit `ACG_CREDENTIALS_REQUIRED` when the credential store is unusable, instead of falling back to a pre-existing session. Default unset preserves the fallback. |
| `K3DM_ACG_SKIP_SESSION_CHECK=1` | local debugging aid that skips the check entirely; never valid for an acceptance gate. |
| `PLAYWRIGHT_CDP_HOST` / `PLAYWRIGHT_CDP_PORT` | CDP endpoint, default `127.0.0.1:9222`. |

Markers written to stdout/stderr are the machine-readable contract — see the session-check table
in the repo `README.md`. `ACG_SESSION_OK` always carries a `path=` suffix, and the complete set of
values is `existing-session`, `auto-login` and `manual-login`, so a caller can tell a working
unattended login from a reused human session. `manual-login` is only reachable when
`K3DM_NONINTERACTIVE` is unset **and** stdout is a TTY, so it never occurs in CI or an unattended
gate; a gate that must prove unattended login should accept `auto-login` alone and treat any
unrecognized `path=` value as a failure. `ACG_CREDENTIALS` reports only the state of each field
(`present`, `empty`, `absent`); credential values are never printed.

Two selector notes for anyone touching `playwright/lib/pluralsight_login.js`:

- CSS attribute **values** are case-sensitive while attribute **names** are not. Pluralsight's
  identity form is PascalCase (`name="Username"`), so every name/id selector arm carries the ` i`
  flag. A lowercase arm silently matches nothing on a fully rendered form.
- Playwright implements its own CSS parser, so verifying a selector with
  `document.querySelectorAll` in a browser console proves nothing about `page.locator()`. Measure
  with `page.locator(...).count()`.

## Sandbox TTL watcher and extend

A sandbox has a 4-hour TTL and can be extended inside its last hour. `playwright/acg_extend.js`
does one check-and-extend pass; the watcher runs it on a schedule.

| Function | What it does |
|---|---|
| `acg_watch_start [sandbox-url]` | macOS: installs the launchd agent `com.k3d-manager.acg-watch` (`StartInterval` 1800 s, persists across reboots). The generated wrapper `~/.local/share/k3d-manager/acg-watch-run.sh` calls `acg_extend.js` with an absolute Node path, because launchd has no Homebrew `PATH`. Logs go to `/tmp/k3d-manager-acg-watch.{out,err}`. |
| `acg_watch_stop` | Unloads the agent and removes the plist and the wrapper. |
| `acg_watch [interval_seconds]` | In-process loop for Linux or a foreground shell; checks every `interval_seconds` (default 1800) and stops when the EC2 instance is gone. A failed extend is retried up to 3 times, `ACG_WATCH_RETRY_INTERVAL` seconds apart (default 600). |
| `acg_extend_playwright <sandbox_url>` | One pass of `acg_extend.js`; what both watchers call. |

One pass of `acg_extend.js`:

1. When an Extend button is already visible, it clicks it and exits.
2. Otherwise it reads the "Auto Shutdown at <time>" text and computes the minutes left. When more
   than 65 remain it logs `Extension window not open yet` and exits 0, so most passes are no-ops.
   This is why the interval must be well under 65 minutes. At the old 3.5-hour interval, a pass
   usually fell before the window and the next one came after expiry.
3. Inside the window it waits up to 15 seconds for the button, which can be on the sandbox card
   or in an "Extend Your Session" dialog. If it is still missing, it reloads the page once, then
   falls back to Open Sandbox. On failure it logs the visible button labels, with credential-shaped
   labels filtered, and saves a viewport screenshot.

The page shows the shutdown time of day without a date. `_remainingMinsFromShutdown` resolves it
to the instant within 6 hours of now, because a sandbox never has more than 6 hours left:

- a time just past midnight is tomorrow (seen at 11:59 PM, 12:30 AM is 31 minutes away)
- a time more than 6 hours ahead is yesterday's shutdown, so the sandbox has expired (seen at
  1:12 AM, 11:24 PM is −108 minutes, not about 22 hours)

A zero or negative result skips the button wait and takes the expired-sandbox path. Passing
`--check` as the second argument prints `REMAINING_MINS:<n>` and exits without extending.

## Validation

- `npm run check` runs the module JS syntax checks.
- `npm test` runs the Jest unit tests.
- `npm run test:e2e` and `make credential-test` remain manual browser gates.
