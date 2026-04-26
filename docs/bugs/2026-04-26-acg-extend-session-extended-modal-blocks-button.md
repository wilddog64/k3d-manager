# Bug: "Session Extended" Modal Blocks Extend Button on Repeat Calls

**File:** `playwright/acg_extend.js`
**Branch:** `feat/phase5-ci-setup`
**Severity:** High — `acg_extend` fails every time except the very first call per browser session

---

## Symptom

```
INFO: Already on Pluralsight page: https://app.pluralsight.com/hands-on/playground/cloud-sandboxes
INFO: Calculated remaining TTL: ~42 minutes
INFO: Within 1h extension window (42m remaining). Proceeding to extend...
INFO: Clicking Open Sandbox to reveal extend panel...
ERROR: Extend button not found or not visible after multiple attempts (including recovery)
```

The "Session extended" confirmation modal (title: "Session extended", body: "Your sandbox has been extended.") appears after a successful extension and is never dismissed. On the next call, the modal is still on screen and blocks the extend button from being visible, causing all selector checks to fail.

---

## Root Cause

`extendSandbox()` has no step to dismiss lingering confirmation modals before beginning its extend button search. The modal remains open indefinitely until the user manually closes it.

---

## Fix

In `playwright/acg_extend.js`, add a modal dismissal step **immediately after the `page` object is resolved** (after line 87, before the skeleton loader wait at line 90).

### Exact insertion point

After this block (lines 82–87):
```javascript
    if (isPluralsight) {
      console.error(`INFO: Already on Pluralsight page: ${currentUrl}`);
    } else {
      console.error(`INFO: Navigating to ${targetUrl}...`);
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    }
```

Insert:
```javascript
    // Dismiss any lingering "Session extended" confirmation modal before searching for extend button
    const _sessionExtendedModal = page.locator('text="Session extended"').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await page.keyboard.press('Escape').catch(() => {});
      await page.waitForTimeout(500);
      // Fallback: click the X button if Escape didn't close it
      const _closeBtn = page.locator('[role="dialog"] button, button:has-text("×"), button[aria-label*="close" i]').first();
      if (await _closeBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
        await _closeBtn.click({ force: true }).catch(() => {});
        await page.waitForTimeout(500);
      }
    }
```

---

## Definition of Done

- [ ] Dismissal block added after the navigation guard (before the skeleton loader wait)
- [ ] `node --check playwright/acg_extend.js` passes with zero errors
- [ ] Committed on branch `feat/phase5-ci-setup` in lib-acg with message:
  `fix(acg-extend): dismiss Session Extended modal before searching for extend button`
- [ ] SHA reported; pushed to origin

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_extend.js`
- Do NOT commit to `main`
