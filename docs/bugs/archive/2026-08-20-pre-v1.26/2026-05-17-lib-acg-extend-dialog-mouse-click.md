# Bug: lib-acg — `dispatchEvent` in `page.evaluate()` does not drive React click; "Extend Session" button never fires

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `playwright/acg_credentials.js` — replace `dispatchEvent` with `page.mouse.click(x, y)` using `getBoundingClientRect()` coordinates

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

`_dismissExtendYourSessionDialog` logs `"clicking Extend Session via DOM..."` then after 10s
logs `ERROR: "Extend Your Session" dialog did not close within 10s — aborting`. The button
is never clicked even with `dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))`.

**Root cause:** `page.evaluate()` creates a JavaScript event inside the page's V8 context.
Playwright's CDP input pipeline (`Input.dispatchMouseEvent`) is never involved. React's
synthetic event system is wired to real browser input events delivered via CDP — it does not
respond to programmatically synthesised DOM events fired from `page.evaluate()`. The only
reliable way to drive a React button from Playwright is `page.mouse.click(x, y)`, which sends
`Input.dispatchMouseEvent` through the browser's actual input processing path.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: replace `dispatchEvent` with `page.mouse.click`

Keep DOM traversal and `scrollIntoView` inside `page.evaluate()` — only change: instead of
dispatching the event there, return `{x, y}` from `getBoundingClientRect()` and call
`page.mouse.click(x, y)` outside the evaluate block.

**Exact old block:**

```javascript
        await page.evaluate(() => {
          const dialog = Array.from(document.querySelectorAll('[role="dialog"]'))
            .find(d => (d.innerText || '').includes('Extend Your Session'));
          if (!dialog) return;
          const btn = Array.from(dialog.querySelectorAll('button'))
            .find(b => (b.textContent || '').trim().includes('Extend Session'));
          if (!btn) return;
          btn.scrollIntoView({ block: 'center' });
          btn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
        }).catch(() => {});
        await page.waitForTimeout(2000);
        await page.evaluate(() => {
          const closeBtn = document.querySelector('button[aria-label="close" i]');
          if (closeBtn) {
            closeBtn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
            return;
          }
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let n;
          while ((n = walker.nextNode())) {
            if ((n.nodeValue || '').includes('Your sandbox has been extended.')) {
              let el = n.parentElement;
              for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
                const buttons = [...el.querySelectorAll('button')];
                if (buttons.length) {
                  buttons[buttons.length - 1].dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
                  return;
                }
              }
              break;
            }
          }
        }).catch(() => {});
```

**Exact new block:**

```javascript
        const _extendBtnCoords = await page.evaluate(() => {
          const dialog = Array.from(document.querySelectorAll('[role="dialog"]'))
            .find(d => (d.innerText || '').includes('Extend Your Session'));
          if (!dialog) return null;
          const btn = Array.from(dialog.querySelectorAll('button'))
            .find(b => (b.textContent || '').trim().includes('Extend Session'));
          if (!btn) return null;
          btn.scrollIntoView({ block: 'center' });
          const rect = btn.getBoundingClientRect();
          return { x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2) };
        }).catch(() => null);
        if (_extendBtnCoords) {
          await page.mouse.click(_extendBtnCoords.x, _extendBtnCoords.y);
        }
        await page.waitForTimeout(2000);
        const _closeBtnCoords = await page.evaluate(() => {
          const closeBtn = document.querySelector('button[aria-label="close" i]');
          if (closeBtn) {
            const rect = closeBtn.getBoundingClientRect();
            return { x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2) };
          }
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let n;
          while ((n = walker.nextNode())) {
            if ((n.nodeValue || '').includes('Your sandbox has been extended.')) {
              let el = n.parentElement;
              for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
                const buttons = [...el.querySelectorAll('button')];
                if (buttons.length) {
                  const btn = buttons[buttons.length - 1];
                  const rect = btn.getBoundingClientRect();
                  return { x: Math.round(rect.left + rect.width / 2), y: Math.round(rect.top + rect.height / 2) };
                }
              }
              break;
            }
          }
          return null;
        }).catch(() => null);
        if (_closeBtnCoords) {
          await page.mouse.click(_closeBtnCoords.x, _closeBtnCoords.y);
        }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Replace `dispatchEvent` with `page.mouse.click(x, y)` using `getBoundingClientRect()` coords |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- No other files modified

---

## Definition of Done

- [ ] `page.evaluate()` for "Extend Session" button now returns `{x, y}` from `getBoundingClientRect()` instead of dispatching a MouseEvent
- [ ] `page.mouse.click(_extendBtnCoords.x, _extendBtnCoords.y)` called outside evaluate block (guarded by `if (_extendBtnCoords)`)
- [ ] `page.evaluate()` for close/confirmation button now returns `{x, y}` from `getBoundingClientRect()` instead of dispatching a MouseEvent
- [ ] `page.mouse.click(_closeBtnCoords.x, _closeBtnCoords.y)` called outside evaluate block (guarded by `if (_closeBtnCoords)`)
- [ ] `scrollIntoView({ block: 'center' })` kept on the Extend Session button (ensures coords are in viewport before click)
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg): use page.mouse.click with getBoundingClientRect for extend dialog
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT add `addLocatorHandler` — all DOM traversal stays in `page.evaluate()`
- Do NOT touch `acg_extend.js`
- Do NOT use `page.locator().click()` — use `page.mouse.click(x, y)` as specified
