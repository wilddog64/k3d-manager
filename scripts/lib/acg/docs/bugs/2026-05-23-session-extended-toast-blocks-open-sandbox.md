# Bug: "Session extended" toast intercepts pointer events — Open Sandbox click fails

**Branch (lib-acg):** `fix/next-improvements-5`
**Files:** `playwright/acg_credentials.js`, `playwright/acg_restart.js`

---

## Problem

After `acg_extend.js` runs successfully, a "Session extended" success toast appears with
`role="alertdialog"` and/or `data-testid="extend-sandbox-modal"`. This toast intercepts
pointer events on the "Open Sandbox" button, causing the 30 s timeout in `acg_credentials.js`:

```
ERROR: locator.click: Timeout 30000ms exceeded.
  - waiting for locator('button:has-text("Open Sandbox")').first()
  - <dialog open="" role="alertdialog" data-testid="extend-sandbox-modal"...>
      intercepts pointer events
```

**Root cause — two gaps:**

1. `_dismissExtendYourSessionDialog` in both files only checks for `"Extend Your Session"`
   text. The success toast contains `"Session extended"` / `"sandbox has been extended"` —
   so the function returns early without dismissing it.

2. `acg_credentials.js` line 502 calls `openButton.click()` with no pre-dismiss and no
   `force: true`. The background watcher runs every 2000 ms — if the toast appears between
   watcher ticks, the click fires while the toast is still blocking.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: expand `_dismissExtendYourSessionDialog`

Add "Session extended" toast dismissal after the existing "Extend Your Session" block.

**Exact old block (lines 259–286) — the complete `_dismissExtendYourSessionDialog` function body:**

```javascript
    const _dismissExtendYourSessionDialog = async () => {
      const _dialogVisible = await page.evaluate(() =>
        Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
          .some(d => (d.innerText || '').includes('Extend Your Session'))
      ).catch(() => false);
      if (!_dialogVisible) return;
      console.error('INFO: "Extend Your Session" dialog detected — clicking Cancel via DOM...');
      // Use DOM click (not Playwright keyboard) — Escape closes the panel, not just the dialog
      await page.evaluate(() => {
        const dialog = Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
          .find(d => (d.innerText || '').includes('Extend Your Session'));
        if (!dialog) return;
        const btns = Array.from(dialog.querySelectorAll('button'));
        // Prefer Cancel/close button; fall back to any non-Extend button
        const dismiss = btns.find(b => /cancel|no thanks|close|dismiss/i.test(b.textContent || b.getAttribute('aria-label') || ''))
          || btns.find(b => !/extend/i.test(b.textContent || ''));
        if (dismiss) dismiss.click();
      }).catch(() => {});
      await page.waitForTimeout(1000);
      const _dialogClosed = await page.waitForFunction(
        () => !Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
          .some(d => (d.innerText || '').includes('Extend Your Session')),
        { timeout: 5000 }
      ).then(() => true).catch(() => false);
      if (!_dialogClosed) {
        console.error('WARN: "Extend Your Session" dialog still visible — continuing anyway');
      }
    };
```

**Exact new block:**

```javascript
    const _dismissExtendYourSessionDialog = async () => {
      const _dialogVisible = await page.evaluate(() =>
        Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
          .some(d => (d.innerText || '').includes('Extend Your Session'))
      ).catch(() => false);
      if (_dialogVisible) {
        console.error('INFO: "Extend Your Session" dialog detected — clicking Cancel via DOM...');
        // Use DOM click (not Playwright keyboard) — Escape closes the panel, not just the dialog
        await page.evaluate(() => {
          const dialog = Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
            .find(d => (d.innerText || '').includes('Extend Your Session'));
          if (!dialog) return;
          const btns = Array.from(dialog.querySelectorAll('button'));
          // Prefer Cancel/close button; fall back to any non-Extend button
          const dismiss = btns.find(b => /cancel|no thanks|close|dismiss/i.test(b.textContent || b.getAttribute('aria-label') || ''))
            || btns.find(b => !/extend/i.test(b.textContent || ''));
          if (dismiss) dismiss.click();
        }).catch(() => {});
        await page.waitForTimeout(1000);
        const _dialogClosed = await page.waitForFunction(
          () => !Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
            .some(d => (d.innerText || '').includes('Extend Your Session')),
          { timeout: 5000 }
        ).then(() => true).catch(() => false);
        if (!_dialogClosed) {
          console.error('WARN: "Extend Your Session" dialog still visible — continuing anyway');
        }
      }
      // Also dismiss "Session extended" success toast — it shares role="alertdialog" and
      // intercepts pointer events on the Open Sandbox button.
      const _toastVisible = await page.evaluate(() =>
        Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="alertdialog"], [role="alert"]'))
          .some(d => (d.innerText || '').match(/session extended|sandbox has been extended/i) && d.offsetParent !== null)
      ).catch(() => false);
      if (_toastVisible) {
        console.error('INFO: "Session extended" toast detected — dismissing...');
        await page.evaluate(() => {
          const toast = Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="alertdialog"], [role="alert"]'))
            .find(d => (d.innerText || '').match(/session extended|sandbox has been extended/i) && d.offsetParent !== null);
          if (!toast) return;
          const closeBtn = Array.from(toast.querySelectorAll('button'))
            .find(b => /close|dismiss/i.test(b.getAttribute('aria-label') || b.textContent || ''))
            || toast.querySelector('button');
          if (closeBtn) closeBtn.click();
        }).catch(() => {});
        await page.waitForTimeout(500);
      }
    };
```

---

### Change 2 — `playwright/acg_credentials.js`: pre-dismiss before Open Sandbox click

**Exact old block (lines 500–503):**

```javascript
      } else if (await openButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        console.error('INFO: Clicking Open Sandbox...');
        await openButton.click();
        await page.waitForTimeout(3000);
```

**Exact new block:**

```javascript
      } else if (await openButton.isVisible({ timeout: 5000 }).catch(() => false)) {
        await _dismissExtendYourSessionDialog();
        console.error('INFO: Clicking Open Sandbox...');
        await openButton.click({ force: true });
        await page.waitForTimeout(3000);
```

---

### Change 3 — `playwright/acg_restart.js`: expand `_dismissExtendYourSessionDialog`

The function in `acg_restart.js` is defined at module scope (lines 31–56). Apply the same
"Session extended" toast handling.

**Exact old block (lines 31–56):**

```javascript
async function _dismissExtendYourSessionDialog(page) {
  const visible = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
      .some(d =>
        (d.innerText || '').includes('Extend Your Session') &&
        d.offsetParent !== null &&
        getComputedStyle(d).display !== 'none'
      )
  ).catch(() => false);
  if (!visible) return;
  console.error('INFO: "Extend Your Session" dialog detected — clicking Cancel via DOM...');
  await page.evaluate(() => {
    const dialog = Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
      .find(d =>
        (d.innerText || '').includes('Extend Your Session') &&
        d.offsetParent !== null &&
        getComputedStyle(d).display !== 'none'
      );
    if (!dialog) return;
    const btns = Array.from(dialog.querySelectorAll('button'));
    const dismiss = btns.find(b => /cancel|no thanks|close|dismiss/i.test(b.textContent || b.getAttribute('aria-label') || ''))
      || btns.find(b => !/extend/i.test(b.textContent || ''));
    if (dismiss) dismiss.click();
  }).catch(() => {});
  await page.waitForTimeout(1000);
}
```

**Exact new block:**

```javascript
async function _dismissExtendYourSessionDialog(page) {
  const visible = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
      .some(d =>
        (d.innerText || '').includes('Extend Your Session') &&
        d.offsetParent !== null &&
        getComputedStyle(d).display !== 'none'
      )
  ).catch(() => false);
  if (visible) {
    console.error('INFO: "Extend Your Session" dialog detected — clicking Cancel via DOM...');
    await page.evaluate(() => {
      const dialog = Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
        .find(d =>
          (d.innerText || '').includes('Extend Your Session') &&
          d.offsetParent !== null &&
          getComputedStyle(d).display !== 'none'
        );
      if (!dialog) return;
      const btns = Array.from(dialog.querySelectorAll('button'));
      const dismiss = btns.find(b => /cancel|no thanks|close|dismiss/i.test(b.textContent || b.getAttribute('aria-label') || ''))
        || btns.find(b => !/extend/i.test(b.textContent || ''));
      if (dismiss) dismiss.click();
    }).catch(() => {});
    await page.waitForTimeout(1000);
  }
  // Also dismiss "Session extended" success toast — it uses role="alertdialog" and
  // intercepts pointer events on the Open Sandbox button.
  const toastVisible = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="alertdialog"], [role="alert"]'))
      .some(d => (d.innerText || '').match(/session extended|sandbox has been extended/i) && d.offsetParent !== null)
  ).catch(() => false);
  if (toastVisible) {
    console.error('INFO: "Session extended" toast detected — dismissing...');
    await page.evaluate(() => {
      const toast = Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="alertdialog"], [role="alert"]'))
        .find(d => (d.innerText || '').match(/session extended|sandbox has been extended/i) && d.offsetParent !== null);
      if (!toast) return;
      const closeBtn = Array.from(toast.querySelectorAll('button'))
        .find(b => /close|dismiss/i.test(b.getAttribute('aria-label') || b.textContent || ''))
        || toast.querySelector('button');
      if (closeBtn) closeBtn.click();
    }).catch(() => {});
    await page.waitForTimeout(500);
  }
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Expand `_dismissExtendYourSessionDialog` to also dismiss "Session extended" toast; add pre-dismiss + `force: true` before Open Sandbox click |
| `playwright/acg_restart.js` | Expand `_dismissExtendYourSessionDialog` to also dismiss "Session extended" toast |

---

## Rules

- `node --check playwright/acg_credentials.js` must pass
- `node --check playwright/acg_restart.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] `acg_credentials.js` `_dismissExtendYourSessionDialog` expanded with toast block
- [ ] `acg_credentials.js` line 500: `_dismissExtendYourSessionDialog()` added before Open Sandbox click; `click({ force: true })` applied
- [ ] `acg_restart.js` `_dismissExtendYourSessionDialog` (lines 31–56) expanded with toast block
- [ ] No other functions or files modified
- [ ] `node --check` passes on both files
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg): dismiss Session extended toast — it shares alertdialog role and blocks Open Sandbox click
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js` and `playwright/acg_restart.js`
- Do NOT commit to `main`
- Do NOT change any other function in either file
