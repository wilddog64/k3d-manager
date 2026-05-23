# Bug: "Extend Your Session" Modal Blocks Delete Sandbox After Open Sandbox Click

**Date:** 2026-05-22
**File:** `playwright/acg_restart.js`
**Symptom:** `acg_restart.js` fails with `page.waitForSelector: Timeout 15000ms exceeded` waiting for `button:has-text("Delete Sandbox")` — the `extend-sandbox-modal` dialog appears after clicking "Open Sandbox" and prevents the sandbox panel from expanding.

## Root Cause

In the "card view → expanded panel" code path (lines ~236–251), the script calls
`_dismissExtendYourSessionDialog(page)` only once — before the button state check at
line 230. But the modal can appear **after** `openBtn.click()` at line 250, triggered by
the panel expand animation. At that point nothing dismisses the modal, so
`waitForSelector('button:has-text("Delete Sandbox")')` at line 251 times out.

```javascript
      await openBtn.click({ force: true });
      // ← "Extend Your Session" modal can appear here
      await page.waitForSelector('button:has-text("Delete Sandbox")', { timeout: 15000 });
      // ↑ FAILS — modal intercepts pointer events; Delete Sandbox never becomes visible
```

## Fix

Add `await _dismissExtendYourSessionDialog(page);` immediately after `openBtn.click()` and
before `waitForSelector`.

### Old (lines ~250–251):
```javascript
      await openBtn.click({ force: true });
      await page.waitForSelector('button:has-text("Delete Sandbox")', { timeout: 15000 });
```

### New:
```javascript
      await openBtn.click({ force: true });
      await _dismissExtendYourSessionDialog(page);
      await page.waitForSelector('button:has-text("Delete Sandbox")', { timeout: 15000 });
```

No other changes. Function body of `_dismissExtendYourSessionDialog` is unchanged.

## Definition of Done

- [ ] One line added to `playwright/acg_restart.js`: `await _dismissExtendYourSessionDialog(page);` between `openBtn.click()` and `waitForSelector`
- [ ] Code change limited to `playwright/acg_restart.js`; CHANGELOG/memory-bank/docs updates may also be required
- [ ] `node --check playwright/acg_restart.js` passes
- [ ] Commit on branch `fix/next-improvements-3`: `fix(acg-restart): dismiss extend-session modal after Open Sandbox click`
- [ ] Push to origin before reporting done

## What NOT to Do

- Do NOT change `_dismissExtendYourSessionDialog` function body
- Do NOT remove or move the existing call at line 230 (covers the "already deleted" path)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside `playwright/acg_restart.js`
- Do NOT commit to `main` — work on `fix/next-improvements-3`
