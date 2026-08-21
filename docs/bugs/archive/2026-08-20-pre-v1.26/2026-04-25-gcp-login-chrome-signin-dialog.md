# Bug: gcp_login.js does not dismiss "Sign in to Chrome?" dialog

**Branch:** `k3d-manager-v1.2.0`
**Work repo:** `wilddog64/lib-acg` at `/Users/cliang/src/gitrepo/personal/lib-acg/`
**File:** `playwright/gcp_login.js`

## Root Cause

When the GCP OAuth flow completes email + password sign-in, Chrome detects a new Google
account and displays a "Sign in to Chrome?" dialog offering to sync the account with Chrome.
This dialog appears as a **new page** in the CDP browser context, mid-flow — between the
password step and the OAuth consent screen.

`gcp_login.js` has no handler for new pages in the context, so the dialog is never dismissed
automatically. The user must click "Use Chrome Without an Account" manually before the consent
screens (Continue / Allow) appear.

The `--no-first-run` flag already suppresses Chrome's initial setup wizard; it does NOT
suppress the post-login sync prompt.

---

## Before You Start

1. `git pull origin k3d-manager-v1.2.0` in the k3d-manager repo.
2. Read this spec in full before touching any file.
3. Read `playwright/gcp_login.js` in lib-acg on `feat/phase5-ci-setup`.

**Work repo:** `wilddog64/lib-acg` at `/Users/cliang/src/gitrepo/personal/lib-acg/`
**Branch (lib-acg):** `feat/phase5-ci-setup` (already exists)

**k3d-manager is read-only for this task** — do NOT commit anything to k3d-manager.

---

## File: `playwright/gcp_login.js` — two changes

### Change 1: add `context.on('page', ...)` dialog handler

Insert after `const context = contexts[0];` and before the logout navigation:

**Old:**
```javascript
  const context = contexts[0];

  // Step 0 — Navigate to Google logout to clear all stale sessions
```

**New:**
```javascript
  const context = contexts[0];

  // Dismiss "Sign in to Chrome?" dialog — Chrome offers to sync with the signed-in Google
  // account; appears as a new page mid-OAuth flow. Dismiss without creating a Chrome profile.
  context.on('page', async (page) => {
    try {
      await page.waitForLoadState('domcontentloaded', { timeout: 5000 }).catch(() => {});
      const noChromeSignInBtn = page.locator('button:has-text("Use Chrome Without an Account")');
      if (await noChromeSignInBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
        console.error('INFO: Dismissing "Sign in to Chrome?" dialog...');
        await noChromeSignInBtn.click();
      }
    } catch { /* best-effort */ }
  });

  // Step 0 — Navigate to Google logout to clear all stale sessions
```

### Change 2: update stale comment in the `else` branch

**Old:**
```javascript
  } else {
    // macOS: gcloud opens the OAuth tab in this Chrome session — wait for it
```

**New:**
```javascript
  } else {
    // No URL provided: wait for gcloud to open the OAuth tab directly in this CDP session
```

---

## Rules

1. `node --check playwright/gcp_login.js` — must pass with zero errors.
2. Do NOT run `--no-verify`.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `playwright/gcp_login.js`.
- Do NOT modify anything under `scripts/lib/foundation/`.
- Do NOT commit to `main` in lib-acg.
- Do NOT commit anything to k3d-manager.

---

## Definition of Done

- [ ] `context.on('page', ...)` handler inserted after `const context = contexts[0];`
- [ ] Stale comment in `else` branch updated
- [ ] `node --check playwright/gcp_login.js` passes
- [ ] Committed to `feat/phase5-ci-setup` in lib-acg with exact message:
      `fix(gcp-login): dismiss Sign-in-to-Chrome dialog automatically; update stale comment`
- [ ] Pushed to `origin/feat/phase5-ci-setup`
- [ ] Update k3d-manager `memory-bank/activeContext.md` and `memory-bank/progress.md`
      with the lib-acg commit SHA and fix status COMPLETE
- [ ] Report back: SHA + paste memory-bank lines updated
