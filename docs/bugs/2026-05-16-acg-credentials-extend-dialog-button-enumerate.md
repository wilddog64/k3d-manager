# Bug: acg_credentials — handler can't find "Extend" button (wrong text), falls back to Cancel, dialog loops 3×

**Branch:** `k3d-manager-v1.4.6`
**File:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

After the `click Extend instead of Cancel` fix (commit `a07c3c10`), the "Extend Your Session"
dialog still loops — now 3× instead of 5× (handler is slower because `_handlerExtendBtn.isVisible`
times out at 1000ms waiting for a button labeled "Extend" that doesn't exist). The code falls
back to `Cancel`, which is the same behavior as before.

The dialog button is NOT labeled "Extend". We do not know its actual label.

```
INFO: [handler] Auto-extending "Extend Your Session" prompt...  (×3)
ERROR: locator.click: Timeout 30000ms exceeded.
  3 × found locator ... intercepting action to run the handler
    - locator handler has finished, waiting for locator to be hidden
    - interception handler has finished, continuing
```

**Root cause:** The button selector `button:has-text("Extend")` does not match any button in the
dialog. The exact affirmative button text is unknown. The handler must enumerate all dialog buttons
and click the first one that is not a cancel/dismiss action, regardless of its exact text.

---

## Reproduction

1. Have a GCP sandbox session near expiry
2. Run `make up CLUSTER_PROVIDER=k3s-gcp`
3. "Extend Your Session" dialog appears during Start Sandbox (Step 2)
4. Handler fires 3× — each time falling through to Cancel (not Extend)
5. 30s timeout

---

## Fix

### Change 1 — `addLocatorHandler` callback: enumerate buttons, click first non-cancel button

Replace the entire handler callback body (lines 256–268). No other lines change.

**Exact old block:**

```javascript
        console.error('INFO: [handler] Auto-extending "Extend Your Session" prompt...');
        const _handlerExtendBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Extend")').first();
        const _handlerCancelBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Cancel")').first();
        if (await _handlerExtendBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerExtendBtn.click({ force: true }).catch(() => {});
          await page.waitForTimeout(500).catch(() => {});
          await page.keyboard.press('Escape').catch(() => {});
        } else if (await _handlerCancelBtn.isVisible({ timeout: 1000 }).catch(() => false)) {
          await _handlerCancelBtn.click({ force: true }).catch(() => {});
        } else {
          await page.keyboard.press('Escape').catch(() => {});
        }
        await page.waitForTimeout(1000).catch(() => {});
```

**Exact new block:**

```javascript
        const _dlgBtns = page.locator('[role="dialog"]:has-text("Extend Your Session") button');
        const _dlgBtnCount = await _dlgBtns.count().catch(() => 0);
        const _dlgTexts = [];
        for (let _hbi = 0; _hbi < _dlgBtnCount; _hbi++) {
          _dlgTexts.push((await _dlgBtns.nth(_hbi).textContent().catch(() => '?')).trim());
        }
        console.error(`INFO: [handler] "Extend Your Session" buttons (${_dlgBtnCount}): ${_dlgTexts.join(' | ')}`);
        const _cancelWords = ['cancel', 'no', 'dismiss', 'skip', 'later', 'close'];
        const _affirmIdx = _dlgTexts.findIndex(_t => !_cancelWords.some(_w => _t.toLowerCase().includes(_w)));
        if (_affirmIdx >= 0) {
          console.error(`INFO: [handler] Clicking affirmative button: "${_dlgTexts[_affirmIdx]}"`);
          await _dlgBtns.nth(_affirmIdx).click({ force: true }).catch(() => {});
          await page.waitForTimeout(500).catch(() => {});
          await page.keyboard.press('Escape').catch(() => {});
        } else if (_dlgBtnCount > 0) {
          console.error(`INFO: [handler] No affirmative button found — clicking first button: "${_dlgTexts[0]}"`);
          await _dlgBtns.first().click({ force: true }).catch(() => {});
        } else {
          console.error('INFO: [handler] No buttons found — pressing Enter');
          await page.keyboard.press('Enter').catch(() => {});
        }
        await page.waitForTimeout(1000).catch(() => {});
```

**Why this works:**
- Enumerates all buttons in the dialog and logs their texts — gives us the exact label on the next run.
- Clicks the first button whose text does NOT contain cancel-like words ("cancel", "no", "dismiss",
  "skip", "later", "close"). This is the affirmative/primary action regardless of its exact label.
- If all buttons are cancel-like (unlikely), clicks the first button anyway as a last resort.
- If no buttons at all, presses Enter to activate the focused/default button.
- Keeps the 500ms + Escape (to dismiss any "Session extended" confirmation after extending)
  and the trailing 1000ms settle wait — both unchanged from the previous fix.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Handler callback: enumerate buttons, click first non-cancel |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass (zero syntax errors)
- No other files touched

---

## Definition of Done

- [ ] Handler callback body matches the exact new block above
- [ ] The `_dlgBtnCount` / `_dlgTexts` enumeration loop is present and logs the button count + texts
- [ ] `_cancelWords` array is present and `findIndex` selects the first non-cancel button
- [ ] Affirmative click + 500ms + Escape is in the `_affirmIdx >= 0` branch
- [ ] Fallback to `_dlgBtns.first().click()` is present when `_affirmIdx < 0` but buttons exist
- [ ] Fallback to `page.keyboard.press('Enter')` is present when no buttons at all
- [ ] Trailing `await page.waitForTimeout(1000).catch(() => {})` is unchanged (last line before `}`)
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Commit message (exact): `fix(acg-credentials): enumerate dialog buttons and click first non-cancel to handle unknown button label`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT remove the `[data-open="true"]` selector from the `addLocatorHandler` locator
- Do NOT remove the trailing `waitForTimeout(1000)` — still needed for page settle
- Do NOT hardcode a specific button text — the enumeration approach is intentional
- Do NOT add `{ noWaitAfter: true }` to `addLocatorHandler`
