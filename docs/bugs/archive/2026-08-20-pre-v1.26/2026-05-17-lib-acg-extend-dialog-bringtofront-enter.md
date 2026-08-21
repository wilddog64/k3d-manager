# Bug: lib-acg — Cancel button unfindable by any Playwright selector; X close button is always focused

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `playwright/acg_credentials.js` — replace locator-based Cancel click with `page.bringToFront()` + `page.keyboard.press('Enter')` on the already-focused X button

---

## Before You Start

```
git -C ~/src/gitrepo/personal/lib-acg fetch origin
git -C ~/src/gitrepo/personal/lib-acg checkout fix/acg-credentials-extend-dialog
git -C ~/src/gitrepo/personal/lib-acg pull origin fix/acg-credentials-extend-dialog
```

Read this spec in full before touching any file.

---

## Problem

Every Playwright selector tried so far has failed to find the Cancel button:
- `locator('button', { hasText: 'Cancel' })` — TimeoutError (not a native `<button>`)
- `getByRole('button', { name: 'Cancel' })` — TimeoutError (no ARIA role or accessible name mismatch)

The Cancel button in Pluralsight's dialog is a custom React component element that is not
reachable by any standard Playwright selector.

**Key observation confirmed across every test run:** The dialog's **X close button** (top-right
corner) is **always focused** (blue focus ring visible in browser) when the dialog appears.
This is consistent behavior — the dialog's focus trap places focus on the X button when the
dialog opens.

**Fix:** Use `page.bringToFront()` to activate the CDP target tab (making the tab the active
Chrome tab so `Input.dispatchKeyEvent` events are received), then immediately press `Enter`
via CDP. `Enter` on the focused X button triggers the browser's native "activation behavior"
(the browser fires a real, trusted click event on the focused element → React handles it →
dialog closes). No selector is needed; the focus state already points at the dismiss button.

**Why this is different from earlier bringToFront attempts (attempt 5, `19c31a8`):**
- Attempt 5 pressed `Escape` after bringToFront. Chrome may intercept `Escape` at the browser
  UI level before it reaches the page (closing devtools, omnibox, etc.).
- This attempt presses `Enter`, which Chrome never intercepts for its own UI. Enter on a
  focused element is always forwarded to the page's event handlers.
- Attempt 5 then called `page.evaluate()` for `_stillVisible` check immediately after
  bringToFront — that evaluate may have run during a page state transition and returned a
  false "no dialog" result. This spec avoids any `page.evaluate()` between `bringToFront()`
  and the `waitForFunction` check.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: replace locator click with bringToFront + Enter

**Exact old block (lines 379–393, inside `_dismissExtendYourSessionDialog`, after the `_dialogVisible` check):**

```javascript
        console.error('INFO: "Extend Your Session" dialog detected — clicking Cancel...');
        await page.locator('[role="dialog"]')
          .filter({ hasText: 'Extend Your Session' })
          .getByRole('button', { name: 'Cancel' })
          .click({ timeout: 5000 })
          .catch(e => console.error('WARN: Cancel click error:', e.message));
        await page.waitForTimeout(1000);
        const _dialogClosed = await page.waitForFunction(
          () => !Array.from(document.querySelectorAll('[role="dialog"]'))
            .some(d => (d.innerText || '').includes('Extend Your Session')),
          { timeout: 5000 }
        ).then(() => true).catch(() => false);
        if (!_dialogClosed) {
          console.error('WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing');
        }
```

**Exact new block:**

```javascript
        console.error('INFO: "Extend Your Session" dialog detected — activating tab and pressing Enter on focused close button...');
        await page.bringToFront();
        await page.keyboard.press('Enter').catch(() => {});
        await page.waitForTimeout(1000);
        const _dialogClosed = await page.waitForFunction(
          () => !Array.from(document.querySelectorAll('[role="dialog"]'))
            .some(d => (d.innerText || '').includes('Extend Your Session')),
          { timeout: 5000 }
        ).then(() => true).catch(() => false);
        if (!_dialogClosed) {
          console.error('WARN: "Extend Your Session" dialog still visible — credentials populate on either Cancel or Extend; continuing');
        }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Replace locator-based Cancel click with `page.bringToFront()` + `page.keyboard.press('Enter')` |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- No other files modified

---

## Definition of Done

- [ ] Locator chain (`locator('[role="dialog"]')...getByRole(...)...click(...)`) removed entirely
- [ ] `await page.bringToFront();` present immediately after the INFO log
- [ ] `await page.keyboard.press('Enter').catch(() => {});` present immediately after bringToFront
- [ ] `await page.waitForTimeout(1000);` present after the Enter press
- [ ] No `page.evaluate()` call between `bringToFront()` and `waitForFunction`
- [ ] `waitForFunction` timeout remains 5000
- [ ] WARN + continue on timeout (no `process.exit(1)`)
- [ ] INFO log says `"activating tab and pressing Enter on focused close button..."`
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat` output

**Commit message (exact):**
```
fix(acg): bringToFront then Enter on focused close button to dismiss extend dialog
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT restore `process.exit(1)`
- Do NOT use any locator/selector — the X button is found by focus state, not by selector
- Do NOT call `page.evaluate()` between `bringToFront()` and `waitForFunction` — this causes page state desync
- Do NOT press `Escape` — Chrome may intercept it at the browser UI level before it reaches the page
- Do NOT touch `acg_extend.js`
