# Bug: `_browser_launch` dies with `_antigravity_browser_ready: command not found` under a host

**Status:** FIXED — branch `fix/cdp-browser-ready-host-load`
**Filed:** 2026-10-05
**Severity:** High — the first `make up` after Chrome is closed fails at step 1 (exit 127)

## Symptom

k3d-manager `make up` (sandbox, `k3s-aws`), operator run 2026-10-05:

```
INFO: [acg-up] Extracting and validating AWS credentials (will restart sandbox on ghost-state failure)...
.../scripts/lib/foundation/scripts/lib/acg/cdp.sh: line 162: _antigravity_browser_ready: command not found
WARN: [acg-up] failed (exit 127) — cleaning up local processes...
make: *** [up] Error 127
```

A rerun succeeded, because the first run had already started Chrome in the background before it
died, so the rerun took the "reuse existing CDP browser" branch and never reached line 162.

## Root cause

`scripts/lib/acg/cdp.sh` loads foundation's `system.sh` only when the host has not:

```bash
if ! declare -f _run_command >/dev/null 2>&1; then
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/system.sh"
fi
```

That guard checks a proxy (`_run_command`) instead of the function it actually needs. k3d-manager's
`bin/cluster-up` sources k3d-manager's own `scripts/lib/system.sh`, which defines `_run_command`
but not `_antigravity_browser_ready` (that helper moved into foundation's `system.sh` in v1.2.0).
So the guard skips the source, and the launch branch of `_browser_launch` calls a function that
does not exist. `scripts/lib/acg/acg.sh:412` has the same dependency.

Only the **launch** branch is affected; the reuse branch returns before line 162. That is why this
is intermittent: it shows up only when no drivable Chrome is listening on the CDP port.

**Why the tests miss it:** `scripts/tests/lib/acg_cdp.bats` `setup()` always sources foundation
`system.sh` first, and every launch-branch test stubs `_antigravity_browser_ready() { :; }`. No
test loads `cdp.sh` the way a host does. The 2026-07-06 credential-test doc recorded "its
launch-branch dependency `_antigravity_browser_ready` is defined in `scripts/lib/system.sh`
(pulled in by `cdp.sh` via `../system.sh`)" — true standalone, false under a host.

A second, latent defect: `_antigravity_browser_ready` hard-codes `http://localhost:9222`, while
`_browser_launch` launches on `${PLAYWRIGHT_CDP_HOST}:${PLAYWRIGHT_CDP_PORT}`. A non-default port
would launch Chrome and then time out waiting on 9222.

## Fix spec

Give the CDP module its own readiness wait so it depends on nothing a host may lack, and honour
the same host/port the launch uses. Keep `_antigravity_browser_ready` in `system.sh` unchanged
(its own BATS tests and any external callers stay valid).

### File 1 — `scripts/lib/acg/cdp.sh`

Add this function directly above `function _browser_launch() {`:

```bash
function _cdp_browser_ready() {
  local _timeout="${1:-30}"
  local _cdp_host="${PLAYWRIGHT_CDP_HOST:-127.0.0.1}"
  local _cdp_port="${PLAYWRIGHT_CDP_PORT:-9222}"
  local _elapsed=0
  while (( _elapsed < _timeout )); do
    if _run_command --soft -- curl --max-time "${CURL_MAX_TIME:-30}" -sf "http://${_cdp_host}:${_cdp_port}/json" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    _elapsed=$(( _elapsed + 2 ))
  done
  _err "[acg] CDP browser not ready on ${_cdp_host}:${_cdp_port} after ${_timeout}s"
}
```

In `_browser_launch`, replace:

```bash
  _antigravity_browser_ready 30
  _cdp_ensure_acg_session
```

with:

```bash
  _cdp_browser_ready 30
  _cdp_ensure_acg_session
```

Add `#   _cdp_browser_ready       — wait for the CDP endpoint to answer after a launch` to the
header's "Public functions" list, under `_browser_launch`.

### File 2 — `scripts/lib/acg/acg.sh`

Replace (line ~412):

```bash
    _browser_launch
    _antigravity_browser_ready 30
```

with:

```bash
    _browser_launch
```

`_browser_launch` already waits (via `_cdp_browser_ready`) on every path that launches, and the
reuse path has a live endpoint by definition, so the second wait is redundant.

### File 3 — `scripts/tests/lib/acg_cdp.bats`

1. In every existing test, rename the stub `_antigravity_browser_ready` to `_cdp_browser_ready`
   (both the definition and the `export -f` / `unset -f` lists).
2. Add a host-load regression test that sources `cdp.sh` **without** foundation `system.sh`, with
   a host-style `_run_command` already defined, and drives the launch branch with the real
   `_cdp_browser_ready`:

```bash
@test "_browser_launch: launch branch works when a host already defines _run_command (no foundation system.sh)" {
  fake_chromium="${BATS_TEST_TMPDIR}/fake-chromium"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_chromium"
  chmod +x "$fake_chromium"
  export fake_chromium CDP_LIB
  run env -i HOME="${BATS_TEST_TMPDIR}" PATH="$PATH" fake_chromium="$fake_chromium" CDP_LIB="$CDP_LIB" bash -c '
    _probe_count=0
    _run_command() { _probe_count=$(( _probe_count + 1 )); (( _probe_count > 1 )); }
    _command_exist() { [[ "$1" == curl ]]; }
    _info() { :; }
    _err() { printf "ERR: %s\n" "$*" >&2; return 1; }
    source "$CDP_LIB"
    _cdp_port_has_listener() { return 1; }
    _cdp_stop_chrome_cdp_agent() { :; }
    _cdp_remove_stale_singleton_lock() { :; }
    _acg_resolve_cdp_browser_bin() { printf "%s" "$fake_chromium"; }
    uname() { echo Darwin; }
    sleep() { :; }
    _cdp_ensure_acg_session() { echo launched-session-check; }
    _browser_launch
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"launched-session-check"* ]]
  [[ "$output" != *"command not found"* ]]
}
```

Adjust the stub names to whatever `_browser_launch` actually calls on the launch path on
`origin/main` (read the function first) — the point is that **no stub replaces
`_cdp_browser_ready`** and foundation `system.sh` is **not** sourced.

### File 4 — docs

- `CHANGE.md` `[Unreleased]` → `### Fixed`: prose entry describing the proxy-guard defect and the
  host/port mismatch.
- `docs/api/functions.md`: add `_cdp_browser_ready` next to `_browser_launch`.
- This file: flip **Status** to FIXED with the commit SHA.

## Definition of Done

- [ ] Pre-fix proof: the new host-load test is RED against `origin/main` `cdp.sh` (paste output),
      GREEN after the fix.
- [ ] Mutation: replace `_cdp_browser_ready 30` in `_browser_launch` with
      `_antigravity_browser_ready 30` → the host-load test goes red; restore from a `$TMPDIR`
      snapshot and prove with `cmp`.
- [ ] `bats scripts/tests/lib/acg_cdp.bats scripts/tests/lib/acg.bats scripts/tests/lib/system.bats` green; paste counts.
- [ ] `shellcheck scripts/lib/acg/cdp.sh scripts/lib/acg/acg.sh` — no new findings vs `origin/main`.
- [ ] `git grep -n _antigravity_browser_ready -- scripts/lib/acg` → 0 matches.
- [ ] Changes left **unstaged**; Claude verifies and commits.

## What NOT to do

- Do NOT remove or change `_antigravity_browser_ready` in `system.sh`.
- Do NOT "fix" the guard by sourcing foundation `system.sh` unconditionally — it would override
  the host's `_run_command` and friends.
- Do NOT modify files outside the four listed. No commit, push, PR, or `--no-verify`.
- Do NOT launch a real browser or touch `~/.local/share/k3d-manager`.
