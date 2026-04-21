# Bug Fix: clean-slate login to prevent ghost account OAuth failure

**Branch:** `k3d-manager-v1.1.0`
**File:** `scripts/playwright/gcp_login.js`

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/playwright/gcp_login.js` in full — understand the current 4-step flow
3. Read `scripts/plugins/gcp.sh` function `gcp_login` — understand how `gcp_login.js` is called
   and that `GCP_PASSWORD` is already exported before the script runs

---

## Problem

When Chrome has stale "signed out" accounts in its Google account picker,
`gcp_login.js` clicks an existing ghost session. The click succeeds visually but Google
does not issue a fresh token — the localhost OAuth callback never fires. `gcloud auth login`
hangs waiting for the callback; `gcloud auth list` shows no new account.

Root cause: Step 1 picks the account by `data-email` / `data-identifier` attribute.
When that account already has a stale session, clicking it re-uses the old cookie rather
than triggering a fresh grant. The localhost redirect (`127.0.0.1:...`) that `gcloud`
waits for never arrives.

---

## Fix

Replace the entire `handleGcpOAuthFlow` function body in `scripts/playwright/gcp_login.js`
with the following **exact content**. The outer scaffolding (`TIMEOUT_MS`, `Promise.race`,
constants, `require` line) stays unchanged — only the function body changes.

```js
// current — scripts/playwright/gcp_login.js
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
    'button:has-text("Got it"), button:has-text("Continue"), button:has-text("I understand"), button:has-text("Confirm")'
  ).first();
  if (await managedProfileBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Confirming Managed Profile...');
    await managedProfileBtn.click();
    await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
  }

  // Step 3 — Terms of Service
  const tosBtn = oauthPage.locator(
    'button:has-text("I agree"), button:has-text("Accept"), button:has-text("Agree and continue")'
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
```

```js
// replacement — scripts/playwright/gcp_login.js
async function handleGcpOAuthFlow() {
  const browser = await chromium.connectOverCDP(CDP_URL);
  const contexts = browser.contexts();
  if (contexts.length === 0) {
    throw new Error('No browser context found via CDP');
  }
  const context = contexts[0];

  // Step 0 — Navigate to Google logout to clear all stale sessions
  console.error('INFO: Clearing stale Google sessions...');
  const logoutPage = await context.newPage();
  await logoutPage.goto('https://accounts.google.com/Logout', { waitUntil: 'domcontentloaded', timeout: 15000 });
  await logoutPage.close();

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

  // Step 1 — Use another account (force fresh credential entry after logout)
  const useAnotherAccountBtn = oauthPage.locator(
    'li:has-text("Use another account"), div:has-text("Use another account")'
  ).first();
  if (await useAnotherAccountBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Clicking "Use another account"...');
    await useAnotherAccountBtn.click();
    await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
  }

  // Step 1b — Enter email
  if (GCP_ACCOUNT) {
    const emailInput = oauthPage.locator('input[type="email"]').first();
    if (await emailInput.isVisible({ timeout: 5000 }).catch(() => false)) {
      console.error(`INFO: Entering email ${GCP_ACCOUNT}...`);
      await emailInput.fill(GCP_ACCOUNT);
      await oauthPage.locator('button:has-text("Next")').first().click();
      await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
    }
  }

  // Step 1c — Enter password
  const gcpPassword = process.env.GCP_PASSWORD || '';
  if (gcpPassword) {
    const passwordInput = oauthPage.locator('input[type="password"]').first();
    if (await passwordInput.isVisible({ timeout: 10000 }).catch(() => false)) {
      console.error('INFO: Entering password...');
      await passwordInput.fill(gcpPassword);
      await oauthPage.locator('button:has-text("Next")').first().click();
      await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
    }
  }

  // Step 2 — Managed Profile confirmation (shown for Google Workspace accounts)
  const managedProfileBtn = oauthPage.locator(
    'button:has-text("Got it"), button:has-text("Continue"), button:has-text("I understand"), button:has-text("Confirm")'
  ).first();
  if (await managedProfileBtn.isVisible({ timeout: 5000 }).catch(() => false)) {
    console.error('INFO: Confirming Managed Profile...');
    await managedProfileBtn.click();
    await oauthPage.waitForLoadState('domcontentloaded', { timeout: 10000 });
  }

  // Step 3 — Terms of Service
  const tosBtn = oauthPage.locator(
    'button:has-text("I agree"), button:has-text("Accept"), button:has-text("Agree and continue")'
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
```

**Note on `GCP_PASSWORD`:** `gcp_get_credentials` in `scripts/plugins/gcp.sh` exports
`GCP_PASSWORD` before calling `gcloud auth login`. The password is already in the
environment when `gcp_login.js` runs — no changes to `gcp.sh` are needed.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/playwright/gcp_login.js` | Replace `handleGcpOAuthFlow` body — add logout step, "Use another account" path, email+password entry |

---

## Rules

- Only `scripts/playwright/gcp_login.js` may be touched
- Do NOT modify `scripts/plugins/gcp.sh`
- Do NOT change the outer scaffolding (`TIMEOUT_MS`, `Promise.race`, constants, `require` line)
- `GCP_PASSWORD` must be read from `process.env.GCP_PASSWORD` — never from argv
- Do NOT log the password value — only log `'INFO: Entering password...'`

---

## E2E Verification

### Test A1 — node syntax check
```bash
node --check scripts/playwright/gcp_login.js && echo "syntax OK"
```
Expected: `syntax OK`.

### Test A2 — confirm key strings present
```bash
grep -n "accounts.google.com/Logout" scripts/playwright/gcp_login.js
grep -n "Use another account" scripts/playwright/gcp_login.js
grep -n "GCP_PASSWORD" scripts/playwright/gcp_login.js
```
Expected: one match each.

### Test A3 — live E2E (run with active GCP sandbox)
```bash
source scripts/plugins/gcp.sh
gcp_get_credentials
gcloud auth list
```
Expected: cloud_user account appears as ACTIVE in `gcloud auth list`.

---

## Definition of Done

- [ ] `handleGcpOAuthFlow` replaced with the exact content above
- [ ] Tests A1 and A2 pass — paste actual outputs
- [ ] Test A3 — live smoke test run and `gcloud auth list` output pasted
- [ ] Committed and pushed to `k3d-manager-v1.1.0`
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with commit SHA

**Commit message (exact):**
```
fix(gcp): clean-slate login — logout + explicit email/password to unblock OAuth callback
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/playwright/gcp_login.js`
- Do NOT commit to `main`
- Do NOT hardcode or log the value of `GCP_PASSWORD`
- Do NOT remove the existing Step 2 (Managed Profile) or Step 3 (ToS) selectors
