# Bug Fix: automate GCP OAuth consent flow in gcp_login

**Branch:** `recovery-v1.1.0-aws-first`
**Files:**
- `scripts/playwright/gcp_login.js` (new)
- `scripts/plugins/gcp.sh` — `gcp_login` function only

---

## Before You Start

1. `git pull origin recovery-v1.1.0-aws-first`
2. Read `scripts/playwright/acg_credentials.js` in full — understand CDP attach pattern,
   `chromium.connectOverCDP`, `context.waitForEvent`, `browser.disconnect()`
3. Read `scripts/plugins/gcp.sh` lines 118–158 (`gcp_login` function in full)
4. Read `scripts/etc/playwright/vars.sh` — understand `PLAYWRIGHT_CDP_HOST/PORT`

---

## Problem

`gcp_login` runs `gcloud auth login --account "${account}" --quiet` synchronously.
`gcloud` opens a Google OAuth tab in Chrome and blocks until the OAuth callback arrives —
but nothing automates the clicks. The user must manually:

1. Click the correct account on the "Choose an account" screen
2. Confirm "Managed Profile" if shown
3. Accept Terms of Service if shown
4. Click "Allow" for gcloud's OAuth scopes

The fix: create `scripts/playwright/gcp_login.js` to automate these clicks via CDP,
and update `gcp_login` to run `gcloud auth login` in the background while the
Playwright script handles the browser concurrently.

---

## Fix

### Change 1 — Create `scripts/playwright/gcp_login.js`

Create the file with the following exact content:

```javascript
'use strict';

const { chromium } = require('playwright');

/**
 * scripts/playwright/gcp_login.js
 *
 * Automates the Google OAuth consent flow triggered by `gcloud auth login`.
 * Connects to the running Chrome CDP session and handles:
 *   1. "Choose an account" — selects the account matching GCP_ACCOUNT arg
 *   2. "Managed Profile" confirmation — clicks Continue / Got it
 *   3. Terms of Service — clicks I agree / Accept
 *   4. OAuth scopes — clicks Allow
 *
 * Usage:
 *   node gcp_login.js <gcp-account-email>
 *
 * Environment:
 *   PLAYWRIGHT_CDP_HOST  (default: 127.0.0.1)
 *   PLAYWRIGHT_CDP_PORT  (default: 9222)
 */

const CDP_HOST = process.env.PLAYWRIGHT_CDP_HOST || '127.0.0.1';
const CDP_PORT = process.env.PLAYWRIGHT_CDP_PORT || '9222';
const CDP_URL = `http://${CDP_HOST}:${CDP_PORT}`;
const GCP_ACCOUNT = process.argv[2] || process.env.GCP_USERNAME || '';

async function handleGcpOAuthFlow() {
  const browser = await chromium.connectOverCDP(CDP_URL);
  const contexts = browser.contexts();
  if (contexts.length === 0) {
    throw new Error('No browser context found via CDP');
  }
  const context = contexts[0];

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
  console.error(`INFO: OAuth tab found: ${oauthPage.url()}`);

  await oauthPage.waitForLoadState('domcontentloaded', { timeout: 15000 });

  // Step 1 — Choose account
  if (GCP_ACCOUNT) {
    const accountLink = oauthPage.locator(
      `[data-email="${GCP_ACCOUNT}"], div[data-identifier="${GCP_ACCOUNT}"]`
    ).first();
    if (await accountLink.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.error(`INFO: Selecting account ${GCP_ACCOUNT}...`);
      await accountLink.click();
      await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
    } else {
      // Fallback: click the first listed account
      const firstAccount = oauthPage.locator('div[data-identifier], li.JDAKTe').first();
      if (await firstAccount.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking first listed account (fallback)...');
        await firstAccount.click();
        await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
      }
    }
  }

  // Step 2 — Managed Profile confirmation (shown for Google Workspace accounts)
  const managedProfileBtn = oauthPage.locator(
    'button:has-text("Got it"), button:has-text("Continue"), button:has-text("I understand")'
  ).first();
  if (await managedProfileBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Confirming Managed Profile...');
    await managedProfileBtn.click();
    await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
  }

  // Step 3 — Terms of Service
  const tosBtn = oauthPage.locator(
    'button:has-text("I agree"), button:has-text("Accept")'
  ).first();
  if (await tosBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Accepting Terms of Service...');
    await tosBtn.click();
    await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
  }

  // Step 4 — Allow gcloud OAuth scopes
  const allowBtn = oauthPage.locator('button:has-text("Allow")').first();
  if (await allowBtn.isVisible({ timeout: 15000 }).catch(() => false)) {
    console.error('INFO: Clicking Allow...');
    await allowBtn.click();
  } else {
    console.error('WARN: Allow button not found — OAuth may have completed via redirect');
  }

  // Wait for gcloud callback (localhost redirect signals completion)
  await oauthPage.waitForURL('*localhost*', { timeout: 30000 }).catch(() => {
    console.error('INFO: No localhost redirect observed — assuming OAuth completed');
  });
  console.error('INFO: GCP OAuth flow complete.');

  try { await browser.disconnect(); } catch {}
}

const TIMEOUT_MS = 60000;
let _timeoutHandle;
const _timeoutPromise = new Promise((_, reject) => {
  _timeoutHandle = setTimeout(
    () => reject(new Error(`gcp_login.js timed out after ${TIMEOUT_MS / 1000}s`)),
    TIMEOUT_MS
  );
});

Promise.race([handleGcpOAuthFlow(), _timeoutPromise])
  .then(() => {
    clearTimeout(_timeoutHandle);
    process.exit(0);
  })
  .catch(err => {
    clearTimeout(_timeoutHandle);
    console.error(`ERROR: ${err.message}`);
    process.exit(1);
  });
```

The file must be created at `scripts/playwright/gcp_login.js`. Do NOT make it executable
(`.js` files are invoked via `node`, not directly).

---

### Change 2 — Update `gcp_login` in `scripts/plugins/gcp.sh`

**Exact old block (lines 156–158):**

```bash
  _info "[gcp] Running one-time 'gcloud auth login' for ${account}..."
  gcloud auth login --account "${account}" --quiet
  _info "[gcp] Authenticated as ${account}"
```

**Exact new block:**

```bash
  _info "[gcp] Running one-time 'gcloud auth login' for ${account}..."
  local playwright_dir
  playwright_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../playwright"

  if ! command -v node >/dev/null 2>&1 || ! node -e "require('playwright')" 2>/dev/null; then
    printf 'WARN: %s\n' "[gcp] node/playwright not available — gcloud auth login will require manual browser interaction" >&2
    gcloud auth login --account "${account}"
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
  _info "[gcp] Authenticated as ${account}"
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/playwright/gcp_login.js` | New file — automates Google OAuth consent flow |
| `scripts/plugins/gcp.sh` | `gcp_login` function — run gcloud in background + Playwright concurrently |

---

## Rules

- `shellcheck scripts/plugins/gcp.sh` — must pass with zero warnings
- Only the two listed files may be touched
- Do NOT modify any other function in `gcp.sh` — only `gcp_login`
- Do NOT add `#!/usr/bin/env node` shebang or `chmod +x` to `gcp_login.js`
- The fallback path (no node/playwright) must still call `gcloud auth login` manually

---

## E2E Verification (must all pass before committing)

### Test F1 — shellcheck

```bash
shellcheck scripts/plugins/gcp.sh
```
Expected: exit 0, no output.

### Test F2 — node parse check

```bash
node --check scripts/playwright/gcp_login.js && echo "parse OK"
```
Expected: `parse OK`.

### Test F3 — gcp_login.js exists, not executable

```bash
test -f scripts/playwright/gcp_login.js && echo "exists"
test ! -x scripts/playwright/gcp_login.js && echo "not executable"
```
Expected: both lines print.

### Test F4 — old synchronous gcloud line removed

```bash
grep -n "gcloud auth login --account.*--quiet" scripts/plugins/gcp.sh || echo "none (OK)"
```
Expected: `none (OK)`.

### Test F5 — fallback path present

```bash
grep -n "node/playwright not available" scripts/plugins/gcp.sh
```
Expected: line found.

---

## Definition of Done

- [ ] `scripts/playwright/gcp_login.js` created with exact content above
- [ ] `scripts/plugins/gcp.sh` `gcp_login` updated — gcloud runs in background + Playwright concurrently
- [ ] Fallback (no node/playwright) still calls `gcloud auth login` manually
- [ ] Tests F1–F5 all pass — paste actual outputs
- [ ] `shellcheck scripts/plugins/gcp.sh` passes with zero warnings
- [ ] Committed and pushed to `recovery-v1.1.0-aws-first`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(gcp): automate OAuth consent flow in gcp_login via Playwright CDP
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed above
- Do NOT modify any function in `gcp.sh` other than `gcp_login`
- Do NOT commit to `main` — work on `recovery-v1.1.0-aws-first`
- Do NOT reformat or refactor unrelated lines in `gcp.sh`
- Do NOT implement a new CDP persistent context launch — connect only, never launch
