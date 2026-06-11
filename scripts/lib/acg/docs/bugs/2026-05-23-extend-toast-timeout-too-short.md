# Fix: acg_extend.js toast dismiss — timeout too short for async server response

**Branch (lib-acg):** `fix/next-improvements-5`
**File:** `playwright/acg_extend.js`

---

## Problem

The "Session extended" toast appears AFTER the extend API call completes server-side.
The extend button click succeeds immediately (clicked = true), but the server processes
the request asynchronously and posts the toast seconds later.

- **Immediate path** (line 192): `isVisible({ timeout: 5000 })` — 5s is not enough.
  Log shows "Extend action complete (Immediate)." with no subsequent dismiss message,
  meaning the toast arrived after the window closed.
- **Non-immediate path** (line 380): `isVisible({ timeout: 3000 })` — 3s, also too short.

Neither path added a pre-wait before the check, so the full window is only as long as
the timeout. The fix adds a 2s pre-wait (time for the network round-trip) and increases
the detection window to 15s (immediate) and 10s (non-immediate).

---

## Fix

### Change 1 — immediate path toast dismiss (lines 187–198)

**Exact old block:**

```javascript
    if (clicked) {
      console.log('Extend action complete (Immediate).');
      // Dismiss the "Session extended" toast — anchor on the leaf body text then walk up
      // to the closest ancestor that owns a button (the toast card, not the whole page).
      const _toastBody = page.getByText('Your sandbox has been extended.');
      if (await _toastBody.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Dismissing "Session extended" toast...');
        await _toastBody.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
          .click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
      return;
    }
```

**Exact new block:**

```javascript
    if (clicked) {
      console.log('Extend action complete (Immediate).');
      // Wait for the extend API response before checking — the toast is posted asynchronously.
      await page.waitForTimeout(2000);
      const _toastBody = page.getByText('Your sandbox has been extended.');
      if (await _toastBody.isVisible({ timeout: 15000 }).catch(() => false)) {
        console.error('INFO: Dismissing "Session extended" toast...');
        await _toastBody.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
          .click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
      return;
    }
```

---

### Change 2 — non-immediate path toast dismiss (lines 379–385)

**Exact old block:**

```javascript
    const _toastBody = page.getByText('Your sandbox has been extended.');
    if (await _toastBody.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" toast...');
      await _toastBody.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
        .click({ force: true }).catch(() => {});
      await page.waitForTimeout(300);
    }
```

**Exact new block:**

```javascript
    await page.waitForTimeout(2000);
    const _toastBody = page.getByText('Your sandbox has been extended.');
    if (await _toastBody.isVisible({ timeout: 10000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" toast...');
      await _toastBody.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
        .click({ force: true }).catch(() => {});
      await page.waitForTimeout(300);
    }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Add 2s pre-wait; increase timeout: 5000→15000 (immediate), 3000→10000 (non-immediate) |

---

## Rules

- `node --check playwright/acg_extend.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] Immediate path: `await page.waitForTimeout(2000)` added before `getByText`; timeout changed from 5000 to 15000
- [ ] Non-immediate path: `await page.waitForTimeout(2000)` added before `getByText`; timeout changed from 3000 to 10000
- [ ] No other functions or files modified
- [ ] `node --check playwright/acg_extend.js` passes
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-extend): increase toast detection timeout — async server response arrives after 5s window
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_extend.js`
- Do NOT commit to `main`
- Do NOT change the addLocatorHandler or any other function
