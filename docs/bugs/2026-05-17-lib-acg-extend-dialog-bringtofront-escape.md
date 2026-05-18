# Bug: lib-acg — Escape key not reaching dialog; page lacks CDP focus in background session

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `playwright/acg_credentials.js` — add `page.bringToFront()` before Escape; replace force-click fallback with `button.focus()` + `page.keyboard.press('Enter')`

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

`page.keyboard.press('Escape')` is sent but the dialog does not close. Manually pressing
the physical Escape key DOES dismiss the dialog — confirming the dialog handles Escape
correctly. The script's CDP keyboard event is not reaching the dialog.

**Root cause:** In a CDP-attached session (connecting to an existing Chrome via
`--remote-debugging-port=9222`), `Input.dispatchKeyEvent` requires the target tab to be
the active tab in the browser. When Chrome is in the background or a different tab is
active, the keyboard event is dispatched but silently dropped. `page.bringToFront()` sends
`Target.activateTarget` via CDP, which promotes the tab to the foreground at the browser
level — after this, `page.keyboard.press()` lands correctly.

The existing `force: true` locator click fallback also uses `Input.dispatchMouseEvent` via
CDP, which has the same focus requirement. Replacing it with `button.focus()` in
`page.evaluate()` (sets DOM focus, requires no CDP) + `page.keyboard.press('Enter')` (CDP
keyboard event on the now-active tab → browser fires a native click on the focused button
→ React handles it) is fully keyboard-driven and avoids the mouse-event focus problem.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: add `bringToFront` + replace fallback

**Exact old block (inside `_dismissExtendYourSessionDialog`, after the `_dialogVisible` check):**

```javascript
        console.error('INFO: "Extend Your Session" dialog detected — dismissing via Escape key...');
        await page.keyboard.press('Escape').catch(() => {});
        await page.waitForTimeout(1000);
        const _stillVisible = await page.evaluate(() =>
          Array.from(document.querySelectorAll('[role="dialog"]'))
            .some(d => (d.innerText || '').includes('Extend Your Session'))
        ).catch(() => false);
        if (_stillVisible) {
          await page.locator('[role="dialog"]').filter({ hasText: 'Extend Your Session' }).locator('button').first().click({ force: true, timeout: 3000 }).catch(() => {});
          await page.waitForTimeout(1000);
        }
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
        console.error('INFO: "Extend Your Session" dialog detected — dismissing via Escape key...');
        await page.bringToFront();
        await page.keyboard.press('Escape').catch(() => {});
        await page.waitForTimeout(1000);
        const _stillVisible = await page.evaluate(() =>
          Array.from(document.querySelectorAll('[role="dialog"]'))
            .some(d => (d.innerText || '').includes('Extend Your Session'))
        ).catch(() => false);
        if (_stillVisible) {
          await page.evaluate(() => {
            const dialog = Array.from(document.querySelectorAll('[role="dialog"]'))
              .find(d => (d.innerText || '').includes('Extend Your Session'));
            if (!dialog) return;
            const btn = Array.from(dialog.querySelectorAll('button'))
              .find(b => (b.textContent || '').trim() === 'Cancel') || dialog.querySelector('button');
            if (btn) btn.focus();
          }).catch(() => {});
          await page.keyboard.press('Enter').catch(() => {});
          await page.waitForTimeout(1000);
        }
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
| `playwright/acg_credentials.js` | Add `page.bringToFront()` before Escape; replace `force: true` locator click with `button.focus()` + `page.keyboard.press('Enter')` |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- No other files modified

---

## Definition of Done

- [ ] `await page.bringToFront();` added immediately before `page.keyboard.press('Escape')`
- [ ] `force: true` locator click block removed entirely
- [ ] Fallback is now: `page.evaluate(() => { ... btn.focus(); })` + `page.keyboard.press('Enter')`
- [ ] `waitForFunction` timeout remains 5000
- [ ] WARN + continue on timeout (no `process.exit(1)`)
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat` output

**Commit message (exact):**
```
fix(acg): bringToFront before Escape; focus+Enter fallback for extend dialog
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT restore `process.exit(1)`
- Do NOT use `page.mouse.click()` or `locator.click({ force: true })` — mouse events have the same focus-state problem
- Do NOT touch `acg_extend.js`
