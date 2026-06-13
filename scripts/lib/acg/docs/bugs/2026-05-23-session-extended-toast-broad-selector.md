# Fix: "Session extended" toast — `:has-text()` selector too broad, misses close button

**Branch (lib-acg):** `fix/next-improvements-5`
**Files:** `playwright/acg_extend.js`, `playwright/acg_credentials.js`, `playwright/acg_restart.js`

---

## Problem

The current `:has-text("Your sandbox has been extended.")` selector matches every ancestor
element (body, html, divs) that contains that text. `.last()` gives the most-nested match,
but that element also contains the sandbox card buttons ("Open Sandbox", "Learn More"), so
`.locator('button').first()` clicks the wrong button — the dismiss silently no-ops and the
toast remains on the page.

A second gap: `addLocatorHandler` never fires during `_waitForCredentials` because that
loop uses only DOM queries (no pointer actions). `openButton.click({ force: true })` also
bypasses the handler because `force: true` skips Playwright's actionability checks.

**Fix strategy:**
- Replace `:has-text` container locator with `getByText` on the body text, then navigate
  to the closest ancestor that has a button using XPath — this anchors on a leaf text node
  rather than a broad container, so the first ancestor with a button is the toast card.
- Add an explicit toast check inside `_waitForCredentials` loop so the toast is always
  dismissed during the credential polling phase, independent of addLocatorHandler.
- Update `addLocatorHandler` trigger and handler in all three scripts to use the same
  improved locator.

---

## Fix

### Change 1 — `playwright/acg_extend.js`: fix immediate-path toast dismiss (lines 187–197)

**Exact old block:**

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

**Exact new block:**

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

---

### Change 2 — `playwright/acg_extend.js`: fix non-immediate-path toast dismiss (lines 376–384)

**Exact old block:**

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

**Exact new block:**

```javascript
    const expiryText = await page.locator('text=/expires/i').first().textContent().catch(() => 'unknown');
    console.log(`Extend action complete. Current expiry text: ${expiryText}`);
    // Dismiss "Session extended" toast — same anchor-on-leaf approach as immediate path.
    const _toastBody = page.getByText('Your sandbox has been extended.');
    if (await _toastBody.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" toast...');
      await _toastBody.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
        .click({ force: true }).catch(() => {});
      await page.waitForTimeout(300);
    }
```

---

### Change 3 — `playwright/acg_extend.js`: fix `addLocatorHandler` trigger + handler (lines 145–154)

**Exact old block:**

```javascript
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

**Exact new block:**

```javascript
    // Auto-dismiss "Session extended" toast whenever it blocks an action — fires on-demand, not a poll loop.
    await page.addLocatorHandler(
      page.getByText('Your sandbox has been extended.').first(),
      async () => {
        const _tb = page.getByText('Your sandbox has been extended.');
        await _tb.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
          .click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
    );
```

---

### Change 4 — `playwright/acg_credentials.js`: fix `addLocatorHandler` trigger + handler (lines 313–322)

**Exact old block:**

```javascript
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

**Exact new block:**

```javascript
    // Auto-dismiss "Session extended" toast whenever it blocks an action — fires on-demand, not a poll loop.
    await page.addLocatorHandler(
      page.getByText('Your sandbox has been extended.').first(),
      async () => {
        const _tb = page.getByText('Your sandbox has been extended.');
        await _tb.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
          .click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
    );
```

---

### Change 5 — `playwright/acg_credentials.js`: add toast dismiss inside `_waitForCredentials` loop

Insert immediately after the `_dialogUp` block (after the `continue;` on line 497, before `const inputs`).

**Exact old block (lines 498–499):**

```javascript
          const inputs = page.locator('input[aria-label="Copyable input"]');
```

**Exact new block:**

```javascript
          // Dismiss "Session extended" toast — addLocatorHandler does not fire during
          // DOM-only polling; force:true clicks also bypass it. Check explicitly each tick.
          const _sessionToast = page.getByText('Your sandbox has been extended.');
          if (await _sessionToast.isVisible({ timeout: 200 }).catch(() => false)) {
            console.error('INFO: "Session extended" toast blocking credential wait — dismissing...');
            await _sessionToast.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
              .click({ force: true }).catch(() => {});
            await page.waitForTimeout(300);
          }
          const inputs = page.locator('input[aria-label="Copyable input"]');
```

---

### Change 6 — `playwright/acg_restart.js`: fix `addLocatorHandler` trigger + handler (lines 218–227)

**Exact old block:**

```javascript
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

**Exact new block:**

```javascript
    // Auto-dismiss "Session extended" toast whenever it blocks an action — fires on-demand, not a poll loop.
    await page.addLocatorHandler(
      page.getByText('Your sandbox has been extended.').first(),
      async () => {
        const _tb = page.getByText('Your sandbox has been extended.');
        await _tb.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
          .click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
    );
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Changes 1, 2, 3: fix immediate + non-immediate toast dismiss; fix addLocatorHandler |
| `playwright/acg_credentials.js` | Changes 4, 5: fix addLocatorHandler; add explicit dismiss inside _waitForCredentials |
| `playwright/acg_restart.js` | Change 6: fix addLocatorHandler |

---

## Rules

- `node --check playwright/acg_extend.js` must pass
- `node --check playwright/acg_credentials.js` must pass
- `node --check playwright/acg_restart.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] `acg_extend.js` immediate path: `:has-text` replaced with `getByText` + XPath ancestor (Change 1)
- [ ] `acg_extend.js` non-immediate path: same replacement (Change 2)
- [ ] `acg_extend.js` `addLocatorHandler`: trigger + handler updated (Change 3)
- [ ] `acg_credentials.js` `addLocatorHandler`: trigger + handler updated (Change 4)
- [ ] `acg_credentials.js` `_waitForCredentials`: explicit toast dismiss added before `const inputs` (Change 5)
- [ ] `acg_restart.js` `addLocatorHandler`: trigger + handler updated (Change 6)
- [ ] No other functions or files modified
- [ ] `node --check` passes on all three files
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg): anchor toast dismiss on leaf text + XPath ancestor — broad :has-text selector clicked wrong button
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed targets
- Do NOT commit to `main`
- Do NOT change any other function in any file
