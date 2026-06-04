# Fix: remove toast dismiss from _waitForCredentials — DOM queries are never blocked by overlays

**Branch (lib-acg):** `fix/next-improvements-5`
**File:** `playwright/acg_credentials.js`

---

## Problem

The toast dismiss block added inside `_waitForCredentials` (bf57ee1) is itself causing the
420s hang. `_waitForCredentials` uses only DOM queries (`inputs.count()`, `.inputValue()`).
Playwright DOM queries go through CDP — visual overlays (toasts, modals) cannot block them.
The "Session extended" toast never prevented `inputs.count()` from returning the correct
count. The dismissal attempt is the actual culprit:

- **XPath button click** (before bf57ee1): clicked the Pando toast's action button
  ("View Sandbox" or equivalent), navigating away from the credential panel.
- **Escape key** (after escape-dismiss spec): Escape closes focused panels in most
  browsers — it closes the credential slide-over panel, removing all inputs from the DOM.

In both cases the credential panel disappears, `inputs.count()` returns 0 for the remaining
420s, and the loop times out silently.

The `addLocatorHandler` registered at line 312 already handles the toast for pointer actions.
DOM polling does not need and must not have its own dismiss path.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: remove toast dismiss from `_waitForCredentials`

**Exact old block (lines 499–507 after bf57ee1):**

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

**Exact new block:**

```javascript
          const inputs = page.locator('input[aria-label="Copyable input"]');
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Remove 8-line toast dismiss block from `_waitForCredentials`; keep `const inputs` line |

---

## Rules

- `node --check playwright/acg_credentials.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required
- The `addLocatorHandler` at line 312 must remain untouched

---

## Definition of Done

- [ ] The 8-line toast dismiss block (lines 499–507 in bf57ee1 state) is removed
- [ ] `const inputs = page.locator('input[aria-label="Copyable input"]');` remains in place
- [ ] `addLocatorHandler` at line 312 is unchanged
- [ ] No other functions or files modified
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-credentials): remove toast dismiss from _waitForCredentials — DOM queries are never blocked by overlays
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main`
- Do NOT remove or change the `addLocatorHandler` block

---

## Why This Is Correct

Playwright DOM queries (`.count()`, `.inputValue()`, `.evaluate()`) go through the Chrome
DevTools Protocol directly. They are not affected by what is visually rendered on screen.
Only pointer actions (`.click()`, `.hover()`, `.fill()`) are blocked by overlays. The
`addLocatorHandler` at line 312 handles the toast for pointer actions. The polling loop
needs no toast logic.
