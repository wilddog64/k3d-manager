# Bug: gcp_login OAuth tab never appears on Linux headless — gcloud can't open browser

**Branch:** `k3d-manager-v1.1.0`
**Files:** `scripts/plugins/gcp.sh`, `scripts/playwright/gcp_login.js`

---

## Problem

On the ACG sandbox (Linux, no `$DISPLAY`), `gcloud auth login` cannot open a browser window.
It prints the OAuth URL to its output and starts a local HTTP server waiting for the callback.

`gcp_login.js` waits for a Chrome tab matching `accounts.google.com` to appear in the CDP session —
a tab that gcloud is supposed to open. On Linux headless, that tab never appears.
After 30 seconds `gcp_login.js` times out, the `gcp_login` shell function returns non-zero,
and `make up` fails with `Error 1`.

On macOS, gcloud opens Chrome directly via the system default browser — that flow is already working.
**Do not change the macOS branch.**

---

## Root Cause

`gcp.sh` `gcp_login` (lines 177–186):
```bash
    # Run gcloud in background (blocks until OAuth callback); Playwright automates the browser
    gcloud auth login --account "${account}" &
    local gcloud_pid=$!
    GCP_USERNAME="${account}" \
    PLAYWRIGHT_CDP_HOST="${PLAYWRIGHT_CDP_HOST}" \
    PLAYWRIGHT_CDP_PORT="${PLAYWRIGHT_CDP_PORT}" \
    node "${playwright_dir}/gcp_login.js" "${account}"
    wait "${gcloud_pid}"
```

`gcloud auth login` on Linux headless prints the OAuth URL to output and waits for a localhost
callback. It never opens Chrome. `gcp_login.js` waits for a Chrome tab that never arrives.

---

## Fix

### Change 1 — `scripts/plugins/gcp.sh` — split gcp_login by OS; capture URL on Linux

**Old** (lines 177–186, inside the `else` branch of the node/playwright check):
```bash
  else
    # Run gcloud in background (blocks until OAuth callback); Playwright automates the browser
    gcloud auth login --account "${account}" &
    local gcloud_pid=$!
    GCP_USERNAME="${account}" \
    PLAYWRIGHT_CDP_HOST="${PLAYWRIGHT_CDP_HOST}" \
    PLAYWRIGHT_CDP_PORT="${PLAYWRIGHT_CDP_PORT}" \
    node "${playwright_dir}/gcp_login.js" "${account}"
    wait "${gcloud_pid}"
  fi
```

**New**:
```bash
  else
    if [[ "$(uname)" == "Linux" ]]; then
      local _gcloud_url_file
      _gcloud_url_file=$(mktemp)
      gcloud auth login --account "${account}" >"${_gcloud_url_file}" 2>&1 &
      local gcloud_pid=$!
      local _auth_url=""
      local _i
      for _i in $(seq 1 10); do
        _auth_url=$(grep -oE 'https://accounts\.google\.com[^[:space:]]+' "${_gcloud_url_file}" 2>/dev/null | head -1 || true)
        if [[ -n "${_auth_url}" ]]; then
          break
        fi
        sleep 1
      done
      rm -f "${_gcloud_url_file}"
      if [[ -z "${_auth_url}" ]]; then
        _err "[gcp] Could not capture gcloud OAuth URL — manual gcloud auth login required"
      fi
      GCP_USERNAME="${account}" \
      GCP_AUTH_URL="${_auth_url}" \
      PLAYWRIGHT_CDP_HOST="${PLAYWRIGHT_CDP_HOST}" \
      PLAYWRIGHT_CDP_PORT="${PLAYWRIGHT_CDP_PORT}" \
      node "${playwright_dir}/gcp_login.js" "${account}"
      wait "${gcloud_pid}"
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
  fi
```

---

### Change 2 — `scripts/playwright/gcp_login.js` — add GCP_AUTH_URL constant and use it on Linux

**Old** (lines 26–27, constants block):
```js
const GCP_ACCOUNT = process.argv[2] || process.env.GCP_USERNAME || '';
const GCP_PASSWORD = process.env.GCP_PASSWORD || '';
```

**New**:
```js
const GCP_ACCOUNT = process.argv[2] || process.env.GCP_USERNAME || '';
const GCP_PASSWORD = process.env.GCP_PASSWORD || '';
const GCP_AUTH_URL = process.env.GCP_AUTH_URL || '';
```

**Old** (lines 37–62, inside `handleGcpOAuthFlow` — after the logout step, before step 1):
```js
  // Check if the OAuth tab is already open before waiting for a new one
  let oauthPage = context.pages().find(p => {
    try {
      const h = new URL(p.url()).hostname;
      return h === 'accounts.google.com' || h.endsWith('.google.com');
    } catch { return false; }
  });

  if (!oauthPage) {
    console.error('INFO: Waiting for Google OAuth tab (up to 30s)...');
    oauthPage = await context.waitForEvent('page', {
      predicate: p => {
        try {
          const h = new URL(p.url()).hostname;
          return h === 'accounts.google.com' || h.endsWith('.google.com');
        } catch { return false; }
      },
      timeout: 30000
    });
  }
```

**New**:
```js
  let oauthPage;
  if (GCP_AUTH_URL) {
    // Linux headless: gcloud cannot open a browser — navigate to the URL it printed
    console.error('INFO: Navigating directly to gcloud OAuth URL (Linux headless)...');
    oauthPage = await context.newPage();
    await oauthPage.goto(GCP_AUTH_URL, { waitUntil: 'domcontentloaded', timeout: 30000 });
  } else {
    // macOS: gcloud opens the OAuth tab in this Chrome session — wait for it
    oauthPage = context.pages().find(p => {
      try {
        const h = new URL(p.url()).hostname;
        return h === 'accounts.google.com' || h.endsWith('.google.com');
      } catch { return false; }
    });

    if (!oauthPage) {
      console.error('INFO: Waiting for Google OAuth tab (up to 30s)...');
      oauthPage = await context.waitForEvent('page', {
        predicate: p => {
          try {
            const h = new URL(p.url()).hostname;
            return h === 'accounts.google.com' || h.endsWith('.google.com');
          } catch { return false; }
        },
        timeout: 30000
      });
    }
  }
```

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/plugins/gcp.sh` function `gcp_login` (lines 132–188) in full.
3. Read `scripts/playwright/gcp_login.js` in full.
4. Read `memory-bank/activeContext.md`.
5. Run `shellcheck -S warning scripts/plugins/gcp.sh` — record baseline warning count.
6. Do NOT change the macOS branch of `gcp_login`.
7. Do NOT touch `gcp_get_credentials`, `gcp_revoke`, or any other function.

---

## Rules

- `shellcheck -S warning scripts/plugins/gcp.sh` must produce zero new warnings vs baseline.
- `node --check scripts/playwright/gcp_login.js` must pass.
- Only `scripts/plugins/gcp.sh` and `scripts/playwright/gcp_login.js` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Live Test (run on ACG Linux sandbox after committing)

Start a fresh ACG GCP lab session, then:

```bash
git pull origin k3d-manager-v1.1.0
make up
```

Expected:
- `[gcp] Running one-time 'gcloud auth login' for cloud_user_p_xxx@...`
- `INFO: Navigating directly to gcloud OAuth URL (Linux headless)...`
- `INFO: Entering email cloud_user_p_xxx@...`
- `INFO: Entering password...`
- `INFO: Clicking Allow...`
- `INFO: GCP OAuth flow complete.`
- `[gcp] Authenticated as cloud_user_p_xxx@...`
- `make up` continues past the gcloud auth step without `Error 1`

Paste the actual log output lines above — do not summarize.

---

## Definition of Done

1. `scripts/plugins/gcp.sh` diff matches Change 1 exactly — no extra hunks.
2. `scripts/playwright/gcp_login.js` diff matches Change 2 exactly — no extra hunks.
3. `shellcheck -S warning scripts/plugins/gcp.sh` — zero new warnings.
4. `node --check scripts/playwright/gcp_login.js` — exits 0.
5. Live test passed — paste actual log output.
6. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(gcp-login): capture OAuth URL on Linux headless; navigate directly in Chrome CDP
   ```
7. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
8. `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with real commit SHA.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify the macOS branch of `gcp_login` — only the Linux path changes.
- Do NOT touch `gcp_get_credentials`, `gcp_revoke`, or `gcp_login.js` beyond the two hunks above.
- Do NOT modify files outside `scripts/plugins/gcp.sh` and `scripts/playwright/gcp_login.js`.
- Do NOT commit to `main`.
- Do NOT use `gcloud auth login --no-launch-browser` — the fix uses the localhost-callback flow, not OOB.
