# Bug: gcp_login crashes with EOFError on stdin when using --no-launch-browser

**Branch:** `k3d-manager-v1.2.0`
**Work repo:** `wilddog64/lib-acg` at `/Users/cliang/src/gitrepo/personal/lib-acg/`
**File:** `scripts/plugins/gcp.sh`
**Supersedes:** `docs/bugs/2026-04-25-gcp-oauth-tab-timeout-macos.md` (first attempt)

## Root Cause

The previous fix used `gcloud auth login --no-launch-browser` to avoid the CDP tab-wait
timeout. This was wrong. With `--no-launch-browser`, gcloud:
1. Prints the OAuth URL to stderr
2. Waits for the user to complete OAuth in a browser
3. Prompts for a verification code on stdin: "Once finished, enter the verification code"
4. The `redirect_uri` is `https://sdk.cloud.google.com/authcode.html` (not localhost)

When run in background with `>"${url_file}" 2>&1 &`, stdin is EOF. gcloud immediately
crashes:
```
ERROR: gcloud crashed (EOFError): EOF when reading a line
```

`gcp_login.js` then waits for a `*localhost*` redirect that never comes (the flow uses
`sdk.cloud.google.com` instead), causing a second timeout.

## Fix

Use `gcloud auth login` (without `--no-launch-browser`) but intercept its browser-open
call by injecting a fake `open` / `xdg-open` at the front of PATH. This preserves the
localhost-redirect flow where gcloud handles the auth code automatically:

1. gcloud starts a local server on a random port
2. Calls `open <oauth_url>` — our fake `open` intercepts it
3. Fake `open` runs `gcp_login.js` with `GCP_AUTH_URL=<oauth_url>`
4. `gcp_login.js` navigates CDP browser to the URL, completes OAuth
5. Browser redirects to `http://localhost:<port>/?code=...`
6. `gcp_login.js` detects `*localhost*` redirect and exits 0
7. gcloud's local server captures the auth code and stores credentials

No verification code needed. No stdin interaction required.

---

## Before You Start

1. `git pull origin k3d-manager-v1.2.0` in the k3d-manager repo.
2. Read this spec in full before touching any file.
3. Read the current `scripts/plugins/gcp.sh` in lib-acg on `feat/phase5-ci-setup`.

**Work repo:** `wilddog64/lib-acg` at `/Users/cliang/src/gitrepo/personal/lib-acg/`
**Branch (lib-acg):** `feat/phase5-ci-setup` (already exists)

**k3d-manager is read-only for this task** — do NOT commit anything to k3d-manager.

---

## File: `scripts/plugins/gcp.sh` — two changes

### Change 1: revert `--no-launch-browser` from `_gcp_capture_auth_url`

**Old:**
```bash
  gcloud auth login --no-launch-browser --account "${account}" >"${url_file}" 2>&1 &
```

**New:**
```bash
  gcloud auth login --account "${account}" >"${url_file}" 2>&1 &
```

### Change 2: replace URL-capture body of `_gcp_perform_login_auth` with fake-open approach

**Old (the body after the node/playwright guard):**
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

**New:**
```bash
  # Inject fake browser-open commands so gcloud's OAuth URL is routed into the
  # CDP Chrome session instead of the system default browser.
  # macOS: gcloud calls `open <url>`; Linux: gcloud calls `xdg-open <url>` or $BROWSER.
  local _open_dir
  _open_dir=$(mktemp -d)
  cat > "${_open_dir}/browser" <<INTERCEPT
#!/usr/bin/env bash
exec env GCP_AUTH_URL="\$1" GCP_USERNAME="${account}" PLAYWRIGHT_CDP_HOST="${PLAYWRIGHT_CDP_HOST}" PLAYWRIGHT_CDP_PORT="${PLAYWRIGHT_CDP_PORT}" node "${playwright_dir}/gcp_login.js" "${account}"
INTERCEPT
  chmod +x "${_open_dir}/browser"
  ln -s "${_open_dir}/browser" "${_open_dir}/open"
  ln -s "${_open_dir}/browser" "${_open_dir}/xdg-open"

  PATH="${_open_dir}:${PATH}" BROWSER="${_open_dir}/browser" \
    gcloud auth login --account "${account}"
  local exit_code=$?
  rm -rf "${_open_dir}"
  return "${exit_code}"
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

- [ ] `_gcp_capture_auth_url` uses `gcloud auth login --account` (no `--no-launch-browser`)
- [ ] `_gcp_perform_login_auth` uses fake-open approach (no URL-capture, no pgrep, no background gcloud)
- [ ] `shellcheck -S warning scripts/plugins/gcp.sh` passes with zero warnings
- [ ] Committed to `feat/phase5-ci-setup` in lib-acg with exact message:
      `fix(gcp-login): intercept gcloud browser-open via fake PATH entry instead of --no-launch-browser`
- [ ] Pushed to `origin/feat/phase5-ci-setup`
- [ ] Update k3d-manager memory-bank with SHA and fix status COMPLETE
- [ ] Report back: SHA + memory-bank lines updated
