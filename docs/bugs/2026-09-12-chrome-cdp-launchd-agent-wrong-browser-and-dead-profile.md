# `com.k3d-manager.chrome-cdp` launchd agent launches the wrong browser against a dead profile

**Date:** 2026-09-12
**Status:** OPEN — root cause measured, fix not yet written.
**Branch (all work):** `fix/acg-prism-monogram-selector`
**Severity:** high — the agent is the designed mechanism for keeping the Pluralsight
session alive between runs. Because it is broken, it has never been usable, so every run
that kills Chrome costs the operator a manual re-login.

## Why this matters

The Pluralsight auth cookie `.pluralsight.com Identity.Session` is **non-persistent**
(`is_persistent=0`, `has_expires=0`, no expiry recorded). It lives only for the lifetime of
the browser process. So "shut Chrome down after the test" and "keep the ACG session" are
mutually exclusive **unless** a long-lived CDP browser holds the session. That is exactly
what `com.k3d-manager.chrome-cdp` exists to do — and it is currently not loadable.

## Problem 1 — the agent launches the operator's personal Chrome

`_acg_chrome_cdp_write_plist` in `scripts/lib/acg/acg.sh:338` hardcodes:

```
    <string>/Applications/Google Chrome.app/Contents/MacOS/Google Chrome</string>
```

But `cdp.sh:142` resolves the browser through Playwright:

```bash
_pw_chrome_bin="$(NODE_PATH="${_LIB_ACG_ROOT}/node_modules" node -e 'process.stdout.write(require("playwright").chromium.executablePath())' 2>/dev/null || true)"
```

The move to the Playwright-managed Chromium was a deliberate decision — see
`docs/bugs/2026-07-06-cdp-use-playwright-managed-chromium.md`. The plist writer was never
updated, so the agent and the live code path launch **different browsers**. It would also
put `--remote-debugging-port` on the operator's personal Chrome, which is not acceptable.

## Problem 2 — the agent points at a profile that has never held a session

`vars.sh:21`:

```bash
export PLAYWRIGHT_AUTH_DIR="${HOME}/.local/share/k3d-manager/profile"
```

`cdp.sh` (three places — lines 23, 51, 119) and the launch at line 151:

```bash
local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/pw-profile}"
```

`vars.sh` is sourced only by `acg.sh:34` and `gcp.sh:26`. The `credential-test` path does
**not** source it, so `PLAYWRIGHT_AUTH_DIR` is unset there and the `pw-profile` fallback
wins. Confirmed against the running browser:

```
--user-data-dir=/Users/cliang/.local/share/k3d-manager/pw-profile
```

The two directories are measurably different:

| profile dir | referenced by | pluralsight cookies | `Identity.Session` | cookie DB mtime |
|---|---|---|---|---|
| `profile`    | `vars.sh` → plist | **0** | none | Aug 20 |
| `pw-profile` | `cdp.sh` (actual) | **34** | **1, live** | Sep 12 07:16 |

So the agent would launch against an empty profile and never be signed in. The `vars.sh`
comment claiming the path "must match `_ACG_CHROME_CDP_AUTH_DIR`" documents an invariant
that is already violated.

## Problem 3 — `KeepAlive` would fight the port reclaim

The plist sets `KeepAlive` `true` on port 9222. `_browser_launch` reclaims that port via
`_cdp_kill_port_listener` and `_cdp_stop_chrome_cdp_agent`. With the agent loaded and
pointing at the wrong browser/profile, launchd would immediately respawn a signed-out
Chrome onto 9222 after every reclaim — worse than not having the agent at all. This is why
the agent must not be loaded until problems 1 and 2 are fixed.

## Required change

### 1. `scripts/lib/acg/vars.sh`

Point the single source of truth at the profile actually in use:

```bash
export PLAYWRIGHT_AUTH_DIR="${HOME}/.local/share/k3d-manager/pw-profile"
```

Do NOT delete or migrate `~/.local/share/k3d-manager/profile` — it is inert, and the
`vars.sh` header warns that removing a profile directory can trigger ACG bot-detection.
Leave it on disk.

### 2. `scripts/lib/acg/acg.sh` — `_acg_chrome_cdp_write_plist`

Resolve the browser binary the same way `cdp.sh` does, rather than hardcoding a path.
Extract the resolution so both callers share it (put the helper in `cdp.sh` next to the
existing logic and call it from `acg.sh`, or add it to `acg.sh` and have `cdp.sh:142`
call it — either is acceptable, but there must be exactly ONE implementation).

The writer must fail loudly rather than emit a plist naming a non-existent binary:

```bash
_acg_chrome_cdp_write_plist() {
  local _chrome_bin
  _chrome_bin="$(_acg_resolve_cdp_browser_bin)" || return 1
  if [[ -z "${_chrome_bin}" || ! -x "${_chrome_bin}" ]]; then
    _err "[acg] Playwright-managed Chromium not found — run 'npm install' in ${_LIB_ACG_ROOT} before installing the CDP agent"
    return 1
  fi
  ...
}
```

and emit `<string>${_chrome_bin}</string>` in `ProgramArguments` in place of the hardcoded
`/Applications/Google Chrome.app/...` line.

### 3. Keep `KeepAlive`, but make the invariant explicit

`KeepAlive` is correct once the agent launches the right browser against the right
profile — that is the whole point of a long-lived session holder. Add a comment above the
`KeepAlive` key in the heredoc noting that `_cdp_stop_chrome_cdp_agent` must boot the agent
out before reclaiming port 9222, or launchd will respawn into the reclaimed port.

### 4. BATS — `scripts/tests/lib/acg.bats`

`_acg_chrome_cdp_write_plist` currently has **no** BATS coverage (verified: no test in
`acg.bats` or `acg_cdp.bats` references it). Add it there, following the existing
`HOME`-redirection style used by the other plist tests so nothing writes to the real
`~/Library/LaunchAgents`.

Add cases:

1. The rendered plist contains the Playwright-resolved binary path and **no** occurrence of
   `/Applications/Google Chrome.app`.
2. The rendered plist's `--user-data-dir` equals `PLAYWRIGHT_AUTH_DIR`, and that value ends
   in `pw-profile`.
3. `_acg_chrome_cdp_write_plist` returns non-zero and writes **no** plist when the browser
   binary cannot be resolved.

## Definition of done

- [ ] `grep -rn "/Applications/Google Chrome.app" scripts/lib/acg/` prints nothing.
- [ ] `grep -rn "k3d-manager/profile\"" scripts/lib/acg/` prints nothing (only `pw-profile`).
- [ ] Exactly one implementation of the browser-binary resolution exists.
- [ ] `make lint`, `make shellcheck-lib`, `make bats` green, including the new cases.
- [ ] `cd scripts/lib/acg && npm run check && npm test` green.
- [ ] Only `vars.sh`, `acg.sh`, `cdp.sh` and the BATS file are modified.

## Operator step — NOT part of this change, do not automate it

After this lands, the agent still has to be installed once, and only while port 9222 is
free. Installing it while the current signed-in Chrome is running would collide on the
profile's `SingletonLock`. Sequence is the operator's call, not the agent's.

## What NOT to do

- Do NOT create a PR, merge, or commit to `main`.
- Do NOT use `--no-verify`.
- Do NOT run `launchctl load`/`bootstrap` for `com.k3d-manager.chrome-cdp`, or any other
  `launchctl` mutation. Writing the plist template is in scope; loading it is not.
- Do NOT delete, move, or "migrate" `~/.local/share/k3d-manager/profile` or `pw-profile`.
- Do NOT run `make credential-test` / `restart-test` / `extend-test`, launch Chrome, or
  touch port 9222 — a live signed-in session is there and killing it destroys
  `Identity.Session`.
- Do NOT print, echo, or log credential values.
