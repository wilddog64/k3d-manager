# Bug: lib-acg — "Extend Your Session" DOM click not closing dialog

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `playwright/acg_credentials.js` — change `.click()` to `dispatchEvent`, increase timeout, exit on failure

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

`_dismissExtendYourSessionDialog` logs `"clicking Extend Session via DOM..."` then immediately
logs `WARN: "Extend Your Session" dialog did not close within 5s — proceeding anyway`. The
script extracts credentials despite the dialog still being open, yielding
`InvalidAccessKeyId` on first use.

**Root cause:** `btn.click()` is a plain DOM `.click()`. The ACG page uses React synthetic
events — plain `.click()` fires the native handler but React's event delegation never sees
it. The button appears clicked but the dialog state machine never advances. After 5s the
script gives up and proceeds, extracting whatever credentials happen to be visible (often
stale).

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: `_dismissExtendYourSessionDialog`

Replace the plain `.click()` call with a `MouseEvent` dispatch (bubbles through React's
delegation layer), scroll the button into view first, increase the close-wait timeout from
5 s to 10 s, and exit non-zero if the dialog still doesn't close (don't proceed with
invalid creds).

**Exact old block (lines 380–416):**

```javascript
        await page.evaluate(() => {
          const dialog = Array.from(document.querySelectorAll('[role="dialog"]'))
            .find(d => (d.innerText || '').includes('Extend Your Session'));
          if (!dialog) return;
          const btn = Array.from(dialog.querySelectorAll('button'))
            .find(b => (b.textContent || '').trim().includes('Extend Session'));
          if (btn) btn.click();
        }).catch(() => {});
        await page.waitForTimeout(2000);
        await page.evaluate(() => {
          const closeBtn = document.querySelector('button[aria-label="close" i]');
          if (closeBtn) {
            closeBtn.click();
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
                  buttons[buttons.length - 1].click();
                  return;
                }
              }
              break;
            }
          }
        }).catch(() => {});
        await page.waitForTimeout(500);
        await page.waitForFunction(
          () => !Array.from(document.querySelectorAll('[role="dialog"]'))
            .some(d => (d.innerText || '').includes('Extend Your Session')),
          { timeout: 5000 }
        ).catch(() => console.error('WARN: "Extend Your Session" dialog did not close within 5s — proceeding anyway'));
```

**Exact new block:**

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
        await page.waitForTimeout(500);
        const _dialogClosed = await page.waitForFunction(
          () => !Array.from(document.querySelectorAll('[role="dialog"]'))
            .some(d => (d.innerText || '').includes('Extend Your Session')),
          { timeout: 10000 }
        ).then(() => true).catch(() => false);
        if (!_dialogClosed) {
          console.error('ERROR: "Extend Your Session" dialog did not close within 10s — aborting to avoid invalid credentials');
          process.exit(1);
        }
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Replace `.click()` with `dispatchEvent MouseEvent`; increase timeout 5→10s; exit non-zero on failure |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- No other files modified

---

## Definition of Done

- [ ] All three `btn.click()` / `closeBtn.click()` calls replaced with `dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }))`
- [ ] `btn.scrollIntoView({ block: 'center' })` added before the Extend Session dispatch
- [ ] `waitForFunction` timeout increased from `5000` to `10000`
- [ ] On timeout: logs `ERROR: ... aborting` and calls `process.exit(1)` instead of proceeding
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg): use MouseEvent dispatchEvent for extend dialog; exit on failure
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT use `addLocatorHandler` — all dialog interaction stays in `page.evaluate()`
- Do NOT touch `acg_extend.js`
