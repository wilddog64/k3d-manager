# Bugfix: v0.4.2 (follow-up) — credential-test must launch the managed browser, and `_browser_launch` must reject a foreign CDP browser

**Branch:** `feat/v0.4.2`
**Files:** `scripts/lib/acg/cdp.sh`, `scripts/lib/acg/bin/acg-credential-test`

> Fourth and final bug in the v0.4.2 ACG headless-gate line, after
> `2026-07-06-acg-session-gate-not-wired-into-browser-launch.md` (`96bea46`),
> `2026-07-06-acg-session-gate-not-wired-into-credential-test.md` (`36c3bb1`), and
> `2026-07-06-cdp-use-playwright-managed-chromium.md` (`e136f55`). Those wired the gate onto
> both paths and switched the *launched* browser to the Playwright-managed Chromium. This spec
> closes the two gaps that keep `make credential-test PROVIDER=aws` failing at
> `connectOverCDP: … Browser context management is not supported` even after `e136f55`.

---

## Problem

`e136f55` fixed only the browser that `_browser_launch` **launches**. Two paths still connect
to whatever Chrome happens to be on `:9222`:

**Problem A — `_browser_launch` adopts any live `:9222` without checking identity.**
When `:9222` already answers, `_browser_launch` calls `_cdp_ensure_acg_session` and returns
(cdp.sh:72–75). It never verifies the running browser is the managed Chromium. A stale system
Chrome (e.g. Chrome 150 left over from the pre-`e136f55` code, or the launchd CDP agent) that is
squatting on `:9222` gets adopted — reintroducing exactly the protocol drift `e136f55` removed.

**Problem B — `bin/acg-credential-test` never launches the managed browser at all.**
After `36c3bb1` it curl-guards `:9222` (erroring with "launch system Chrome" guidance if empty),
then sources `cdp.sh` and calls `_cdp_ensure_acg_session`, which only **connects** — it never
launches. So `e136f55`'s managed-Chromium launch is unreachable from the credential-test path:
if `:9222` is down it errors out, and if a foreign Chrome is up it connects to that (Problem A).

Together, `make credential-test PROVIDER=aws` connects to a version-mismatched system Chrome and
dies at:

```
ERROR: browserType.connectOverCDP: Protocol error (Browser.setDownloadBehavior):
  Browser context management is not supported.
```

**Root cause:**
1. `_browser_launch`'s reuse branch has no identity guard — it trusts any `:9222` listener.
2. `bin/acg-credential-test` bypasses `_browser_launch` entirely, so it can neither launch the
   managed browser nor benefit from the identity guard.

---

## Reproduction

1. A system Chrome (major newer than the pinned Playwright) is running on `:9222` using the old
   profile `~/.local/share/k3d-manager/profile` — e.g. a leftover from the pre-`e136f55` launcher.
2. From lib-foundation: `make credential-test PROVIDER=aws`.
3. **Expected:** the tool launches / adopts the Playwright-managed Chromium (`pw-profile`), signs
   in headlessly, extracts creds.
4. **Actual:** it connects to the stale system Chrome and dies at
   `connectOverCDP: … Browser context management is not supported` (exit 1).

---

## Fix

### Change 1 — `scripts/lib/acg/cdp.sh`: guard the reuse branch by profile identity

Before adopting a browser already on `:9222`, verify it is the Playwright-managed Chromium by
checking that a Chrome process is running against our dedicated `pw-profile` dir. The existing
`_cdp_profile_in_use` helper already does exactly this check (it matches a chrome process whose
`--user-data-dir` is the `pw-profile` path). If the profile is **not** in use, the `:9222`
listener is a foreign/stale browser — fail with a clear, actionable error instead of connecting
into the drift. Also hoist the `_cdp_profile_dir` declaration above the probe so both the guard
message and the launch block share the single definition.

**Exact old block (`cdp.sh`, lines 66–79):**

```bash
function _browser_launch() {
  local _cdp_host="${PLAYWRIGHT_CDP_HOST:-127.0.0.1}"
  local _cdp_port="${PLAYWRIGHT_CDP_PORT:-9222}"
  if ! _command_exist curl; then
    _err "curl is required for Antigravity browser probe — install curl and retry"
  fi
  if _run_command --soft -- curl -sf "http://${_cdp_host}:${_cdp_port}/json" >/dev/null 2>&1; then
    _cdp_ensure_acg_session
    return $?
  fi
  _cdp_stop_chrome_cdp_agent
  _cdp_remove_stale_singleton_lock
  _info "Chrome not running — launching with --remote-debugging-port=${_cdp_port}..."
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/pw-profile}"
```

**Exact new block:**

```bash
function _browser_launch() {
  local _cdp_host="${PLAYWRIGHT_CDP_HOST:-127.0.0.1}"
  local _cdp_port="${PLAYWRIGHT_CDP_PORT:-9222}"
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/pw-profile}"
  if ! _command_exist curl; then
    _err "curl is required for Antigravity browser probe — install curl and retry"
  fi
  if _run_command --soft -- curl -sf "http://${_cdp_host}:${_cdp_port}/json" >/dev/null 2>&1; then
    if ! _cdp_profile_in_use; then
      _err "[acg] A browser is already listening on :${_cdp_port} but it is not the Playwright-managed Chromium (expected --user-data-dir=${_cdp_profile_dir}). Quit that browser — a stale system Chrome or CDP agent — and re-run. Connecting to a mismatched Chrome breaks CDP: 'Browser.setDownloadBehavior: Browser context management is not supported'."
    fi
    _cdp_ensure_acg_session
    return $?
  fi
  _cdp_stop_chrome_cdp_agent
  _cdp_remove_stale_singleton_lock
  _info "Chrome not running — launching with --remote-debugging-port=${_cdp_port}..."
```

**Notes for the implementer:**
- The later `local _cdp_profile_dir="…pw-profile}"` line (previously the last line of the old
  block, at line 79) is **removed** — it is now declared once at the top of the function. The
  `if [[ "$(uname)" == "Darwin" ]]; then` launch block that follows still references
  `${_cdp_profile_dir}` and now resolves it from the hoisted declaration.
- Do **not** touch `_cdp_profile_in_use` — it already matches the `pw-profile` path (its default
  is `${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/pw-profile}`, updated in `e136f55`).

### Change 2 — `scripts/lib/acg/bin/acg-credential-test`: route through `_browser_launch`

Replace the system-Chrome curl-guard and the connect-only `_cdp_ensure_acg_session` call with a
single `_browser_launch`. `_browser_launch` probes `:9222`; if free it launches the managed
Chromium (via `e136f55`) and runs the gate; if a managed browser is already up it adopts and runs
the gate; if a foreign browser is up it fails with the Change 1 guard. This makes the
credential-test path self-launching and drift-proof, and drops the stale
`open -a "Google Chrome"` guidance string. Verified: sourcing `cdp.sh` standalone exposes
`_browser_launch`, and its launch-branch dependency `_antigravity_browser_ready` is defined in
`scripts/lib/system.sh` (pulled in by `cdp.sh` via `../system.sh`).

**Exact old block (`bin/acg-credential-test`, lines 6–14):**

```bash
if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
  printf 'ERROR: Chrome CDP not running on port 9222\n' >&2
  printf 'Start with: open -a "Google Chrome" --args --remote-debugging-port=9222\n' >&2
  exit 1
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/cdp.sh"
_cdp_ensure_acg_session
```

**Exact new block:**

```bash
# shellcheck source=/dev/null
source "${REPO_ROOT}/cdp.sh"
_browser_launch
```

**Notes for the implementer:**
- Do **not** remove the `REPO_ROOT="$(cd … )"` line above (line 4) or the `set -euo pipefail`
  header — only the curl-guard block and the bare `_cdp_ensure_acg_session` call are replaced.
- `_browser_launch` consumes no positional args, so the `sandbox_url="${1:?…}"` line that follows
  is unaffected.
- The `# shellcheck source=/dev/null` directive is required so shellcheck does not follow the
  sourced file. It is a directive, not a narrative comment.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/cdp.sh` | Hoist `_cdp_profile_dir`; guard the `:9222` reuse branch with `_cdp_profile_in_use` so a foreign/stale browser is rejected instead of adopted |
| `scripts/lib/acg/bin/acg-credential-test` | Replace the system-Chrome curl-guard + connect-only call with `_browser_launch` (self-launch + identity guard + gate) |
| `CHANGE.md` | `[Unreleased] ### Fixed` entry |

---

## Rules

- `shellcheck -S warning scripts/lib/acg/cdp.sh scripts/lib/acg/bin/acg-credential-test` — zero new warnings
- In `scripts/lib/acg/`: `npm run check` and `npm test` (jest) stay green
- Sourcing probe: `bash -c 'source scripts/lib/acg/cdp.sh; declare -f _browser_launch'` exits 0
- No `open -a "Google Chrome"` reference remains in `bin/acg-credential-test`
- No files touched other than the three listed

---

## Definition of Done

- [ ] `_browser_launch` declares `_cdp_profile_dir` once at the top and, in the reuse branch,
      `_err`s when `_cdp_profile_in_use` is false (foreign browser rejected)
- [ ] `bin/acg-credential-test` calls `_browser_launch` (not the bare curl-guard +
      `_cdp_ensure_acg_session`); no `open -a "Google Chrome"` string remains
- [ ] `shellcheck -S warning` clean on both shell files
- [ ] `npm run check` + `npm test` green in `scripts/lib/acg/`
- [ ] Sourcing probe exits 0
- [ ] `CHANGE.md` `[Unreleased] ### Fixed` entry added
- [ ] Committed and pushed to `feat/v0.4.2`
- [ ] lib-foundation memory-bank updated with commit SHA and task status
- [ ] **USER acceptance gate (NOT Codex — needs live browser + AWS sandbox + Keychain creds):**
      In lib-foundation, with `:9222` free (quit any stale system Chrome / CDP agent),
      `make credential-test PROVIDER=aws` launches Chrome-for-Testing, signs in headlessly, and
      extracts creds without manual login — and re-running while a foreign Chrome squats on
      `:9222` fails fast with the Change 1 guard message. Must pass before any subtree-pull.
- [ ] Follow-up (after the lib-foundation gate passes + v0.4.2 tag): subtree-pull into
      k3d-manager, then confirm `CLUSTER_PROVIDER=k3s-aws make up`.

**Commit message (exact):**
```
fix(acg): route credential-test through _browser_launch and guard CDP browser identity
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed targets
- Do NOT edit `_cdp_profile_in_use`, `acg_session_check.js`, `browser.js`, or `output.js` —
  the identity check and the launch/connect logic are reused, not re-implemented
- Do NOT re-add a system-Chrome fallback (`/Applications/Google Chrome.app` or
  `open -a "Google Chrome"`) — the credential-test guard string is being removed for the same
  anti-drift reason as `e136f55`
- Do NOT run the live `make credential-test` yourself and report it as passed — that gate is the
  user's to run in lib-foundation
- Do NOT commit to `main` — work on `feat/v0.4.2`
- Do NOT edit the k3d-manager `scripts/lib/foundation/` copy — upstream-first; the consumer picks
  it up via subtree pull after the v0.4.2 tag
