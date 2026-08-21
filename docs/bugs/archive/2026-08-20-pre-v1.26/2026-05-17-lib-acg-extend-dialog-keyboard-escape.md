# Bug: lib-acg — "Extend Your Session" dialog click still not landing; page.mouse.click unreliable in CDP-attached sessions

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `playwright/acg_credentials.js` — replace click sequence with Escape key + force-click fallback; downgrade exit-1 to WARN+continue

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

`_dismissExtendYourSessionDialog` still fails with `ERROR: dialog did not close within 10s —
aborting`. `page.mouse.click(x, y)` with `getBoundingClientRect()` coords does not register
in a CDP-attached browser session when the tab is not the OS-active focused window.

**Key finding from live testing:** AWS credentials populate in the Playwright output regardless
of whether the user clicks "Extend Session" or "Cancel". The dialog only needs to be dismissed
— any button (or Escape) works — because the credentials panel is already loading in the
background. The hard `process.exit(1)` is therefore too aggressive; the `sts:GetCallerIdentity`
check in `bin/acg-credential-test` is the actual validity gate.

**Root cause of click failures:** Three approaches have been tried in order:
1. `btn.click()` in `page.evaluate()` — fires native DOM click; React synthetic layer ignores it
2. `dispatchEvent(new MouseEvent(...))` in `page.evaluate()` — same: created inside V8, never touches CDP `Input.dispatchMouseEvent`
3. `page.mouse.click(x, y)` with `getBoundingClientRect()` coords — goes through CDP but requires the tab to be the OS-active focused window; unreliable in a background CDP session

**CDP keyboard events (`page.keyboard.press`) do not have this focus restriction.** They
dispatch `Input.dispatchKeyEvent` through the DevTools protocol at the session level, not the
OS window level, so they work even when the Chrome window is in the background.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: replace click sequence with Escape + force-click fallback

Replace everything after the dialog-detected log line (inside `_dismissExtendYourSessionDialog`)
with:
1. `page.keyboard.press('Escape')` — CDP keyboard event; works in background tab
2. If dialog still visible after 1s: `page.locator(...).click({ force: true })` — forces Cancel button click bypassing interactability checks
3. `waitForFunction` timeout reduced 10s → 5s (no server round-trip needed for Escape/Cancel)
4. On timeout: WARN + continue (do NOT `process.exit(1)`) — credentials populate either way; `sts:GetCallerIdentity` is the gate

**Exact old block (from the INFO log through the closing `}`of the if-not-closed block):**

```javascript
        console.error('INFO: "Extend Your Session" dialog detected — clicking Extend Session via DOM...');
        const _extendBtnCoords = await page.evaluate(() => {
          const dialog = Array.from(document.querySelectorAll('[role="dialog"]'))
            .find(d => (d.innerText || '').includes('Extend Your Session'));
          if (!dialog) return null;
          const btn = Array.from(dialog.querySelectorAll('button'))
            .find(b => (b.textContent || '').trim().includes('Extend Session'));
          if (!btn) return null;
          btn.scrollIntoView({ block: 'center' });
          const rect = btn.getBoundingClientRect();
          return {
            x: Math.round(rect.left + rect.width / 2),
            y: Math.round(rect.top + rect.height / 2),
          };
        }).catch(() => null);
        if (_extendBtnCoords) {
          await page.mouse.click(_extendBtnCoords.x, _extendBtnCoords.y);
        }
        await page.waitForTimeout(2000);
        const _closeBtnCoords = await page.evaluate(() => {
          const closeBtn = document.querySelector('button[aria-label="close" i]');
          if (closeBtn) {
            const rect = closeBtn.getBoundingClientRect();
            return {
              x: Math.round(rect.left + rect.width / 2),
              y: Math.round(rect.top + rect.height / 2),
            };
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
                  return {
                    x: Math.round(rect.left + rect.width / 2),
                    y: Math.round(rect.top + rect.height / 2),
                  };
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

**Exact new block:**

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

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Replace multi-step mouse-click sequence with Escape key + force-click fallback; WARN instead of exit-1 |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- No other files modified

---

## Definition of Done

- [ ] The `_extendBtnCoords` evaluate block removed entirely
- [ ] The `_closeBtnCoords` evaluate block (TreeWalker "Your sandbox has been extended") removed entirely
- [ ] `page.keyboard.press('Escape')` is the primary dismiss method
- [ ] `_stillVisible` check added; if true, `page.locator('[role="dialog"]').filter({ hasText: 'Extend Your Session' }).locator('button').first().click({ force: true, timeout: 3000 })` is the fallback
- [ ] `waitForFunction` timeout is 5000 (not 10000)
- [ ] On timeout: `console.error('WARN: ...')` and function returns (no `process.exit(1)`)
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg): dismiss extend dialog via Escape key with force-click fallback
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT add `addLocatorHandler`
- Do NOT touch `acg_extend.js`
- Do NOT restore `process.exit(1)` — the credential validation gate is in `bin/acg-credential-test` via `sts:GetCallerIdentity`
