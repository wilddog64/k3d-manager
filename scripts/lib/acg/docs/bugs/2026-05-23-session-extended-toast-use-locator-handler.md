# Fix: "Session extended" toast — replace DOM evaluate with Playwright locator + addLocatorHandler

**Branch (lib-acg):** `fix/next-improvements-5`
**Files:** `playwright/acg_extend.js`, `playwright/acg_credentials.js`, `playwright/acg_restart.js`

---

## Problem

The current dismiss logic uses `page.evaluate()` with ARIA role selectors
(`[role="alertdialog"]`, `[role="alert"]`, `[role="status"]`). The Pluralsight "Session
extended" toast is a Pando design system component that uses none of these roles — so
the selector never matches and the toast is never dismissed.

Two fixes are required:

1. **`acg_extend.js` immediate + non-immediate paths** — replace `page.evaluate` DOM click
   with a Playwright locator that targets the toast by its unique body text and clicks the
   ✕ button inside it.

2. **All three scripts** — add `page.addLocatorHandler()` so Playwright automatically
   dismisses the toast whenever it appears and blocks an action, without any polling loop
   or timing window.

`addLocatorHandler` is Playwright's built-in mechanism for overlays: it fires on-demand
when the registered locator intercepts a pointer action — not a poll loop.

---

## Fix

### Change 1 — `playwright/acg_extend.js`: replace DOM evaluate in immediate path

**Exact old block (lines 177–194):**

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

**Exact new block:**

```javascript
    if (clicked) {
      console.log('Extend action complete (Immediate).');
      // Dismiss the "Session extended" toast if it appears — it persists across CDP sessions
      // and intercepts clicks in the next script. Use Playwright locator (not DOM evaluate)
      // because the Pando toast component uses no standard ARIA role.
      const _toastClose = page.locator(':has-text("Your sandbox has been extended.")')
        .filter({ has: page.locator('button') }).last().locator('button').first();
      if (await _toastClose.isVisible({ timeout: 5000 }).catch(() => false)) {
        await _toastClose.click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
      return;
    }
```

---

### Change 2 — `playwright/acg_extend.js`: replace DOM evaluate in non-immediate path

**Exact old block (lines 372–385):**

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

**Exact new block:**

```javascript
    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
    console.log(`Extend action complete. Current expiry text: ${expiryText}`);
    // Dismiss "Session extended" toast — same reason as immediate path.
    const _toastClose = page.locator(':has-text("Your sandbox has been extended.")')
      .filter({ has: page.locator('button') }).last().locator('button').first();
    if (await _toastClose.isVisible({ timeout: 3000 }).catch(() => false)) {
      await _toastClose.click({ force: true }).catch(() => {});
      await page.waitForTimeout(300);
    }
```

---

### Change 3 — `playwright/acg_extend.js`: add `addLocatorHandler` after early-exit check

Insert immediately after the closing `}` of the `if (await page.locator('text="Session extended"')...)` block (after line 144).

**Exact old block (lines 140–145):**

```javascript
    // If "Session extended" toast is already visible, extension already succeeded — return so finally runs.
    if (await page.locator('text="Session extended"').first().isVisible({ timeout: 2000 }).catch(() => false)) {
      console.error('INFO: "Session extended" toast already visible — extension already succeeded. Exiting.');
      return;
    }
```

**Exact new block:**

```javascript
    // If "Session extended" toast is already visible, extension already succeeded — return so finally runs.
    if (await page.locator('text="Session extended"').first().isVisible({ timeout: 2000 }).catch(() => false)) {
      console.error('INFO: "Session extended" toast already visible — extension already succeeded. Exiting.');
      return;
    }
    // Auto-dismiss "Session extended" toast whenever it blocks an action — fires on-demand, not a poll loop.
    await page.addLocatorHandler(
      page.locator(':has-text("Your sandbox has been extended.")').filter({ has: page.locator('button') }).last(),
      async () => {
        await page.locator(':has-text("Your sandbox has been extended.")')
          .filter({ has: page.locator('button') }).last()
          .locator('button').first().click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
    );
```

---

### Change 4 — `playwright/acg_credentials.js`: add `addLocatorHandler` after watcher start

Insert immediately after `_startExtendDialogWatcher()` at line 312.

**Exact old block (lines 308–312):**

```javascript
    const _startExtendDialogWatcher = () => {
      const _poll = async () => { while (true) { await _dismissExtendYourSessionDialog(); await page.waitForTimeout(2000); } };
      _poll().catch(() => {});
    };
    _startExtendDialogWatcher();
```

**Exact new block:**

```javascript
    const _startExtendDialogWatcher = () => {
      const _poll = async () => { while (true) { await _dismissExtendYourSessionDialog(); await page.waitForTimeout(2000); } };
      _poll().catch(() => {});
    };
    _startExtendDialogWatcher();
    // Auto-dismiss "Session extended" toast whenever it blocks an action — fires on-demand, not a poll loop.
    await page.addLocatorHandler(
      page.locator(':has-text("Your sandbox has been extended.")').filter({ has: page.locator('button') }).last(),
      async () => {
        await page.locator(':has-text("Your sandbox has been extended.")')
          .filter({ has: page.locator('button') }).last()
          .locator('button').first().click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
    );
```

---

### Change 5 — `playwright/acg_restart.js`: add `addLocatorHandler` after watcher start

Insert immediately after `_startExtendDialogWatcher(page)` at line 217.

**Exact old block (lines 217–219):**

```javascript
    _startExtendDialogWatcher(page);

    // Navigate to sandbox listing if not already there
```

**Exact new block:**

```javascript
    _startExtendDialogWatcher(page);
    // Auto-dismiss "Session extended" toast whenever it blocks an action — fires on-demand, not a poll loop.
    await page.addLocatorHandler(
      page.locator(':has-text("Your sandbox has been extended.")').filter({ has: page.locator('button') }).last(),
      async () => {
        await page.locator(':has-text("Your sandbox has been extended.")')
          .filter({ has: page.locator('button') }).last()
          .locator('button').first().click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
    );

    // Navigate to sandbox listing if not already there
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Changes 1, 2, 3: replace DOM evaluate with Playwright locator in both paths; add `addLocatorHandler` |
| `playwright/acg_credentials.js` | Change 4: add `addLocatorHandler` after `_startExtendDialogWatcher()` |
| `playwright/acg_restart.js` | Change 5: add `addLocatorHandler` after `_startExtendDialogWatcher(page)` |

---

## Rules

- `node --check playwright/acg_extend.js` must pass
- `node --check playwright/acg_credentials.js` must pass
- `node --check playwright/acg_restart.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] `acg_extend.js` immediate path: DOM evaluate block replaced with Playwright locator (Change 1)
- [ ] `acg_extend.js` non-immediate path: DOM evaluate block replaced with Playwright locator (Change 2)
- [ ] `acg_extend.js`: `addLocatorHandler` added after early-exit check (Change 3)
- [ ] `acg_credentials.js`: `addLocatorHandler` added after `_startExtendDialogWatcher()` (Change 4)
- [ ] `acg_restart.js`: `addLocatorHandler` added after `_startExtendDialogWatcher(page)` (Change 5)
- [ ] No other functions or files modified
- [ ] `node --check` passes on all three files
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg): replace DOM evaluate toast dismiss with Playwright locator + addLocatorHandler
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed targets
- Do NOT commit to `main`
- Do NOT change any other function in any file
