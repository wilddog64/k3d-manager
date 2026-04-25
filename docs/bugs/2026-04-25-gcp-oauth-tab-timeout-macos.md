# Bug: gcp_login OAuth tab timeout on macOS

**Branch:** `k3d-manager-v1.2.0`
**Work repo:** `wilddog64/lib-acg` at `/Users/cliang/src/gitrepo/personal/lib-acg/`
**File:** `scripts/plugins/gcp.sh`

## Root Cause

`_gcp_perform_login_auth` has two branches: Linux and macOS. The macOS branch runs
`gcloud auth login --account "${account}" &` in the background, then waits in `gcp_login.js`
for a new Google OAuth tab to appear in the Chrome CDP session (`context.waitForEvent('page')`).

`gcloud auth login` opens the OAuth URL in the system default browser, not in the CDP-managed
Chrome instance (launched on port 9222 for Playwright automation). The CDP browser never
receives the tab, so the 30s `waitForEvent` times out:

```
INFO: Waiting for Google OAuth tab (up to 30s)...
ERROR: browserContext.waitForEvent: Timeout 30000ms exceeded while waiting for event "page"
```

The Linux branch already solves this correctly: `_gcp_capture_auth_url` captures the URL
from gcloud's stderr/stdout, then passes it as `GCP_AUTH_URL` to `gcp_login.js`, which
navigates the CDP browser directly to it. The macOS branch skips this.

## Fix

Remove the macOS/Linux distinction. Use the URL-capture path (`_gcp_capture_auth_url`) on
both platforms. Add `--no-launch-browser` to `_gcp_capture_auth_url` to prevent gcloud from
opening the system default browser at all (it would conflict with the CDP navigation).

---

## Before You Start

1. `git pull origin k3d-manager-v1.2.0` in the k3d-manager repo.
2. Read this spec in full before touching any file.
3. Read `lib-acg/scripts/plugins/gcp.sh` — understand `_gcp_capture_auth_url` and
   `_gcp_perform_login_auth` before changing anything.

**Work repo:** `wilddog64/lib-acg` at `/Users/cliang/src/gitrepo/personal/lib-acg/`
**Branch (lib-acg):** `feat/phase5-ci-setup` (already exists from Phase 5 — do NOT create a new branch)

**k3d-manager is read-only for this task** — do NOT commit anything to k3d-manager.

---

## File: `scripts/plugins/gcp.sh` — change `_gcp_capture_auth_url` and `_gcp_perform_login_auth`

### Change 1: add `--no-launch-browser` to `_gcp_capture_auth_url`

**Old:**
```bash
function _gcp_capture_auth_url() {
  local account="$1"
  local url_file="$2"
  local url=""
  local _i

  gcloud auth login --account "${account}" >"${url_file}" 2>&1 &
```

**New:**
```bash
function _gcp_capture_auth_url() {
  local account="$1"
  local url_file="$2"
  local url=""
  local _i

  gcloud auth login --no-launch-browser --account "${account}" >"${url_file}" 2>&1 &
```

### Change 2: remove the macOS/Linux split in `_gcp_perform_login_auth`

**Old (entire function body after node/playwright guard):**
```bash
  if [[ "$(uname)" == "Linux" ]]; then
    local _gcloud_url_file
    _gcloud_url_file=$(mktemp)
    local _auth_url
    _auth_url=$(_gcp_capture_auth_url "${account}" "${_gcloud_url_file}")
    local gcloud_pid
    gcloud_pid=$(pgrep -n -f "gcloud auth login --account ${account}")
    
    rm -f "${_gcloud_url_file}"
    if [[ -z "${_auth_url}" ]]; then
      _err "[gcp] Could not capture gcloud OAuth URL — manual gcloud auth login required"
    fi
    GCP_USERNAME="${account}" \
    GCP_AUTH_URL="${_auth_url}" \
    PLAYWRIGHT_CDP_HOST="${PLAYWRIGHT_CDP_HOST}" \
    PLAYWRIGHT_CDP_PORT="${PLAYWRIGHT_CDP_PORT}" \
    node "${playwright_dir}/gcp_login.js" "${account}"
    if [[ -n "$gcloud_pid" ]]; then
      wait "${gcloud_pid}"
    fi
  else
    # macOS: gcloud opens the OAuth tab in this Chrome session — Playwright waits for it
    gcloud auth login --account "${account}" &
    local gcloud_pid=$!
    GCP_USERNAME="${account}" \
    PLAYWRIGHT_CDP_HOST="${PLAYWRIGHT_CDP_HOST}" \
    PLAYWRIGHT_CDP_PORT="${PLAYWRIGHT_CDP_PORT}" \
    node "${playwright_dir}/gcp_login.js" "${account}"
    wait "${gcloud_pid}"
  fi
```

**New (single path for both macOS and Linux):**
```bash
  local _gcloud_url_file
  _gcloud_url_file=$(mktemp)
  local _auth_url
  _auth_url=$(_gcp_capture_auth_url "${account}" "${_gcloud_url_file}")
  local gcloud_pid
  gcloud_pid=$(pgrep -n -f "gcloud auth login --no-launch-browser --account ${account}")

  rm -f "${_gcloud_url_file}"
  if [[ -z "${_auth_url}" ]]; then
    _err "[gcp] Could not capture gcloud OAuth URL — manual gcloud auth login required"
  fi
  GCP_USERNAME="${account}" \
  GCP_AUTH_URL="${_auth_url}" \
  PLAYWRIGHT_CDP_HOST="${PLAYWRIGHT_CDP_HOST}" \
  PLAYWRIGHT_CDP_PORT="${PLAYWRIGHT_CDP_PORT}" \
  node "${playwright_dir}/gcp_login.js" "${account}"
  if [[ -n "$gcloud_pid" ]]; then
    wait "${gcloud_pid}"
  fi
```

---

## Rules

1. `shellcheck -S warning scripts/plugins/gcp.sh` — zero warnings.
2. Do NOT run `--no-verify`.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `scripts/plugins/gcp.sh`.
- Do NOT modify anything under `scripts/lib/foundation/`.
- Do NOT commit to `main` in lib-acg.
- Do NOT commit anything to k3d-manager.

---

## Definition of Done

- [ ] `scripts/plugins/gcp.sh` — `_gcp_capture_auth_url` uses `--no-launch-browser`
- [ ] `scripts/plugins/gcp.sh` — `_gcp_perform_login_auth` has no macOS/Linux split; single URL-capture path
- [ ] `shellcheck -S warning scripts/plugins/gcp.sh` passes with zero warnings
- [ ] Committed to `feat/phase5-ci-setup` in lib-acg with exact message:
      `fix(gcp-login): use URL-capture path on macOS to avoid CDP tab wait timeout`
- [ ] Pushed to `origin/feat/phase5-ci-setup` — do NOT report done until push succeeds
- [ ] Update `k3d-manager/memory-bank/activeContext.md` and `k3d-manager/memory-bank/progress.md`
      with the lib-acg commit SHA and this fix status COMPLETE
- [ ] Report back: lib-acg commit SHA + paste the memory-bank lines updated
