# Bugfix: v0.1.4 — _dismissExtendYourSessionDialog false positive fires keyboard Enter in wrong context

**Branch:** `feat/v0.1.4`
**Files:** `playwright/lib/sandbox.js`

---

## Problem

`_dismissExtendYourSessionDialog` checks `[role="dialog"]` elements for "Extend Your Session"
text. The AWS Sandbox popup panel is rendered as `[role="dialog"]` and its innerText contains
"Extend" somewhere (e.g. "four hours" / UI labels). This causes a false positive: `dialogVisible`
is true even when no real Extend Your Session dialog is on screen.

The function then:
1. Logs `INFO: "Extend Your Session" dialog detected — clicking Extend button...`
2. Checks for a visible Extend button → not found (no such button in AWS panel)
3. Falls through to `page.keyboard.press('Enter')` — pressing Enter in the context of the AWS panel (wrong)
4. The dialog-closed check still finds "Extend" text in the AWS panel → logs WARN "still visible"

This repeats every 2s during `_waitForCredentials`, filling the log with false positives
and potentially triggering unintended Enter keypresses on the AWS panel.

**Observed log:**
```
INFO: "Extend Your Session" dialog detected — clicking Extend button...
WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing
INFO: "Extend Your Session" dialog detected — clicking Extend button...
WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing
```
Screenshot shows AWS Sandbox panel open — no Extend Your Session dialog visible.

**Root cause (lines 136–163):** The Extend button visibility check happens AFTER the log line
and AFTER `page.bringToFront()`. When the button is not visible, the code falls through to
`page.keyboard.press('Enter')` instead of returning early. A false positive — where the AWS
panel matches the dialog text check but has no Extend button — causes spurious log spam and
unwanted Enter keypresses.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: check Extend button visibility before logging or acting

Move the `extendVisible` check BEFORE the log line. If not visible, return immediately — do
NOT log, do NOT press Enter.

**Exact old block (lines 136–163):**

```javascript
async function _dismissExtendYourSessionDialog(page) {
  const dialogVisible = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[role="dialog"]'))
      .some(d => (d.innerText || '').includes('Extend Your Session'))
  ).catch(() => false);
  if (!dialogVisible) return;

  console.error('INFO: "Extend Your Session" dialog detected — clicking Extend button...');
  await page.bringToFront();
  const extendBtn = page.locator(
    '[data-testid="extend-sandbox-modal"] button:has-text("Extend"), [role="alertdialog"] button:has-text("Extend"), [role="dialog"] button:has-text("Extend")'
  ).first();
  const extendVisible = await extendBtn.isVisible({ timeout: 2000 }).catch(() => false);
  if (extendVisible) {
    await extendBtn.click({ force: true }).catch(() => {});
  } else {
    await page.keyboard.press('Enter').catch(() => {});
  }
  await page.waitForTimeout(1000);
  const dialogClosed = await page.waitForFunction(
    () => !Array.from(document.querySelectorAll('[role="dialog"]'))
      .some(d => (d.innerText || '').includes('Extend Your Session')),
    { timeout: 5000 }
  ).then(() => true).catch(() => false);
  if (!dialogClosed) {
    console.error('WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing');
  }
}
```

**Exact new block:**

```javascript
async function _dismissExtendYourSessionDialog(page) {
  const dialogVisible = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[role="dialog"]'))
      .some(d => (d.innerText || '').includes('Extend Your Session'))
  ).catch(() => false);
  if (!dialogVisible) return;

  const extendBtn = page.locator(
    '[data-testid="extend-sandbox-modal"] button:has-text("Extend"), [role="alertdialog"] button:has-text("Extend"), [role="dialog"] button:has-text("Extend")'
  ).first();
  const extendVisible = await extendBtn.isVisible({ timeout: 2000 }).catch(() => false);
  if (!extendVisible) return;

  console.error('INFO: "Extend Your Session" dialog detected — clicking Extend button...');
  await page.bringToFront();
  await extendBtn.click({ force: true }).catch(() => {});
  await page.waitForTimeout(1000);
  const dialogClosed = await page.waitForFunction(
    () => !Array.from(document.querySelectorAll('[role="dialog"]'))
      .some(d => (d.innerText || '').includes('Extend Your Session')),
    { timeout: 5000 }
  ).then(() => true).catch(() => false);
  if (!dialogClosed) {
    console.error('WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing');
  }
}
```

**Why this works:** The real "Extend Your Session" dialog always has a visible "Extend" button.
If no Extend button is visible, the `[role="dialog"]` match is a false positive (e.g., the AWS
Sandbox panel). Returning early prevents log spam and unwanted Enter keypresses.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Move `extendVisible` check before log; return early when not visible |

---

## Rules

- `node --check playwright/lib/sandbox.js` — zero errors
- No other files touched

---

## Definition of Done

- [ ] `_dismissExtendYourSessionDialog`: `extendVisible` check is BEFORE `console.error('INFO: "Extend Your Session" dialog detected...')`
- [ ] When `!extendVisible`: `return` immediately — no log, no keyboard press
- [ ] `page.bringToFront()` and `extendBtn.click()` only called when `extendVisible` is true
- [ ] `node --check playwright/lib/sandbox.js` passes

**Commit message (exact):**
```
fix(sandbox): guard _dismissExtendYourSessionDialog against false positive — check button visibility before acting
```
