# Bug: toast dismiss uses button.first() — clicks action button instead of close X

**Branch (lib-acg):** `fix/next-improvements-5`
**Files:** `playwright/acg_extend.js`, `playwright/acg_restart.js`

---

## Problem

In all `addLocatorHandler` toast dismiss blocks and the two explicit toast dismiss blocks
in `acg_extend.js`, the dismiss code uses:

```javascript
await _tb.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
  .click({ force: true }).catch(() => {});
```

Pando toast notifications can have two buttons: an **action button** ("View Sandbox",
"Open") BEFORE the **close X** button. `.locator('button').first()` hits the action
button — not the X — which navigates away and breaks the current flow.

**Fix strategy:** Replace the XPath ancestor button click with `page.keyboard.press('Escape')`.
Escape dismisses Pando/notification toasts universally without targeting any button.

---

## Fix

### Change 1 — `playwright/acg_extend.js` addLocatorHandler (lines 148–153)

**Exact old block:**

```javascript
    async () => {
        const _tb = page.getByText('Your sandbox has been extended.');
        await _tb.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
          .click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
```

**Exact new block:**

```javascript
    async () => {
        await page.keyboard.press('Escape').catch(() => {});
        await page.waitForTimeout(300);
      }
```

---

### Change 2 — `playwright/acg_extend.js` immediate path (lines 195–198)

**Exact old block:**

```javascript
        console.error('INFO: Dismissing "Session extended" toast...');
        await _toastBody.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
          .click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
      return;
```

**Exact new block:**

```javascript
        console.error('INFO: Dismissing "Session extended" toast...');
        await page.keyboard.press('Escape').catch(() => {});
        await page.waitForTimeout(300);
      }
      return;
```

---

### Change 3 — `playwright/acg_extend.js` non-immediate path (lines 383–387)

**Exact old block:**

```javascript
      console.error('INFO: Dismissing "Session extended" toast...');
      await _toastBody.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
        .click({ force: true }).catch(() => {});
      await page.waitForTimeout(300);
    }
```

**Exact new block:**

```javascript
      console.error('INFO: Dismissing "Session extended" toast...');
      await page.keyboard.press('Escape').catch(() => {});
      await page.waitForTimeout(300);
    }
```

---

### Change 4 — `playwright/acg_restart.js` addLocatorHandler (lines 221–225)

**Exact old block:**

```javascript
    async () => {
        const _tb = page.getByText('Your sandbox has been extended.');
        await _tb.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
          .click({ force: true }).catch(() => {});
        await page.waitForTimeout(300);
      }
```

**Exact new block:**

```javascript
    async () => {
        await page.keyboard.press('Escape').catch(() => {});
        await page.waitForTimeout(300);
      }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_extend.js` | Replace XPath button.first() with Escape at 3 locations (addLocatorHandler, immediate path, non-immediate path) |
| `playwright/acg_restart.js` | Replace XPath button.first() with Escape in addLocatorHandler |

---

## Rules

- `node --check playwright/acg_extend.js` must pass
- `node --check playwright/acg_restart.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] `acg_extend.js` addLocatorHandler: `_tb.locator(...).button.first().click()` replaced with `page.keyboard.press('Escape')`
- [ ] `acg_extend.js` immediate path: same replacement
- [ ] `acg_extend.js` non-immediate path: same replacement
- [ ] `acg_restart.js` addLocatorHandler: same replacement
- [ ] No other functions or files modified
- [ ] `node --check` passes on both files
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-extend,acg-restart): replace button.first() toast dismiss with Escape — action button click caused navigation
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_extend.js` and `playwright/acg_restart.js`
- Do NOT commit to `main`
- Do NOT change any other function in either file
