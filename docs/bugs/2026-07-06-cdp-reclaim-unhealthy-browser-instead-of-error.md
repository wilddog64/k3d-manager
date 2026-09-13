# Bugfix: v0.4.2 (follow-up) — reuse a healthy CDP browser; reclaim a stale/zombie one instead of erroring

**Branch:** `feat/v0.4.2`
**Files:** `scripts/lib/acg/cdp.sh`

> Fifth bug in the v0.4.2 ACG headless-gate line, after
> `2026-07-06-acg-session-gate-not-wired-into-browser-launch.md` (`96bea46`),
> `2026-07-06-acg-session-gate-not-wired-into-credential-test.md` (`36c3bb1`),
> `2026-07-06-cdp-use-playwright-managed-chromium.md` (`e136f55`), and
> `2026-07-06-credential-test-launch-and-browser-identity-guard.md` (`2918d5c`).
> Bug #4 added a hard `_err` guard on the `:9222` reuse branch keyed on **profile identity**
> (`_cdp_profile_in_use`). This spec replaces that guard with a **connectivity health check +
> port reclaim**, because profile identity is the wrong signal and a hard error is the wrong
> response.

---

## Problem

After Bug #4, `_browser_launch`'s reuse branch does: `curl :9222` ok → if the running Chrome is
**not** on the `pw-profile` dir, `_err` and stop. Two failures follow from this:

**Problem A — a healthy managed browser can still be undriveable (zombie), yet the guard adopts it.**
When the operator manually closes the CDP window, the Chrome-for-Testing **process** frequently
lingers, still bound to `:9222`, still using `pw-profile`. The profile check passes, so
`_browser_launch` adopts it and calls `_cdp_ensure_acg_session`, which `connectOverCDP`s and dies:

```
ERROR: browserType.connectOverCDP: Protocol error (Browser.setDownloadBehavior):
  Browser context management is not supported.
```

Proven live this session — same binary, same version, same profile:

| Browser on `:9222` | `connectOverCDP` |
|---|---|
| lingering/zombie CFT (PID 20506), `pw-profile`, `Chrome/148.0.7778.96` | **FAIL** `setDownloadBehavior` |
| freshly launched CFT (PID 34701), `pw-profile`, `Chrome/148.0.7778.96` | **OK** `contexts=1` |

The `setDownloadBehavior` error is **not** version drift here (Playwright 1.60.0 ↔ Chromium 148 =
`chromium-1223` match) — it is a stale browser-context state in a half-closed process. Profile
identity cannot detect it; only actually connecting can.

**Problem B — the guard errors out instead of recovering.**
For a genuinely stale/mismatched browser (e.g. the pre-`e136f55` system Chrome on the old
`profile` dir that squatted `:9222` earlier this session), Bug #4 prints a "quit that browser and
re-run" message and exits 1, forcing the operator to hunt the PID and `kill` it by hand every cold
start. The tool owns the `:9222` convention; it should reclaim the port itself.

**Root cause:** the reuse branch decides adopt-vs-reject on **profile name**, then **hard-errors**
on mismatch. The correct signal is "can Playwright actually drive this browser?" and the correct
response to "no" is "reclaim the port and relaunch the managed browser," not an error.

---

## Reproduction

1. `make credential-test PROVIDER=aws` (launches managed CFT on `:9222`).
2. Manually close the CFT window; confirm the process still holds `:9222`
   (`lsof -nP -iTCP:9222 -sTCP:LISTEN`).
3. `make credential-test PROVIDER=aws` again.
4. **Expected:** the tool detects the browser is undriveable, reclaims `:9222`, relaunches a fresh
   managed CFT, signs in headlessly, extracts creds.
5. **Actual (post-Bug #4):** profile check passes, `connectOverCDP` fails at
   `setDownloadBehavior: Browser context management is not supported` (exit 1).

---

## Fix

Decision (operator, this session): **Always reclaim `:9222`.** Reuse the existing browser when
Playwright can drive it; otherwise terminate whatever holds the port and relaunch the managed
Chromium. Never hard-error on the reuse branch.

The connectOverCDP health probe **becomes** the anti-drift protection: a version-drifted system
Chrome fails the probe (that failure *is* the drift symptom), so it is reclaimed and replaced by
the managed CFT — strictly better than Bug #4's profile-name guess. Verified this session that
`browser.close()` over `connectOverCDP` **disconnects without killing** the browser, so the probe
is non-destructive to a healthy session (PID 34701 survived the probe and `:9222` kept answering);
the subsequent `_cdp_ensure_acg_session` reconnects cleanly.

### Change 1 — `scripts/lib/acg/cdp.sh`: add two helpers

Insert **after** `_cdp_remove_stale_singleton_lock` (its closing `}` is line 64) and **before** the
blank line preceding `function _browser_launch()` (line 66). Add exactly:

```bash
function _cdp_connectable() {
  local _cdp_host="${PLAYWRIGHT_CDP_HOST:-127.0.0.1}"
  local _cdp_port="${PLAYWRIGHT_CDP_PORT:-9222}"
  if ! _command_exist node; then
    return 1
  fi
  if [[ ! -d "${_LIB_ACG_ROOT}/node_modules/playwright" ]]; then
    return 1
  fi
  CDP_HOST="${_cdp_host}" CDP_PORT="${_cdp_port}" \
  NODE_PATH="${_LIB_ACG_ROOT}/node_modules" \
    node -e 'const{chromium}=require("playwright");chromium.connectOverCDP(`http://${process.env.CDP_HOST}:${process.env.CDP_PORT}`,{timeout:10000}).then(b=>b.close()).then(()=>process.exit(0)).catch(()=>process.exit(1));' >/dev/null 2>&1
}

function _cdp_kill_port_listener() {
  local _cdp_port="${PLAYWRIGHT_CDP_PORT:-9222}"
  if ! _command_exist lsof; then
    _warn "[acg] lsof unavailable — cannot reclaim :${_cdp_port} automatically; quit the browser holding it and re-run"
    return 0
  fi
  local _pids
  _pids="$(lsof -nP -iTCP:"${_cdp_port}" -sTCP:LISTEN -t 2>/dev/null || true)"
  if [[ -z "${_pids}" ]]; then
    return 0
  fi
  _info "[acg] Reclaiming :${_cdp_port} — terminating the CDP browser holding it (pid(s): ${_pids//$'\n'/ })"
  # shellcheck disable=SC2086
  kill ${_pids} 2>/dev/null || true
  local _w=0
  while lsof -nP -iTCP:"${_cdp_port}" -sTCP:LISTEN -t >/dev/null 2>&1 && [[ ${_w} -lt 8 ]]; do
    sleep 1
    _w=$((_w + 1))
  done
  if lsof -nP -iTCP:"${_cdp_port}" -sTCP:LISTEN -t >/dev/null 2>&1; then
    _pids="$(lsof -nP -iTCP:"${_cdp_port}" -sTCP:LISTEN -t 2>/dev/null || true)"
    if [[ -n "${_pids}" ]]; then
      # shellcheck disable=SC2086
      kill -9 ${_pids} 2>/dev/null || true
      sleep 1
    fi
  fi
}
```

**Notes for the implementer:**
- The `node -e` argument is **single-quoted** in bash, so the backtick template literal and
  `${process.env.…}` are passed to node verbatim (bash does not interpret them). Do not switch to
  double quotes.
- `_warn`, `_info`, `_command_exist`, and `${_LIB_ACG_ROOT}` are already defined/used elsewhere in
  this file — reuse them, do not redefine.
- The two `# shellcheck disable=SC2086` directives are required: `${_pids}` is intentionally
  unquoted so multiple space/newline-separated PIDs word-split into separate `kill` args. These are
  directives, not narrative comments.

### Change 2 — `scripts/lib/acg/cdp.sh`: rewrite the `_browser_launch` reuse branch

Replace the Bug #4 profile-identity `_err` guard with a health-check + reclaim.

**Exact old block (`cdp.sh`, lines 73–79):**

```bash
  if _run_command --soft -- curl -sf "http://${_cdp_host}:${_cdp_port}/json" >/dev/null 2>&1; then
    if ! _cdp_profile_in_use; then
      _err "[acg] A browser is already listening on :${_cdp_port} but it is not the Playwright-managed Chromium (expected --user-data-dir=${_cdp_profile_dir}). Quit that browser — a stale system Chrome or CDP agent — and re-run. Connecting to a mismatched Chrome breaks CDP: 'Browser.setDownloadBehavior: Browser context management is not supported'."
    fi
    _cdp_ensure_acg_session
    return $?
  fi
```

**Exact new block:**

```bash
  if _run_command --soft -- curl -sf "http://${_cdp_host}:${_cdp_port}/json" >/dev/null 2>&1; then
    if _cdp_connectable; then
      _info "[acg] Reusing existing CDP browser on :${_cdp_port}"
      _cdp_ensure_acg_session
      return $?
    fi
    _info "[acg] A browser is on :${_cdp_port} but Playwright cannot drive it (stale/zombie or version-mismatched) — reclaiming the port and relaunching the managed Chromium."
    _cdp_kill_port_listener
  fi
```

**Notes for the implementer:**
- After `_cdp_kill_port_listener`, control **falls through** the closing `fi` into the existing
  relaunch path (lines 80–102: `_cdp_stop_chrome_cdp_agent`, `_cdp_remove_stale_singleton_lock`,
  managed-CFT launch, `_antigravity_browser_ready 30`, `_cdp_ensure_acg_session`). Do not
  duplicate that path — just let the `if` block fall through.
- `${_cdp_profile_dir}` (line 69, hoisted in Bug #4) is still used by the launch block — leave that
  declaration untouched.
- `_cdp_profile_in_use` is **no longer called by `_browser_launch`**, but it is still used by
  `_cdp_stop_chrome_cdp_agent` and `_cdp_remove_stale_singleton_lock` — **do not delete it.**

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/cdp.sh` | Add `_cdp_connectable` (connectOverCDP health probe) + `_cdp_kill_port_listener` (reclaim `:9222`); rewrite `_browser_launch` reuse branch to reuse-if-driveable / reclaim-and-relaunch otherwise, replacing the Bug #4 `_err` profile guard |
| `CHANGE.md` | `[Unreleased] ### Fixed` entry |

---

## Rules

- `shellcheck -S warning scripts/lib/acg/cdp.sh` — zero new warnings (the two `SC2086` disables are intentional and scoped)
- In `scripts/lib/acg/`: `npm run check` and `npm test` (jest) stay green
- Sourcing probe: `bash -c 'source scripts/lib/acg/cdp.sh; declare -f _browser_launch _cdp_connectable _cdp_kill_port_listener'` exits 0
- No `_err` remains on the "browser already listening on :port" reuse path (it is superseded by reclaim)
- `_cdp_profile_in_use` still defined (used by the agent-stop and singleton-lock helpers)
- No files touched other than the two listed

---

## Definition of Done

- [ ] `_cdp_connectable` added: returns 0 when `connectOverCDP` to `:port` succeeds (connect + close), 1 otherwise; guards missing `node`/`playwright`
- [ ] `_cdp_kill_port_listener` added: TERM then (if still bound) KILL the `:port` listener via `lsof -t`, with a bounded wait; warns and returns 0 if `lsof` is unavailable
- [ ] `_browser_launch` reuse branch: reuse via `_cdp_ensure_acg_session` when `_cdp_connectable`, else `_cdp_kill_port_listener` and fall through to relaunch — no hard `_err`
- [ ] `_cdp_profile_in_use` retained (no longer called by `_browser_launch`)
- [ ] `shellcheck -S warning` clean on `cdp.sh`
- [ ] `npm run check` + `npm test` green in `scripts/lib/acg/`
- [ ] Sourcing probe (all three functions) exits 0
- [ ] `CHANGE.md` `[Unreleased] ### Fixed` entry added
- [ ] Committed and pushed to `feat/v0.4.2`
- [ ] lib-foundation memory-bank updated with commit SHA and task status
- [ ] **USER acceptance gate (NOT Codex — needs live browser + AWS sandbox + Keychain creds):**
      In lib-foundation: (a) with a healthy managed CFT already on `:9222`, `make credential-test
      PROVIDER=aws` reuses it and extracts creds; (b) after manually closing the CFT window so a
      zombie lingers on `:9222`, re-running reclaims the port, relaunches a fresh CFT, signs in
      headlessly, and extracts creds with no manual `kill`. Must pass before any subtree-pull.
- [ ] Follow-up (after the lib-foundation gate passes + v0.4.2 tag): subtree-pull into
      k3d-manager, then confirm `CLUSTER_PROVIDER=k3s-aws make up`.

**Commit message (exact):**
```
fix(acg): reclaim stale CDP browser and reuse healthy one instead of erroring
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/cdp.sh` and `CHANGE.md`
- Do NOT delete `_cdp_profile_in_use` — it is still used by `_cdp_stop_chrome_cdp_agent` and `_cdp_remove_stale_singleton_lock`
- Do NOT re-add a hard `_err` on the reuse branch — the operator's decision is to reclaim, not error
- Do NOT re-add a system-Chrome fallback or `open -a "Google Chrome"` — the relaunch path stays on the Playwright-managed Chromium (`e136f55`)
- Do NOT run the live `make credential-test` yourself and report it as passed — that gate is the user's to run in lib-foundation
- Do NOT commit to `main` — work on `feat/v0.4.2`
- Do NOT edit the k3d-manager `scripts/lib/foundation/` copy — upstream-first; the consumer picks it up via subtree pull after the v0.4.2 tag
