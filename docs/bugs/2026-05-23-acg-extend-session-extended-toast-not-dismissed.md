# Bug: acg_extend — "Session extended" toast not dismissed before exit

**Branch (lib-acg):** `fix/next-improvements-5`
**File:** `playwright/acg_extend.js`

---

## Problem

After clicking the extend button, `acg_extend.js` logs "Extend action complete (Immediate)."
and returns immediately without dismissing the "Session extended" success toast. The toast
persists on the page after the script exits. When `acg_credentials.js` runs next in the
same Chrome CDP session, the toast (which uses `role="alertdialog"`) intercepts pointer
events on the "Open Sandbox" button.

**Root cause:** The `if (clicked)` branch at lines 177–180 returns without waiting for or
dismissing the toast. Same issue exists at line 358 (non-immediate path). Both paths need a
toast-dismiss step before returning.

---

## Fix

### Change 1 — `playwright/acg_extend.js`: dismiss toast in immediate path

**Exact old block (lines 177–180):**

```javascript
    if (clicked) {
      console.log('Extend action complete (Immediate).');
      return;
    }
```

**Exact new block:**

```javascript
    if (clicked) {
      console.log('Extend action complete (Immediate).');
      // Wait for the toast to appear then dismiss it — it persists across CDP sessions
      // and intercepts clicks in the next script that runs against the same Chrome tab.
      await page.locator('text=/session extended/i').first()
        .waitFor({ state: 'visible', timeout: 5000 }).catch(() => {});
      await page.evaluate(() => {
        const toast = Array.from(document.querySelectorAll(
          '[data-testid="extend-sandbox-modal"], [role="alertdialog"], [role="alert"], [role="status"]'
        )).find(d => (d.innerText || '').match(/session extended|sandbox has been extended/i) && d.offsetParent !== null);
        if (!toast) return;
        const closeBtn = Array.from(toast.querySelectorAll('button'))
          .find(b => /close|dismiss/i.test(b.getAttribute('aria-label') || b.textContent || ''))
          || toast.querySelector('button');
        if (closeBtn) closeBtn.click();
      }).catch(() => {});
      await page.waitForTimeout(500);
      return;
    }
```

---

### Change 2 — `playwright/acg_extend.js`: dismiss toast in non-immediate path

**Exact old block (lines 357–358):**

```javascript
    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
    console.log(`Extend action complete. Current expiry text: ${expiryText}`);
```

**Exact new block:**

```javascript
    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
    console.log(`Extend action complete. Current expiry text: ${expiryText}`);
    // Dismiss "Session extended" toast before exit — same reason as immediate path.
    await page.evaluate(() => {
      const toast = Array.from(document.querySelectorAll(
        '[data-testid="extend-sandbox-modal"], [role="alertdialog"], [role="alert"], [role="status"]'
      )).find(d => (d.innerText || '').match(/session extended|sandbox has been extended/i) && d.offsetParent !== null);
      if (!toast) return;
      const closeBtn = Array.from(toast.querySelectorAll('button'))
        .find(b => /close|dismiss/i.test(b.getAttribute('aria-label') || b.textContent || ''))
        || toast.querySelector('button');
      if (closeBtn) closeBtn.click();
    }).catch(() => {});
    await page.waitForTimeout(500);
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Dismiss "Session extended" toast in immediate path (lines 177–180) and non-immediate path (lines 357–358) before returning |

---

## Rules

- `node --check playwright/acg_extend.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] Immediate path (lines 177–180): `if (clicked)` block updated with toast-dismiss before `return`
- [ ] Non-immediate path (lines 357–358): toast-dismiss added after `console.log('Extend action complete...')`
- [ ] No other functions or files modified
- [ ] `node --check playwright/acg_extend.js` passes
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-extend): dismiss Session extended toast before exit — it persists and blocks next script
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_extend.js`
- Do NOT commit to `main`
- Do NOT change any other function in the file
