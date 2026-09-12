# Bugfix: v0.4.2 — ACG headless session gate never wired into `_browser_launch`

**Branch:** `feat/v0.4.2`
**Files:** `scripts/lib/acg/cdp.sh`

---

## Problem

`make up` (via consumer `bin/cluster-up` → `acg-credential-test` → `playwright/acg_credentials.js`)
does not automatically sign in to Pluralsight, click the sandbox, or create the AWS env. The
provisioning run reaches `aws cloudformation deploy` with stale/absent credentials and fails:

```
aws command failed (255): aws cloudformation deploy ... --stack-name k3d-manager-cluster ...
An error occurred (InvalidClientTokenId) ... The security token included in the request is invalid.
```

**Root cause:** `_browser_launch` (`cdp.sh:66`) launches a *dedicated* Chrome CDP profile
(`~/.local/share/k3d-manager/profile`) with `--password-store=basic` (`cdp.sh:86`). That profile is
neither signed into Pluralsight nor holds a saved password. The only sign-in on the extraction path,
`handleSignIn` (`playwright/lib/sandbox.js:94-97`), fills **no** password — it clicks the field and
waits for Google Password Manager autofill, which cannot fire in a `--password-store=basic` dedicated
profile. Sign-in silently no-ops → `startSandbox` never sees an authenticated page → no sandbox, no
AWS env → CloudFormation runs on stale creds.

The v0.4.1 headless-login gate that *does* fill username+password from Keychain
(`_cdp_ensure_acg_session` → `acg_session_check.js` → `pluralsight_login.loginWithPage`) is **defined
but never called** in any production path — only a consumer BATS stub references it.

---

## Reproduction

1. Ensure the CDP Chrome profile is signed out of Pluralsight (or use a fresh
   `~/.local/share/k3d-manager/profile`).
2. In a consumer (k3d-manager): `CLUSTER_PROVIDER=k3s-aws make up`.
3. **Expected:** the tool signs into Pluralsight headlessly (Keychain `k3dm-acg-pluralsight`
   username/password), starts the AWS sandbox, extracts fresh creds, then deploys CloudFormation.
4. **Actual:** no sign-in occurs; CloudFormation deploy fails with `InvalidClientTokenId` (exit 255).

---

## Fix

### Change 1 — `scripts/lib/acg/cdp.sh`: call `_cdp_ensure_acg_session` on both `_browser_launch` paths

Make `_browser_launch` guarantee an authenticated Pluralsight session, not just a running CDP Chrome.
Run the gate whether Chrome was already up or freshly launched. The gate already honors
`K3DM_ACG_SKIP_SESSION_CHECK=1` (opt-out) and fast-fails under `K3DM_NONINTERACTIVE=1` / no-TTY.

**Exact old block (`cdp.sh`, `_browser_launch`, lines 66-101):**

```bash
function _browser_launch() {
  local _cdp_host="${PLAYWRIGHT_CDP_HOST:-127.0.0.1}"
  local _cdp_port="${PLAYWRIGHT_CDP_PORT:-9222}"
  if ! _command_exist curl; then
    _err "curl is required for Antigravity browser probe — install curl and retry"
  fi
  if _run_command --soft -- curl -sf "http://${_cdp_host}:${_cdp_port}/json" >/dev/null 2>&1; then
    return 0
  fi
  _cdp_stop_chrome_cdp_agent
  _cdp_remove_stale_singleton_lock
  _info "Chrome not running — launching with --remote-debugging-port=${_cdp_port}..."
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/profile}"
  if [[ "$(uname)" == "Darwin" ]]; then
    local _chrome_app_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [[ -x "${_chrome_app_bin}" ]]; then
      local _chrome_cdp_log="${HOME}/.local/share/k3d-manager/chrome-cdp.log"
      mkdir -p "$(dirname "${_chrome_cdp_log}")"
      "${_chrome_app_bin}" \
        --remote-debugging-port="${_cdp_port}" \
        --password-store=basic \
        --user-data-dir="${_cdp_profile_dir}" \
        --no-first-run \
        --no-default-browser-check \
        >>"${_chrome_cdp_log}" 2>&1 &
    else
      open -a "Google Chrome" --args \
        --remote-debugging-port="${_cdp_port}" \
        --password-store=basic \
        --user-data-dir="${_cdp_profile_dir}"
    fi
  else
    _err "[acg] _browser_launch is macOS-only — $(uname) is not supported"
  fi
  _antigravity_browser_ready 30
}
```

**Exact new block:**

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
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/profile}"
  if [[ "$(uname)" == "Darwin" ]]; then
    local _chrome_app_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [[ -x "${_chrome_app_bin}" ]]; then
      local _chrome_cdp_log="${HOME}/.local/share/k3d-manager/chrome-cdp.log"
      mkdir -p "$(dirname "${_chrome_cdp_log}")"
      "${_chrome_app_bin}" \
        --remote-debugging-port="${_cdp_port}" \
        --password-store=basic \
        --user-data-dir="${_cdp_profile_dir}" \
        --no-first-run \
        --no-default-browser-check \
        >>"${_chrome_cdp_log}" 2>&1 &
    else
      open -a "Google Chrome" --args \
        --remote-debugging-port="${_cdp_port}" \
        --password-store=basic \
        --user-data-dir="${_cdp_profile_dir}"
    fi
  else
    _err "[acg] _browser_launch is macOS-only — $(uname) is not supported"
  fi
  _antigravity_browser_ready 30
  _cdp_ensure_acg_session
}
```

**Notes for the implementer:**
- `_cdp_ensure_acg_session` is defined immediately below `_browser_launch` in the same file, so no
  ordering/source changes are needed.
- On the already-running path, `return $?` propagates the gate's exit code (non-zero =
  `ACG_SESSION_EXPIRED` / MFA / login failure) so the caller fast-fails.
- On the launch path, the trailing `_cdp_ensure_acg_session` is the function's last command, so its
  exit code becomes `_browser_launch`'s return under `set -euo pipefail`.
- Do **not** touch `playwright/lib/sandbox.js`. `handleSignIn` correctly early-returns once the gate
  has authenticated the session; it stays as a fallback for interactive/manual use.
- Do **not** change the `--password-store=basic` flag or the profile dir — the gate fills credentials
  programmatically, so autofill is no longer relied upon.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/cdp.sh` | `_browser_launch` calls `_cdp_ensure_acg_session` on both the already-running and freshly-launched paths |
| `scripts/tests/lib/acg_cdp.bats` (or existing cdp BATS) | Add a case asserting `_browser_launch` invokes `_cdp_ensure_acg_session`; add a case with `K3DM_ACG_SKIP_SESSION_CHECK=1` asserting it does not |

---

## Rules

- `shellcheck -S warning scripts/lib/acg/cdp.sh` — zero new warnings
- BATS: run with clean env — `env -i HOME="$HOME" PATH=... bash --norc --noprofile -c 'bats scripts/tests/lib/'`
- `npm run check` and `npm test` in `scripts/lib/acg/` must stay green (no JS changed, but confirm)
- No other files touched

---

## Definition of Done

- [ ] `_browser_launch` calls `_cdp_ensure_acg_session` on both the already-running and launch paths
- [ ] Gate exit code propagates so a failed/expired session aborts provisioning (fast-fail preserved)
- [ ] `K3DM_ACG_SKIP_SESSION_CHECK=1` still bypasses the check end-to-end
- [ ] `shellcheck -S warning scripts/lib/acg/cdp.sh` clean
- [ ] BATS green (clean env); new cases cover both wired and skip paths
- [ ] `CHANGE.md` `[Unreleased]` gets a `### Fixed` entry for this wiring bug (avoid the v0.4.0/v0.4.1 changelog-drift repeat)
- [ ] Committed and pushed to `feat/v0.4.2`
- [ ] memory-bank updated with commit SHA and task status
- [ ] Follow-up noted: after v0.4.2 tag, subtree-pull into k3d-manager and re-run the live smoke

**Commit message (exact):**
```
fix(acg): wire _cdp_ensure_acg_session into _browser_launch so make up signs in headlessly
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the listed targets (`cdp.sh` + its BATS)
- Do NOT edit `playwright/lib/sandbox.js`, `acg_credentials.js`, or `acg_session_check.js`
- Do NOT commit to `main` — work on `feat/v0.4.2`
- Do NOT edit the k3d-manager `scripts/lib/foundation/` copy — this is upstream-first; the consumer
  picks it up via subtree pull after the v0.4.2 tag
