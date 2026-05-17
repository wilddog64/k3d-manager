# Bug: lib-acg — `button.focus()` + `Enter` does not dismiss extend dialog; CDP keyboard event not landing on activeElement

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `playwright/acg_credentials.js` — replace `button.focus()` + `page.keyboard.press('Enter')` with `page.locator(...).click()` on the Cancel button

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

`button.focus()` in `page.evaluate()` + `page.keyboard.press('Enter')` does not dismiss the
dialog. The WARN is correctly logged, and credentials do populate despite the dialog remaining
visible — so credential extraction is not blocked. However, the dialog stays open in the
browser, which is undesirable.

**Root cause:** `page.keyboard.press('Enter')` sends `Input.dispatchKeyEvent` via CDP. Even
though `btn.focus()` sets `document.activeElement`, this focus state may not persist to the
CDP target by the time the keyboard event arrives — the dialog's focus trap or a React
re-render between the two async operations may reset `document.activeElement`. The result is
that Enter lands on `document.body` (no activation behavior) instead of the focused button.

**Next approach:** Use `page.locator(...).click()` without `force: true`. Playwright's locator
click performs proper actionability checks (visible, enabled, not overlapped), scrolls the
element into view, computes accurate center coordinates, then sends `Input.dispatchMouseEvent`
via CDP. This is different from attempt 3 (`page.mouse.click` with manually computed
`getBoundingClientRect` coordinates) because:
- Playwright verifies actionability before clicking
- Playwright recomputes coordinates after scrolling (no stale bounding box)
- The Cancel button is targeted by text, not by index (attempt 4 used `.first()` which may
  have targeted the X close button)

CDP mouse events bypass OS-level input routing — they do not require Chrome to be the
OS-active window; they are dispatched directly to the renderer target. This makes
`locator.click()` viable without `bringToFront()` or any OS focus requirement.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: replace focus+Enter with locator.click on Cancel

**Exact old block (lines 379–397, inside `_dismissExtendYourSessionDialog`, after the `_dialogVisible` check):**

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

**Exact new block:**

```javascript
        console.error('INFO: "Extend Your Session" dialog detected — clicking Cancel...');
        await page.locator('[role="dialog"]')
          .filter({ hasText: 'Extend Your Session' })
          .locator('button', { hasText: 'Cancel' })
          .click({ timeout: 5000 })
          .catch(() => {});
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
| `playwright/acg_credentials.js` | Replace `button.focus()` + `Enter` with `page.locator(...).click()` on Cancel button |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- No other files modified

---

## Definition of Done

- [ ] `page.evaluate()` focus block removed entirely
- [ ] `page.keyboard.press('Enter')` removed entirely
- [ ] `page.locator('[role="dialog"]').filter({ hasText: 'Extend Your Session' }).locator('button', { hasText: 'Cancel' }).click({ timeout: 5000 }).catch(() => {})` is the dismiss call
- [ ] `await page.waitForTimeout(1000)` present after the click
- [ ] `waitForFunction` timeout remains 5000
- [ ] WARN + continue on timeout (no `process.exit(1)`)
- [ ] INFO log says `"clicking Cancel..."` (not `"keyboard..."`)
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat` output

**Commit message (exact):**
```
fix(acg): click Cancel via locator to dismiss extend dialog
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT restore `process.exit(1)`
- Do NOT add `force: true` to the click — proper actionability check is the point
- Do NOT use `.first()` — target by `hasText: 'Cancel'` specifically
- Do NOT touch `acg_extend.js`
