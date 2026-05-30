# Fix: "Session extended" toast — Escape dismiss instead of XPath ancestor button click

**Branch (lib-acg):** `fix/next-improvements-5`
**File:** `playwright/acg_credentials.js`

---

## Problem

Inside `_waitForCredentials`, the current toast dismiss uses:
```javascript
await _sessionToast.locator('xpath=ancestor::*[.//button][1]').locator('button').first()
  .click({ force: true }).catch(() => {});
```

Pando toast notifications sometimes have two buttons: an action button ("View Sandbox",
"Open") **and** a close X button. `.locator('button').first()` clicks the **action** button,
not the X. The action button navigates away or changes the page panel state — the credential
inputs then disappear and the `_waitForCredentials` loop times out silently after 420s.

Additionally, after the dismiss attempt there is no `continue` — the loop immediately
falls through to check for inputs in a potentially unstable page state.

**Fix strategy:**
- Replace the XPath ancestor click with `page.keyboard.press('Escape')`. Escape dismisses
  Pando/notification toasts universally without targeting any button — no wrong-button risk.
- Add `continue` after the dismiss+wait so the loop re-evaluates page state cleanly from
  the top before checking for credential inputs.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: Escape dismiss + continue (lines 499–507)

**Exact old block:**

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
          // Dismiss "Session extended" toast — addLocatorHandler does not fire during
          // DOM-only polling; force:true clicks also bypass it. Check explicitly each tick.
          // Use Escape (not a button click) — Pando toasts may have an action button before
          // the close X; clicking button.first() navigates away and kills the credential panel.
          const _sessionToast = page.getByText('Your sandbox has been extended.');
          if (await _sessionToast.isVisible({ timeout: 200 }).catch(() => false)) {
            console.error('INFO: "Session extended" toast blocking credential wait — dismissing...');
            await page.keyboard.press('Escape');
            await page.waitForTimeout(300);
            continue;
          }
          const inputs = page.locator('input[aria-label="Copyable input"]');
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Replace XPath ancestor button click with `Escape` key; add `continue` after dismiss |

---

## Rules

- `node --check playwright/acg_credentials.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] `_waitForCredentials` toast dismiss uses `page.keyboard.press('Escape')` (not XPath button click)
- [ ] `continue` added after the dismiss+wait
- [ ] No other functions or files modified
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-credentials): use Escape to dismiss Session extended toast — action button click killed credential panel
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main`
- Do NOT change the addLocatorHandler or any other function
