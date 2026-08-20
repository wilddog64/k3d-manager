# Bug: lib-acg — `bringToFront()` dismisses iTerm2 hotkey window and resets page focus; Enter never reaches dialog X button

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `playwright/acg_credentials.js` — replace `bringToFront()` + `keyboard.press('Enter')` with AppleScript native OS click on the X button using screen coordinates from `window.screenX/Y`

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

`page.bringToFront()` sends `Target.activateTarget` which brings Chrome to the OS foreground.
This has two unacceptable side effects:
1. **iTerm2 hotkey window auto-dismisses** — iTerm2 hotkey windows hide whenever another app takes OS focus.
2. **Page focus resets** — when Chrome gains OS focus, a `focus` event fires on the page. The dialog's React focus trap re-runs, resetting `document.activeElement` away from the X button before `page.keyboard.press('Enter')` arrives. Enter lands on `document.body` (no activation behavior) instead of the X button.

`bringToFront()` cannot be used in this workflow.

**Root cause of all keyboard/mouse CDP failures (consolidated):**
- CDP keyboard events (`Input.dispatchKeyEvent`) require the Chrome tab to be the active Chrome tab — without `bringToFront()`, they are silently dropped.
- CDP mouse events (`Input.dispatchMouseEvent`) fail for this specific dialog — the Cancel button cannot be found by any Playwright selector (`button` tag, `getByRole`), meaning it is a custom React component element with no standard ARIA role.
- `page.evaluate()` + `element.click()` / `dispatchEvent()` generate `isTrusted: false` events — React ignores them.

**Fix:** Use `page.evaluate()` (no bringToFront needed) to compute the **screen coordinates** of the X button using `window.screenX`, `window.screenY`, and `window.outerHeight - window.innerHeight` (Chrome UI chrome height). Then use Node.js `child_process.execSync` to run an AppleScript `System Events` click at those screen coordinates. This generates a real, `isTrusted: true` native OS click that goes directly to whatever is at those screen coordinates — no focus change, no bringToFront, no iTerm2 disruption.

`window.screenX/Y` returns the Chrome window's screen position. `window.outerHeight - window.innerHeight` returns Chrome's UI chrome height (title bar + tab bar + toolbar). So `screenY = window.screenY + (window.outerHeight - window.innerHeight) + viewportY` gives the exact screen Y of the element.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: replace bringToFront+Enter with AppleScript screen-coordinate click

**Exact old block (lines 379–390, inside `_dismissExtendYourSessionDialog`, after the `_dialogVisible` check):**

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

**Exact new block:**

```javascript
        console.error('INFO: "Extend Your Session" dialog detected — clicking close button via native OS event...');
        const _screenCoords = await page.evaluate(() => {
          const dialog = Array.from(document.querySelectorAll('[role="dialog"]'))
            .find(d => (d.innerText || '').includes('Extend Your Session'));
          if (!dialog) return null;
          const btn = dialog.querySelector('button');
          if (!btn) return null;
          const rect = btn.getBoundingClientRect();
          const uiH = window.outerHeight - window.innerHeight;
          return {
            x: Math.round(window.screenX + rect.left + rect.width / 2),
            y: Math.round(window.screenY + uiH + rect.top + rect.height / 2),
          };
        }).catch(() => null);
        if (_screenCoords) {
          require('child_process').execSync(
            `osascript -e 'tell application "System Events" to click at {${_screenCoords.x}, ${_screenCoords.y}}'`
          , { stdio: 'ignore' });
        }
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
| `playwright/acg_credentials.js` | Replace `bringToFront()` + `keyboard.press('Enter')` with AppleScript `System Events` click at computed screen coordinates |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- No other files modified

---

## Definition of Done

- [ ] `await page.bringToFront();` removed entirely
- [ ] `await page.keyboard.press('Enter').catch(() => {});` removed entirely
- [ ] `page.evaluate()` computes `_screenCoords` using `window.screenX`, `window.screenY`, `window.outerHeight - window.innerHeight`, and `getBoundingClientRect()` on `dialog.querySelector('button')` (first button = X close button)
- [ ] `require('child_process').execSync(...)` calls `osascript` with `tell application "System Events" to click at {x, y}` — `{ stdio: 'ignore' }` passed to suppress output
- [ ] `_screenCoords` is guarded: `if (_screenCoords) { ... }` — no click attempt if coords unavailable
- [ ] `.execSync(...)` is NOT wrapped in try/catch — if `System Events` fails (no Accessibility permission), the error propagates to the outer `.catch()` at call site; the `waitForTimeout` + `waitForFunction` + WARN still run after
- [ ] `await page.waitForTimeout(1000)` present after the click block (unconditional)
- [ ] `waitForFunction` timeout remains 5000
- [ ] WARN + continue on timeout (no `process.exit(1)`)
- [ ] INFO log says `"clicking close button via native OS event..."`
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat` output

**Commit message (exact):**
```
fix(acg): click extend dialog close button via AppleScript screen-coordinate click
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT restore `process.exit(1)`
- Do NOT use `page.bringToFront()` — dismisses iTerm2 hotkey window and resets page focus
- Do NOT use `page.keyboard.press()` without bringToFront — CDP key events require active tab
- Do NOT use any Playwright locator to find the Cancel button — it is not findable by any selector
- Do NOT wrap `execSync` in try/catch — let errors surface; WARN path handles dialog still visible
- Do NOT touch `acg_extend.js`
