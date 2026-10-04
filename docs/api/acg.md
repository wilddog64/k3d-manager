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

## Validation

- `npm run check` runs the module JS syntax checks.
- `npm test` runs the Jest unit tests.
- `npm run test:e2e` and `make credential-test` remain manual browser gates.
