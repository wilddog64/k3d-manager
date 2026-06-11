# Bug: device code fallback requires manual browser input — must automate via CDP

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**Files:** `playwright/acg_azure_device_login.js` (new), `bin/acg-credential-test`
**Supersedes:** `2026-06-11-az-portal-mfa-device-code-fallback.md`,
               `2026-06-11-device-code-azure-config-dir-deleted-tempdir.md`

---

## Symptom

`make credential-test PROVIDER=azure` with a portal-only sandbox prints a device code URL
and code to the terminal and then hangs, waiting for the user to manually open a browser
and enter the code. This breaks the automation contract — the script must run unattended.

---

## Root Cause

The current `_az_portal_valid` fallback calls `az login --use-device-code` and lets it
block waiting for the user. The existing Chrome CDP session on port 9222 already has a
Microsoft-authenticated session (from the ACG portal login). We can automate the device
code form fill using Playwright + CDP.

Secondary issue in `24a89f1`: `AZURE_CONFIG_DIR="$config_dir"` is applied to both the
device code login and the token probe. `_az_login_probe_clean` traps `rm -rf "$config_dir"`
on RETURN — the temp dir is deleted before the device code path runs. The device code
session must write to `~/.azure` (no `AZURE_CONFIG_DIR` override).

---

## Fix

### Change 1 — new file `playwright/acg_azure_device_login.js`

Create this file. It connects to the existing Chrome via CDP, opens a new tab, navigates
to the Microsoft device login URL, fills the code, and confirms sign-in.

**Exact content:**

```javascript
'use strict';
const { chromium } = require('playwright');
const { CDP_URL } = require('./lib/output');

async function main() {
  const [,, deviceUrl, deviceCode] = process.argv;
  if (!deviceUrl || !deviceCode) {
    console.error('ERROR: Usage: acg_azure_device_login.js <device-url> <device-code>');
    process.exit(1);
  }

  const cdpBrowser = await chromium.connectOverCDP(CDP_URL);
  const context = cdpBrowser.contexts()[0];
  if (!context) {
    console.error('ERROR: No browser context available — is Chrome running with --remote-debugging-port=9222?');
    await cdpBrowser.disconnect().catch(() => {});
    process.exit(1);
  }

  const page = await context.newPage();
  try {
    console.error(`INFO: Navigating to device login: ${deviceUrl}`);
    await page.goto(deviceUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });

    const codeInput = page.locator('input[name="otc"]').first();
    await codeInput.waitFor({ state: 'visible', timeout: 15000 });
    await codeInput.fill(deviceCode);
    console.error(`INFO: Filled device code: ${deviceCode}`);

    await page.locator('input[type="submit"]').first().click();
    await page.waitForTimeout(2000);

    const confirmBtn = page.locator('input[type="submit"], button').filter({
      hasText: /continue|yes|confirm/i,
    }).first();
    if (await confirmBtn.isVisible({ timeout: 8000 }).catch(() => false)) {
      await confirmBtn.click({ force: true });
      await page.waitForTimeout(2000);
    }

    const bodyText = await page.textContent('body').catch(() => '');
    if (/signed.?in|you.*close|authentication.?complete/i.test(bodyText)) {
      console.error('INFO: Device code sign-in confirmed in browser.');
    } else {
      console.error('INFO: Device code submitted — proceeding.');
    }
    process.exit(0);
  } catch (e) {
    console.error(`ERROR: acg_azure_device_login failed: ${e.message}`);
    process.exit(1);
  } finally {
    await page.close().catch(() => {});
    await cdpBrowser.disconnect().catch(() => {});
  }
}

main().catch(e => {
  console.error(`FATAL: ${e.message}`);
  process.exit(1);
});
```

### Change 2 — `bin/acg-credential-test`: automate device code via browser in `_az_portal_valid`

**Exact old block (lines 165–187):**

```bash
_az_portal_valid() {
  local username password tenant config_dir
  username=$(grep ^'AZURE_USERNAME=' "$_tmpout" | cut -d= -f2-)
  password=$(grep ^'AZURE_PASSWORD=' "$_tmpout" | cut -d= -f2-)
  tenant=$(_azure_discover_tenant)
  [[ -n "$username" && -n "$password" ]] || return 1
  [[ -n "$tenant" ]] || { printf 'ERROR: Could not determine Azure tenant ID\n' >&2; return 1; }

  config_dir=$(mktemp -d)
  if _az_login_probe_clean "$config_dir" az login \
    --username "$username" \
    --password "$password" \
    --tenant "$tenant"; then
    return 0
  fi
  printf 'INFO: Username/password login failed (MFA enforcement) — falling back to device code flow.\n' >&2
  printf 'INFO: Open the URL printed below in your browser and enter the code to authenticate.\n' >&2
  AZURE_CONFIG_DIR="$config_dir" az login --use-device-code --tenant "$tenant" --allow-no-subscriptions --output none >/dev/null || {
    AZURE_LOGIN_ERROR='Device code login failed or was cancelled'
    return 1
  }
  AZURE_CONFIG_DIR="$config_dir" az account get-access-token --resource https://management.azure.com/ --output none >/dev/null 2>&1
}
```

**Exact new block:**

```bash
_az_portal_valid() {
  local username password tenant config_dir device_tmp az_pid device_url device_code _i
  username=$(grep '^AZURE_USERNAME=' "$_tmpout" | cut -d= -f2-)
  password=$(grep '^AZURE_PASSWORD=' "$_tmpout" | cut -d= -f2-)
  tenant=$(_azure_discover_tenant)
  [[ -n "$username" && -n "$password" ]] || return 1
  [[ -n "$tenant" ]] || { printf 'ERROR: Could not determine Azure tenant ID\n' >&2; return 1; }

  config_dir=$(mktemp -d)
  if _az_login_probe_clean "$config_dir" az login \
    --username "$username" \
    --password "$password" \
    --tenant "$tenant"; then
    return 0
  fi
  printf 'INFO: Username/password login failed (MFA enforcement) — automating device code via browser.\n' >&2
  device_tmp=$(mktemp)
  az login --use-device-code --tenant "$tenant" --allow-no-subscriptions --output none 2>"$device_tmp" &
  az_pid=$!
  _i=0
  until grep -qE 'microsoft\.com/device' "$device_tmp" 2>/dev/null; do
    _i=$(( _i + 1 ))
    if (( _i > 60 )); then
      printf 'ERROR: Timed out waiting for device code URL from az login.\n' >&2
      kill "$az_pid" 2>/dev/null || true
      rm -f "$device_tmp"
      return 1
    fi
    sleep 0.5
  done
  device_url=$(grep -oE 'https://[^ ]+microsoft\.com/device[^ ]*' "$device_tmp" | head -1)
  device_code=$(grep -oE 'code [A-Z0-9]+' "$device_tmp" | awk '{print $2}' | head -1)
  rm -f "$device_tmp"
  if [[ -z "$device_url" || -z "$device_code" ]]; then
    printf 'ERROR: Could not parse device code URL or code from az output.\n' >&2
    kill "$az_pid" 2>/dev/null || true
    return 1
  fi
  printf 'INFO: Automating device sign-in in browser (url=%s code=%s).\n' "$device_url" "$device_code" >&2
  node "$REPO_ROOT/playwright/acg_azure_device_login.js" "$device_url" "$device_code" >&2 || {
    printf 'ERROR: Browser automation of device code sign-in failed.\n' >&2
    kill "$az_pid" 2>/dev/null || true
    return 1
  }
  wait "$az_pid" || {
    AZURE_LOGIN_ERROR='az login --use-device-code failed after browser automation'
    return 1
  }
  az account get-access-token --resource https://management.azure.com/ --output none 2>/dev/null
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_azure_device_login.js` | New — CDP browser automation for device code form fill |
| `bin/acg-credential-test` | Replace manual device code block with background az + Playwright automation |

---

## Rules

- `node --check playwright/acg_azure_device_login.js` must pass
- `shellcheck -S warning bin/acg-credential-test` — zero new warnings
- No other files touched

---

## Definition of Done

- [ ] `playwright/acg_azure_device_login.js` exists with exact content from spec
- [ ] `node --check playwright/acg_azure_device_login.js` passes
- [ ] `_az_portal_valid` new block: username/password first, then background `az login --use-device-code`, poll for URL+code, call Playwright script, `wait "$az_pid"`, validate token
- [ ] No `AZURE_CONFIG_DIR` in the device code path (session writes to `~/.azure`)
- [ ] `device_tmp` cleaned up with `rm -f` before calling Playwright
- [ ] `shellcheck -S warning bin/acg-credential-test` passes with zero new warnings
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(credential-test): automate device code sign-in via CDP — replace manual browser prompt
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT add `AZURE_CONFIG_DIR` to the device code `az login` or `az account get-access-token` calls
- Do NOT commit to `main` — work on `feat/v0.1.5`
- Do NOT touch `_az_sp_valid`, `_az_identity_valid`, or `_az_login_probe_clean`
- Do NOT modify any other Playwright scripts
