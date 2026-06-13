# Bugfix: v0.1.4 — _deleteConflictingSandbox panel stays open after deletion (no text Close button)

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`

---

## Problem

After `_deleteConflictingSandbox` confirms deletion (detects "Start Sandbox" for the
conflicting label — the panel is now in reset state), it tries to close the panel:

```javascript
const closeBtn = page.locator('button:has-text("Close")');
if (await closeBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
  await closeBtn.click({ force: true });
}
```

The AWS Sandbox panel's close affordance is an icon-only button (`button[aria-label="close"]`
or similar), NOT a text button. `button:has-text("Close")` finds nothing, `isVisible` returns
false, and the panel stays open.

**Effect:** The AWS panel remains open overlaying the page. When `_waitForCredentials` runs for
Azure, it sees the AWS panel's empty credential inputs, cannot find Azure's "Start Sandbox"
button (only AWS's is in the DOM), and cannot interact with Azure's "Open Sandbox" button
(behind the AWS overlay). The script loops for 420s and times out.

**Root cause (lines 305–312):** `button:has-text("Close")` does not match icon-only close
buttons. No fallback exists when the text button is not found.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: add aria-label selectors and Escape fallback

**Exact old block (lines 305–312):**

```javascript
  // Close the deleted sandbox panel — after deletion it stays open in "Start Sandbox" state
  // and blocks the target provider's "Open Sandbox" from being actionable.
  const closeBtn = page.locator('button:has-text("Close")');
  if (await closeBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
    console.error(`INFO: Closing ${conflictingLabel} panel after deletion...`);
    await closeBtn.click({ force: true });
    await page.waitForTimeout(1000);
  }
```

**Exact new block:**

```javascript
  // Close the deleted sandbox panel — after deletion it stays open in "Start Sandbox" state
  // and blocks the target provider's "Open Sandbox" from being actionable.
  const closeBtn = page.locator('button:has-text("Close"), button[aria-label="close"], button[aria-label="Close"]').first();
  if (await closeBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
    console.error(`INFO: Closing ${conflictingLabel} panel after deletion...`);
    await closeBtn.click({ force: true });
    await page.waitForTimeout(1000);
  } else {
    console.error(`INFO: No Close button found — pressing Escape to dismiss ${conflictingLabel} panel...`);
    await page.keyboard.press('Escape');
    await page.waitForTimeout(1000);
  }
```

**Why this works:** `button[aria-label="close"]` and `button[aria-label="Close"]` match the
icon-only X button used by Pluralsight's panel overlay. The `Escape` fallback handles cases
where neither selector matches — modal panels universally close on Escape.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Extend `closeBtn` selector with aria-label variants; add Escape fallback |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `closeBtn` locator includes `button[aria-label="close"]` and `button[aria-label="Close"]`
- [ ] `else` branch added: `page.keyboard.press('Escape')` + `page.waitForTimeout(1000)`
- [ ] `console.error` log emitted in both branches
- [ ] `node --check playwright/lib/sandbox.js` passes

**Commit message (exact):**
```
fix(sandbox): close deleted sandbox panel via aria-label or Escape fallback
```
