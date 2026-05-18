# Bug: acg_credentials — handler dismisses with Cancel causing dialog loop; _clickStartSandbox force-click hides button

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

Two regressions vs v1.4.5:

1. **Handler dismisses with Cancel** — Cancel does not extend the session, so the "Extend Your
   Session" dialog immediately reappears. The handler fires a second time, clicks Cancel again,
   and the page is now mid-re-render with the Start Sandbox button hidden behind the reappearing
   modal. The click then fails with `Element is not visible`.

2. **`_clickStartSandbox` with `{ force: true }`** — force bypasses Playwright's stability and
   viewport checks but does NOT help when the button is truly hidden (behind a modal overlay).
   It also adds a redundant `.first()` to the locator (`.first().first()`). v1.4.5 used plain
   `startButton.click()` which waited for full actionability and worked correctly.

```
INFO: [handler] Dismissing "Extend Your Session" prompt...
INFO: [handler] Dismissing "Extend Your Session" prompt...
ERROR: locator.click: Element is not visible
Call log:
  - waiting for locator('button:has-text("Start Sandbox")').first().first()
    - locator resolved to <button ...>
  - attempting click action
    - scrolling into view if needed
    - done scrolling
```

**Root cause:**
- Handler clicks Cancel → dialog reappears → 2nd handler fire → button ends up hidden → click fails.
- `_clickStartSandbox` helper removes the actionability wait that v1.4.5 relied on.

---

## Reproduction

1. Have an AWS sandbox session near expiry
2. Run `make up`
3. "Extend Your Session" dialog appears during Start Sandbox (Step 2)
4. Handler fires, clicks Cancel, dialog disappears and immediately reappears
5. Handler fires again, clicks Cancel again — button is hidden by the re-appearing modal
6. `_clickStartSandbox` tries force-click, fails with `Element is not visible`

---

## Fix

### Change 1 — Handler: click primary (filled) Extend button; Escape the "Session extended" confirmation

**Exact old block (lines 264–272):**

```javascript
        console.error('INFO: [handler] Dismissing "Extend Your Session" prompt...');
        const _handlerCancelBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Cancel")').first();
        if (await _handlerCancelBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerCancelBtn.click({ force: true }).catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
        await page.waitForTimeout(250).catch(() => {});
```

**Exact new block:**

```javascript
        console.error('INFO: [handler] Extending "Extend Your Session" prompt...');
        const _extendBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button.pando-button--usage_filled').first();
        if (await _extendBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _extendBtn.click({ force: true }).catch(() => {});
          await page.waitForTimeout(500).catch(() => {});
          await page.keyboard.press('Escape').catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
        await page.waitForTimeout(250).catch(() => {});
```

**Why:** `pando-button--usage_filled` selects the primary action button (Extend) in Pluralsight's
Pando design system — the same class used by the Start Sandbox button. Clicking it actually extends
the session so the dialog does not immediately reappear. The 500ms pause + Escape dismisses the
"Session extended" confirmation modal that appears after the extension. Fallback to Escape handles
the case where the filled button is not found.

---

### Change 2 — Remove `_clickStartSandbox` helper entirely

**Exact old block (lines 152–160):**

```javascript
async function _clickStartSandbox(page, buttonLocator) {
  const _prompt = page.locator('[role="dialog"]:has-text("Extend Your Session")').first();
  await _prompt.waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
  const _btn = buttonLocator.first();
  await _btn.scrollIntoViewIfNeeded().catch(() => {});
  await _btn.click({ force: true });
}

async function extractCredentials() {
```

**Exact new block:**

```javascript
async function extractCredentials() {
```

**Why:** The helper added a redundant `.first()` (creating `.first().first()`) and bypassed
Playwright's actionability wait with `{ force: true }`. After the handler actually extends the
session (Change 1), the button stays stable and in-viewport — plain `.click()` is sufficient,
exactly as v1.4.5 had it.

---

### Change 3 — Revert `startButton` call to plain click

**Exact old block:**

```javascript
          console.error('INFO: Clicking Start Sandbox...');
          await _clickStartSandbox(page, startButton);
```

**Exact new block:**

```javascript
          console.error('INFO: Clicking Start Sandbox...');
          await startButton.click();
```

---

### Change 4 — Revert `startButton2` call to plain click

**Exact old block:**

```javascript
          console.error('INFO: Clicking Start Sandbox (Step 2)...');
          await _clickStartSandbox(page, startButton2);
```

**Exact new block:**

```javascript
          console.error('INFO: Clicking Start Sandbox (Step 2)...');
          await startButton2.click();
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Handler: click filled Extend button + Escape confirmation; remove `_clickStartSandbox`; revert both call sites to plain `.click()` |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

- [ ] Handler log message changed to `'INFO: [handler] Extending "Extend Your Session" prompt...'`
- [ ] Handler uses `button.pando-button--usage_filled` selector (not `button:has-text("Cancel")`)
- [ ] Handler clicks filled button, waits 500ms, presses Escape, then waits 250ms
- [ ] Handler falls back to Escape when filled button not visible
- [ ] `_clickStartSandbox` function is gone — no reference anywhere in the file
- [ ] `startButton.click()` (not `_clickStartSandbox`) at the Step 1 call site
- [ ] `startButton2.click()` (not `_clickStartSandbox`) at the Step 2 call site
- [ ] No other lines touched
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg-credentials): extend session via filled button; revert to plain startButton click`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT keep `{ force: true }` on the startButton clicks — plain `.click()` is correct
- Do NOT keep `_clickStartSandbox` — remove it entirely
- Do NOT reintroduce `button:has-text("Cancel")` — Cancel does not extend the session
- Do NOT reintroduce `button:has-text("Extend")` — the exact text was not found previously; use the CSS class selector instead
