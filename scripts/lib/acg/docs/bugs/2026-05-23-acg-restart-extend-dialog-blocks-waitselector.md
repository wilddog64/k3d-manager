# Bug: acg_restart — waitForSelector times out — "Extend Your Session" dialog appears after _dismissExtendYourSessionDialog returns

**Branch (lib-acg):** `fix/next-improvements-5`
**File:** `playwright/acg_restart.js`

---

## Problem

After `openBtn.click()`, the script calls `_dismissExtendYourSessionDialog` once and then
calls `waitForSelector('button:has-text("Delete Sandbox")', { timeout: 15000 })`. The dialog
appears with a delay (triggered by the panel-open animation), AFTER the dismiss call has
already returned. The `waitForSelector` then blocks for the full 15 s while the dialog
prevents the panel from revealing "Delete Sandbox".

```
INFO: Delete Sandbox not visible — clicking Open Sandbox to reveal panel...
ERROR: page.waitForSelector: Timeout 15000ms exceeded.
  - waiting for locator('button:has-text("Delete Sandbox")') to be visible
```

The background watcher (`_startExtendDialogWatcher`) polls every 2000 ms, but
`page.evaluate` DOM-click is not reliably closing the modal (React's synthetic event system
may not handle programmatic `MouseEvent` dispatches on the Cancel button), so the dialog
persists for the entire 15 s timeout.

**Root cause:** `waitForSelector` at line 266 has no mechanism to dismiss the Extend dialog
if it appears DURING the wait. The one-shot dismiss at line 265 fires too early (dialog not
yet visible), and the background watcher's DOM click is not reliable enough.

---

## Fix

Replace lines 265–266 (the one-shot dismiss + `waitForSelector`) with a 500 ms polling
loop that calls `_dismissExtendYourSessionDialog` on every tick and checks `deleteBtn`
visibility, timing out after 15 s.

### Change — `playwright/acg_restart.js`: replace waitForSelector with polling loop

**Exact old block (lines 264–266):**

```javascript
      await openBtn.click({ force: true });
      await _dismissExtendYourSessionDialog(page);
      await page.waitForSelector('button:has-text("Delete Sandbox")', { timeout: 15000 });
```

**Exact new block:**

```javascript
      await openBtn.click({ force: true });
      // Poll for Delete Sandbox — dismiss Extend dialog on every tick so a late-appearing
      // dialog cannot block for more than one 500 ms interval.
      const _deletePollDeadline = Date.now() + 15000;
      let _deleteBtnReady = false;
      while (Date.now() < _deletePollDeadline) {
        await _dismissExtendYourSessionDialog(page);
        _deleteBtnReady = await deleteBtn.isVisible({ timeout: 500 }).catch(() => false);
        if (_deleteBtnReady) break;
        await page.waitForTimeout(500).catch(() => {});
      }
      if (!_deleteBtnReady) {
        const _url = page.url();
        const _btns = await page.evaluate(() =>
          Array.from(document.querySelectorAll('button'))
            .map(b => (b.innerText || b.textContent || '').trim())
            .filter(t => t.length > 0)
        ).catch(() => []);
        throw new Error(`Delete Sandbox button did not appear within 15s after Open Sandbox click. URL: ${_url} | Buttons: ${JSON.stringify(_btns)}`);
      }
```

**Why:** The loop dismisses the dialog and checks button visibility every 500 ms. Even if
the dialog appears after the first dismiss call, the next tick catches it within 500 ms
instead of waiting up to 2000 ms for the background watcher. The explicit error message
replaces the generic `waitForSelector` timeout and includes the current URL and visible
button list for diagnostics.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_restart.js` | Replace 3-line open+dismiss+waitForSelector block with 14-line polling loop |

---

## Rules

- `node --check playwright/acg_restart.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] Lines 264–266 replaced with the exact new block above
- [ ] No other functions or files modified
- [ ] `node --check playwright/acg_restart.js` passes
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-restart): poll + dismiss Extend dialog while waiting for Delete Sandbox button
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_restart.js`
- Do NOT commit to `main`
- Do NOT change any other function in the file
