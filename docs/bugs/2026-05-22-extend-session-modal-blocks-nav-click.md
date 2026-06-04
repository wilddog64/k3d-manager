# Bug: "Extend Your Session" Modal Blocks Navigation Click

**Date:** 2026-05-22
**File:** `playwright/acg_credentials.js`
**Symptom:** `make up` fails with `locator.click: Timeout 30000ms exceeded` — the `extend-sandbox-modal` dialog intercepts pointer events on the Cloud Sandboxes nav link.

## Root Cause

`_dismissExtendYourSessionDialog()` is defined and called inside the "Start/Open flow" block
(lines ~389–418), but the "Extend Your Session" modal can also appear **before** that — during
the SPA navigation step at lines ~283–288:

```javascript
const navLink = page.locator('a[href*="cloud-sandboxes"]').first();
const navVisible = await navLink.isVisible({ timeout: 5000 }).catch(() => false);
if (navVisible) {
  await navLink.click();   // ← FAILS when extend-sandbox-modal is open
}
```

At this point the helper function is not yet in scope, so nothing dismisses the modal first.

The `_entryExtendDialog` check at lines ~246–257 handles the case where the dialog is
present on a **reused** sandbox tab (reloads the page). But when the script opens a fresh
tab and the dialog appears after SPA navigation renders, that guard does not fire.

## Fix

Extract `_dismissExtendYourSessionDialog` so it is defined before the navigation block,
then call it immediately before `navLink.click()`.

### Step 1 — Hoist the function

Move the `_dismissExtendYourSessionDialog` function definition to just before the navigation
block (before line 260, after the `_entryExtendDialog` guard block that ends around line 257).
No change to function body.

### Step 2 — Call it before navLink.click()

**Old (lines ~283–289):**
```javascript
        if (navVisible) {
          await navLink.click();
        } else {
          await page.evaluate(url => window.location.assign(url), targetUrl);
        }
```

**New:**
```javascript
        if (navVisible) {
          await _dismissExtendYourSessionDialog();
          await navLink.click();
        } else {
          await page.evaluate(url => window.location.assign(url), targetUrl);
        }
```

### Step 3 — Remove the now-duplicate definition inside the Start/Open block

After hoisting, delete the local `_dismissExtendYourSessionDialog` definition from inside
the `if (!credentialsAlreadyVisible)` block (it will already be in scope).

## Definition of Done

- [ ] `_dismissExtendYourSessionDialog` defined before the navigation block (hoisted out of Start/Open block)
- [ ] Called immediately before `navLink.click()` in the SPA navigation branch
- [ ] No duplicate definition remains inside `if (!credentialsAlreadyVisible)` block
- [ ] `node playwright/acg_credentials.js <url>` completes without timeout when modal is present at nav time
- [ ] Commit on branch `fix/next-improvements-3`: `fix(acg-credentials): dismiss extend-session modal before nav link click`
- [ ] Push to origin before reporting done

## What NOT to Do

- Do NOT change the function body — the DOM-click approach is intentional (Escape closes the panel)
- Do NOT remove the `_entryExtendDialog` guard at the top (covers a different code path)
- Do NOT add a new test for this without checking existing `tests/acg-restart.spec.js` first
- Do NOT commit to `main` — work on `fix/next-improvements-3`
