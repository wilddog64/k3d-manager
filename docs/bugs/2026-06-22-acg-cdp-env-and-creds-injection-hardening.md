# Bugfix: v0.4.0 — acg CDP env-var threading + gcp creds injection hardening

**Branch:** `feat/v0.4.0`
**Repo:** `lib-foundation`
**Files:** `scripts/lib/acg/cdp.sh`, `scripts/lib/acg/acg.sh`, `scripts/lib/acg/gcp.sh`, `scripts/lib/acg/vars.sh`, `scripts/lib/acg/playwright/lib/output.js`, `scripts/lib/acg/playwright/acg_extend.js`, `scripts/lib/acg/playwright/acg_restart.js`, `scripts/lib/acg/acg_session_check.js`

Addresses the 10 deferred Copilot findings on PR #32 (see `docs/issues/2026-06-22-copilot-pr32-review-findings.md`). All sites are imported lib-acg code; this is the hardening pass the user elected to fold into PR #32 ("fix everything now").

---

## Problem

1. **Shell injection (OWASP A03)** — `gcp_get_credentials` `source`s a temp creds file whose values are browser-extracted external input. Unescaped `$()`/backticks/etc. would execute as shell.
2. **Creds-file perms** — `output.js` passes `{mode:0o600}` to `writeFileSync`, which only applies on file *creation*; a pre-existing creds file keeps its old (looser) perms.
3. **Hard-coded CDP host/port** — `cdp.sh`, `acg.sh`, `acg_extend.js`, `acg_restart.js`, `acg_session_check.js` hard-code `localhost:9222` / `127.0.0.1:9222`, ignoring the module's own `PLAYWRIGHT_CDP_HOST` / `PLAYWRIGHT_CDP_PORT` (exported in `vars.sh`; already honored by `gcp.sh` and `output.js`).
4. **Stale path comments** — `vars.sh` header/comments still reference the old lib-acg paths (`scripts/etc/...`, `scripts/plugins/...`, `scripts/playwright/...`).

**Root cause:** verbatim import from lib-acg `7708ea31`; these were pre-existing in the standalone repo.

---

## Reproduction

- CDP override: `PLAYWRIGHT_CDP_PORT=9333 make credential-test PROVIDER=aws` still probes/launches/connects on 9222 (override ignored).
- Injection: a GCP credential value containing `$(...)` would be evaluated by `source`.

---

## Fix

### Change 1 — `scripts/lib/acg/playwright/lib/output.js`: chmod after write

**Exact old block (lines 25–28):**

```javascript
  if (credsFile) {
    fs.writeFileSync(credsFile, output, { mode: 0o600 });
    console.error(`INFO: Credentials scrubbed to secure file: ${credsFile}`);
  } else {
```

**Exact new block:**

```javascript
  if (credsFile) {
    fs.writeFileSync(credsFile, output, { mode: 0o600 });
    fs.chmodSync(credsFile, 0o600);
    console.error(`INFO: Credentials scrubbed to secure file: ${credsFile}`);
  } else {
```

---

### Change 2 — `scripts/lib/acg/gcp.sh`: parse creds file without `source`

**Exact old block (lines 101–104):**

```bash
  # Load credentials into shell memory (not stdout) and immediately scrub the file
  # shellcheck source=/dev/null
  source "${creds_tmp}"
  rm -f "${creds_tmp}"
```

**Exact new block:**

```bash
  # Parse credentials into shell memory WITHOUT executing the file. The values are
  # browser-extracted external input — sourcing would allow shell injection. Only
  # known keys are honored; values are assigned literally, never evaluated.
  local GCP_PROJECT="" GOOGLE_APPLICATION_CREDENTIALS="" GCP_USERNAME="" GCP_PASSWORD=""
  local _cred_line _cred_key _cred_val
  while IFS= read -r _cred_line || [[ -n "${_cred_line}" ]]; do
    _cred_key="${_cred_line%%=*}"
    _cred_val="${_cred_line#*=}"
    case "${_cred_key}" in
      GCP_PROJECT) GCP_PROJECT="${_cred_val}" ;;
      GOOGLE_APPLICATION_CREDENTIALS) GOOGLE_APPLICATION_CREDENTIALS="${_cred_val}" ;;
      GCP_USERNAME) GCP_USERNAME="${_cred_val}" ;;
      GCP_PASSWORD) GCP_PASSWORD="${_cred_val}" ;;
    esac
  done < "${creds_tmp}"
  rm -f "${creds_tmp}"
```

The immediately-following block (`local project="${GCP_PROJECT:-}"` …) is unchanged and now reads the literally-parsed values.

---

### Change 3 — `scripts/lib/acg/cdp.sh`: thread host/port through `_browser_launch`

**Exact old block (lines 66–99):**

```bash
function _browser_launch() {
  if ! _command_exist curl; then
    _err "curl is required for Antigravity browser probe — install curl and retry"
  fi
  if _run_command --soft -- curl -sf http://localhost:9222/json >/dev/null 2>&1; then
    return 0
  fi
  _cdp_stop_chrome_cdp_agent
  _cdp_remove_stale_singleton_lock
  _info "Chrome not running — launching with --remote-debugging-port=9222..."
  local _cdp_profile_dir="${PLAYWRIGHT_AUTH_DIR:-${HOME}/.local/share/k3d-manager/profile}"
  if [[ "$(uname)" == "Darwin" ]]; then
    local _chrome_app_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if [[ -x "${_chrome_app_bin}" ]]; then
      local _chrome_cdp_log="${HOME}/.local/share/k3d-manager/chrome-cdp.log"
      mkdir -p "$(dirname "${_chrome_cdp_log}")"
      "${_chrome_app_bin}" \
        --remote-debugging-port=9222 \
        --password-store=basic \
        --user-data-dir="${_cdp_profile_dir}" \
        --no-first-run \
        --no-default-browser-check \
        >>"${_chrome_cdp_log}" 2>&1 &
    else
      open -a "Google Chrome" --args \
        --remote-debugging-port=9222 \
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

---

### Change 4 — `scripts/lib/acg/acg.sh`: use CDP host/port in the probe

**Exact old block (lines 298–299):**

```bash
  if ! curl -sf http://localhost:9222/json >/dev/null 2>&1; then
    _info "[acg] Chrome CDP not available on port 9222 — launching Chrome..."
```

**Exact new block:**

```bash
  if ! curl -sf "http://${PLAYWRIGHT_CDP_HOST:-127.0.0.1}:${_ACG_CHROME_CDP_PORT}/json" >/dev/null 2>&1; then
    _info "[acg] Chrome CDP not available on port ${_ACG_CHROME_CDP_PORT} — launching Chrome..."
```

(`_ACG_CHROME_CDP_PORT="${PLAYWRIGHT_CDP_PORT}"` is already set at line 36; `PLAYWRIGHT_CDP_HOST` is exported from `vars.sh`.)

---

### Change 5 — `scripts/lib/acg/acg_session_check.js`: CDP URL from env

**Exact old block (line 6):**

```javascript
const CDP_URL = 'http://127.0.0.1:9222';
```

**Exact new block:**

```javascript
const CDP_HOST = process.env.PLAYWRIGHT_CDP_HOST || '127.0.0.1';
const CDP_PORT = process.env.PLAYWRIGHT_CDP_PORT || '9222';
const CDP_URL = `http://${CDP_HOST}:${CDP_PORT}`;
```

---

### Change 6 — `scripts/lib/acg/playwright/acg_restart.js`: CDP host/port from env

**Exact old block (lines 7–8):**

```javascript
const CDP_HOST = '127.0.0.1';
const CDP_PORT = '9222';
```

**Exact new block:**

```javascript
const CDP_HOST = process.env.PLAYWRIGHT_CDP_HOST || '127.0.0.1';
const CDP_PORT = process.env.PLAYWRIGHT_CDP_PORT || '9222';
```

---

### Change 7 — `scripts/lib/acg/playwright/acg_extend.js`: derive + use CDP_URL from env

**7a. Add the CDP URL constant. Exact old block (line 16):**

```javascript
const AUTH_DIR = path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'profile');
```

**Exact new block:**

```javascript
const AUTH_DIR = path.join(os.homedir(), '.local', 'share', 'k3d-manager', 'profile');

const CDP_HOST = process.env.PLAYWRIGHT_CDP_HOST || '127.0.0.1';
const CDP_PORT = process.env.PLAYWRIGHT_CDP_PORT || '9222';
const CDP_URL = `http://${CDP_HOST}:${CDP_PORT}`;
```

**7b. Use it. Exact old block (line 99):**

```javascript
      _cdpBrowser = await chromium.connectOverCDP('http://localhost:9222');
```

**Exact new block:**

```javascript
      _cdpBrowser = await chromium.connectOverCDP(CDP_URL);
```

---

### Change 8 — `scripts/lib/acg/vars.sh`: fix stale path comments

**8a. Exact old block (line 2):**

```bash
# scripts/etc/playwright/vars.sh
```

**Exact new block:**

```bash
# scripts/lib/acg/vars.sh
```

**8b. Exact old block (lines 5–6):**

```bash
# Sourced by scripts/plugins/acg.sh and scripts/plugins/gcp.sh; also read by
# scripts/playwright/*.js via argv (not by sourcing — node cannot source bash).
```

**Exact new block:**

```bash
# Sourced by scripts/lib/acg/acg.sh and scripts/lib/acg/gcp.sh; also read by
# scripts/lib/acg/playwright/*.js via argv (not by sourcing — node cannot source bash).
```

**8c. Exact old block (lines 19–20):**

```bash
# com.k3d-manager.chrome-cdp). Path must match _ACG_CHROME_CDP_AUTH_DIR in
# scripts/plugins/acg.sh.
```

**Exact new block:**

```bash
# com.k3d-manager.chrome-cdp). Path must match _ACG_CHROME_CDP_AUTH_DIR in
# scripts/lib/acg/acg.sh.
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/lib/output.js` | `chmodSync` after write to enforce 0600 on existing files |
| `scripts/lib/acg/gcp.sh` | replace `source` of creds file with allowlisted no-eval parser |
| `scripts/lib/acg/cdp.sh` | `_browser_launch` honors `PLAYWRIGHT_CDP_HOST`/`PORT` (probe, log, launch, fallback) |
| `scripts/lib/acg/acg.sh` | CDP probe uses `PLAYWRIGHT_CDP_HOST` + `_ACG_CHROME_CDP_PORT` |
| `scripts/lib/acg/acg_session_check.js` | CDP URL from env |
| `scripts/lib/acg/playwright/acg_restart.js` | CDP host/port from env |
| `scripts/lib/acg/playwright/acg_extend.js` | derive + use `CDP_URL` from env |
| `scripts/lib/acg/vars.sh` | update stale path comments |

---

## Rules

- `shellcheck -S warning` clean on `cdp.sh`, `acg.sh`, `gcp.sh`, `vars.sh`, and `bin/acg-credential-test`, `bin/acg-extend-test`.
- `cd scripts/lib/acg && npm run check` (node `--check`) passes on all JS.
- `cd scripts/lib/acg && npm test` (Jest) — 10/10 still pass.
- Do NOT change default behavior: with no env override, host stays `127.0.0.1` and port `9222`.
- Do NOT touch any file outside the table. Do NOT refactor surrounding code.
- `acg_credentials.js` was NOT flagged by Copilot — leave it; if it also hard-codes CDP, file a separate note, do not fix here.

---

## Definition of Done

- [ ] All 8 changes applied exactly as written.
- [ ] `npm run check` + `npm test` (10/10) green in `scripts/lib/acg`.
- [ ] `shellcheck -S warning` clean on the 4 shell files + 2 bin scripts.
- [ ] Default (no override) values unchanged: `127.0.0.1:9222`.
- [ ] Committed and pushed to `feat/v0.4.0`.
- [ ] memory-bank updated with the commit SHA and status.

**Commit message (exact):**

```
fix(acg): thread CDP host/port through env + parse gcp creds without source (Copilot PR #32)
```

---

## What NOT to Do

- Do NOT create a PR (PR #32 already exists; this commits onto its branch).
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file outside the Files-Changed table.
- Do NOT commit to `main` — work on `feat/v0.4.0`.
- Do NOT change the `bin/` layout or the Makefile `cd` behavior (that is the live-flow fix already landed in `cf3ad7a`).
