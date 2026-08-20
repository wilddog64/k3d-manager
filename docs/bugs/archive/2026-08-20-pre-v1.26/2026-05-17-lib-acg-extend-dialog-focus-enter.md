# Bug: lib-acg — `bringToFront()` desyncs page object; dialog appears dismissed but blocks credentials

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `playwright/acg_credentials.js` — remove `bringToFront` + Escape; go straight to `button.focus()` + `page.keyboard.press('Enter')`

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

After `bringToFront()` + `page.keyboard.press('Escape')`, the script logs no WARN (it
believes the dialog was dismissed) but credentials never populate — the 420s locator wait
times out. The dialog is still visibly present in the browser throughout.

**Root cause:** `page.bringToFront()` sends `Target.activateTarget` via CDP. In a
CDP-attached session connecting to an existing Chrome instance, this can cause the
Playwright `page` object to desync from the actual visible page — subsequent
`page.evaluate()` calls may run on a page in a transitioning state (no dialog), making
`_stillVisible` return `false` and `waitForFunction` return `true` even though the dialog
is still there. The script exits `_dismissExtendYourSessionDialog` believing it succeeded,
but credentials cannot populate because the dialog remains.

Additionally, `page.keyboard.press('Escape')` has never reliably dismissed this dialog
across five attempts — it is removed entirely.

**What does work (per Playwright CDP architecture):**
- `element.focus()` in `page.evaluate()` sets DOM focus without going through CDP input pipeline — no tab-activation requirement, no page-state side effects.
- `page.keyboard.press('Enter')` on a DOM-focused button fires the browser's native "activation behavior" (a real click event on the focused button), which React's event delegation handles correctly.
- This approach works whether or not the tab is the active Chrome tab, because focus is set at the DOM level and the keyboard event goes to `document.activeElement`.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: remove bringToFront + Escape; skip directly to focus + Enter

**Exact old block (lines 379–407, inside `_dismissExtendYourSessionDialog`, after the `_dialogVisible` check):**

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

**Exact new block:**

```javascript
        console.error('INFO: "Extend Your Session" dialog detected — dismissing via keyboard...');
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
| `playwright/acg_credentials.js` | Remove `bringToFront` + Escape + `_stillVisible` conditional; go straight to `button.focus()` + `Enter` |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- No other files modified

---

## Definition of Done

- [ ] `await page.bringToFront();` removed entirely
- [ ] `await page.keyboard.press('Escape').catch(() => {});` removed entirely
- [ ] `_stillVisible` check and its conditional block removed entirely
- [ ] `page.evaluate()` for `btn.focus()` is now unconditional (runs immediately after the INFO log)
- [ ] `page.keyboard.press('Enter')` follows immediately after the evaluate
- [ ] `await page.waitForTimeout(1000);` present after the `Enter` press
- [ ] `waitForFunction` timeout remains 5000
- [ ] WARN + continue on timeout (no `process.exit(1)`)
- [ ] INFO log says `"dismissing via keyboard..."` (not `"Escape key..."`)
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat` output

**Commit message (exact):**
```
fix(acg): drop bringToFront+Escape; focus Cancel then Enter to dismiss extend dialog
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT restore `process.exit(1)`
- Do NOT use `page.mouse.click()`, `locator.click()`, or `page.bringToFront()` — all three have page-state or OS-focus issues in CDP-attached sessions
- Do NOT touch `acg_extend.js`
- Do NOT keep the `_stillVisible` conditional — the focus+Enter must always run unconditionally
