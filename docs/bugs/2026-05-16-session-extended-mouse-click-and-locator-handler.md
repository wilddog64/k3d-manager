# Bug: acg — "Session extended" toast × never dismissed — element.click() ignored by React + no addLocatorHandler in acg_extend.js

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_credentials.js`, `scripts/lib/acg/playwright/acg_extend.js`

---

## Problem

Two compounding failures remain after the evaluate-based dismiss approach:

1. **`element.click()` in `page.evaluate()` does not dismiss the toast** — Chakra UI close buttons
   register React synthetic event handlers via React's event delegation at the root. A DOM
   `.click()` fired from `page.evaluate()` does NOT send the `mousedown`+`mouseup`+`click`
   pointer event sequence that Playwright's `page.mouse.click()` sends. React's delegation
   never receives the event, so the handler never fires and the toast stays visible.

2. **`acg_extend.js` has no `addLocatorHandler` for the "Session extended" toast** — the toast
   can appear while the script is blocked inside `_waitForVisibleExtendButton`, `waitForFunction`
   (skeleton loaders), or the confirmation loop. Without a locator handler, there is nothing to
   auto-dismiss it when it appears at an unexpected time. `acg_credentials.js` already has an
   `addLocatorHandler` (for the "Extend Your Session" dialog at site 2), but `acg_extend.js`
   has none.

Combined effect: the toast is never dismissed, `waitFor({ state: 'hidden' })` times out after
5 s, and the confirmation loop can hang for up to 40 s (4 selectors × 10 s each) before the
script either completes or times out.

---

## Fix

### Two changes

**Change A — all 7 dismiss blocks in both files:** replace `element.click()` inside
`page.evaluate()` with `getBoundingClientRect()` → `page.mouse.click()`. The evaluate now
returns `{ x, y }` coordinates; Playwright sends real pointer events that React responds to.

**Change B — `acg_extend.js` only:** add one `addLocatorHandler` block immediately after the
page navigation block (before the skeleton-loader wait), using the same bounding-rect +
`page.mouse.click()` pattern. This catches the toast at any point during the script's
execution regardless of when it appears.

---

### Pattern applied at all 7 dismiss sites (Change A)

**OLD (12 lines — evaluate with element.click()):**
```javascript
    await page.evaluate(() => {
      const closeBtn = document.querySelector('button[aria-label="close" i]');
      if (closeBtn) { closeBtn.click(); return; }
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) {
        if (node.nodeValue.includes('Your sandbox has been extended.')) {
          let el = node.parentElement;
          for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
            const btns = [...el.querySelectorAll('button')];
            if (btns.length) { btns[btns.length - 1].click(); return; }
          }
          break;
        }
      }
    }).catch(() => {});
```

**NEW (3 lines — evaluate returns coords, page.mouse.click()):**
```javascript
    const _closeBox = await page.evaluate(() => { const cb = document.querySelector('button[aria-label="close" i]'); if (cb) { const r = cb.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n; while ((n = w.nextNode())) { if (n.nodeValue.includes('Your sandbox has been extended.')) { let el = n.parentElement; for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) { const bs = [...el.querySelectorAll('button')]; if (bs.length) { const r = bs[bs.length - 1].getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } } break; } } return null; }).catch(() => null);
    if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
```

Note: `_closeBox` is declared inside an `if` block at each site — block-scoped `const`,
no conflicts between sites.

---

### Change 1 — `acg_credentials.js`: `_clickStartSandbox` (`_sessionExtended`)

**Exact old block:**
```javascript
  const _sessionExtended = page.locator('text="Your sandbox has been extended."').first();
  if (await _sessionExtended.isVisible({ timeout: 2000 }).catch(() => false)) {
    await page.evaluate(() => {
      const closeBtn = document.querySelector('button[aria-label="close" i]');
      if (closeBtn) { closeBtn.click(); return; }
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) {
        if (node.nodeValue.includes('Your sandbox has been extended.')) {
          let el = node.parentElement;
          for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
            const btns = [...el.querySelectorAll('button')];
            if (btns.length) { btns[btns.length - 1].click(); return; }
          }
          break;
        }
      }
    }).catch(() => {});
    await _sessionExtended.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }
```

**Exact new block:**
```javascript
  const _sessionExtended = page.locator('text="Your sandbox has been extended."').first();
  if (await _sessionExtended.isVisible({ timeout: 2000 }).catch(() => false)) {
    const _closeBox = await page.evaluate(() => { const cb = document.querySelector('button[aria-label="close" i]'); if (cb) { const r = cb.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n; while ((n = w.nextNode())) { if (n.nodeValue.includes('Your sandbox has been extended.')) { let el = n.parentElement; for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) { const bs = [...el.querySelectorAll('button')]; if (bs.length) { const r = bs[bs.length - 1].getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } } break; } } return null; }).catch(() => null);
    if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
    await _sessionExtended.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }
```

---

### Change 2 — `acg_credentials.js`: `addLocatorHandler` (`_sessionExtendedConfirm`)

**Exact old block:**
```javascript
          const _sessionExtendedConfirm = page.locator('text="Your sandbox has been extended."').first();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            await page.evaluate(() => {
              const closeBtn = document.querySelector('button[aria-label="close" i]');
              if (closeBtn) { closeBtn.click(); return; }
              const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
              let node;
              while ((node = walker.nextNode())) {
                if (node.nodeValue.includes('Your sandbox has been extended.')) {
                  let el = node.parentElement;
                  for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
                    const btns = [...el.querySelectorAll('button')];
                    if (btns.length) { btns[btns.length - 1].click(); return; }
                  }
                  break;
                }
              }
            }).catch(() => {});
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
```

**Exact new block:**
```javascript
          const _sessionExtendedConfirm = page.locator('text="Your sandbox has been extended."').first();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            const _closeBox = await page.evaluate(() => { const cb = document.querySelector('button[aria-label="close" i]'); if (cb) { const r = cb.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n; while ((n = w.nextNode())) { if (n.nodeValue.includes('Your sandbox has been extended.')) { let el = n.parentElement; for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) { const bs = [...el.querySelectorAll('button')]; if (bs.length) { const r = bs[bs.length - 1].getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } } break; } } return null; }).catch(() => null);
            if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
```

---

### Change 3 — `acg_credentials.js`: proactive dismissal (`_sessionExtendedModal`)

**Exact old block:**
```javascript
    const _sessionExtendedModal = page.locator('text="Your sandbox has been extended."').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await page.evaluate(() => {
        const closeBtn = document.querySelector('button[aria-label="close" i]');
        if (closeBtn) { closeBtn.click(); return; }
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          if (node.nodeValue.includes('Your sandbox has been extended.')) {
            let el = node.parentElement;
            for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
              const btns = [...el.querySelectorAll('button')];
              if (btns.length) { btns[btns.length - 1].click(); return; }
            }
            break;
          }
        }
      }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }
```

**Exact new block:**
```javascript
    const _sessionExtendedModal = page.locator('text="Your sandbox has been extended."').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      const _closeBox = await page.evaluate(() => { const cb = document.querySelector('button[aria-label="close" i]'); if (cb) { const r = cb.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n; while ((n = w.nextNode())) { if (n.nodeValue.includes('Your sandbox has been extended.')) { let el = n.parentElement; for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) { const bs = [...el.querySelectorAll('button')]; if (bs.length) { const r = bs[bs.length - 1].getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } } break; } } return null; }).catch(() => null);
      if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }
```

---

### Change 4 — `acg_credentials.js`: `_waitForCredentials` poll loop (`_sessionExtendedConfirm`)

**Exact old block:**
```javascript
              const _sessionExtendedConfirm = page.locator('text="Your sandbox has been extended."').first();
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                await page.evaluate(() => {
                  const closeBtn = document.querySelector('button[aria-label="close" i]');
                  if (closeBtn) { closeBtn.click(); return; }
                  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                  let node;
                  while ((node = walker.nextNode())) {
                    if (node.nodeValue.includes('Your sandbox has been extended.')) {
                      let el = node.parentElement;
                      for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
                        const btns = [...el.querySelectorAll('button')];
                        if (btns.length) { btns[btns.length - 1].click(); return; }
                      }
                      break;
                    }
                  }
                }).catch(() => {});
                await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
              }
```

**Exact new block:**
```javascript
              const _sessionExtendedConfirm = page.locator('text="Your sandbox has been extended."').first();
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                const _closeBox = await page.evaluate(() => { const cb = document.querySelector('button[aria-label="close" i]'); if (cb) { const r = cb.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n; while ((n = w.nextNode())) { if (n.nodeValue.includes('Your sandbox has been extended.')) { let el = n.parentElement; for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) { const bs = [...el.querySelectorAll('button')]; if (bs.length) { const r = bs[bs.length - 1].getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } } break; } } return null; }).catch(() => null);
                if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
                await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
              }
```

---

### Change 5 — `acg_extend.js`: add `addLocatorHandler` (Change B — new block)

Insert the following block **between** the navigation block (the `if (isOnSandboxPage) / else { await page.goto }` block) and the existing fixed-point dismiss check (`// Dismiss any lingering "Session extended"`).

**Exact surrounding context (unchanged lines shown for placement):**
```javascript
    } else {
      console.error(`INFO: Navigating to ${targetUrl} (currently on: ${currentUrl})...`);
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    }

    // Dismiss any lingering "Session extended" confirmation modal before searching for extend button
    const _sessionExtendedModal = page.locator('text="Your sandbox has been extended."').first();
```

**After the change (insert the handler block between them):**
```javascript
    } else {
      console.error(`INFO: Navigating to ${targetUrl} (currently on: ${currentUrl})...`);
      await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
    }

    await page.addLocatorHandler(
      page.locator('text="Your sandbox has been extended."').first(),
      async () => {
        const _handlerBox = await page.evaluate(() => { const cb = document.querySelector('button[aria-label="close" i]'); if (cb) { const r = cb.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n; while ((n = w.nextNode())) { if (n.nodeValue.includes('Your sandbox has been extended.')) { let el = n.parentElement; for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) { const bs = [...el.querySelectorAll('button')]; if (bs.length) { const r = bs[bs.length - 1].getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } } break; } } return null; }).catch(() => null);
        if (_handlerBox) await page.mouse.click(_handlerBox.x, _handlerBox.y);
        await page.locator('text="Your sandbox has been extended."').first()
          .waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
    );

    // Dismiss any lingering "Session extended" confirmation modal before searching for extend button
    const _sessionExtendedModal = page.locator('text="Your sandbox has been extended."').first();
```

---

### Change 6 — `acg_extend.js`: initial dismissal (`_sessionExtendedModal`)

**Exact old block:**
```javascript
    const _sessionExtendedModal = page.locator('text="Your sandbox has been extended."').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      await page.evaluate(() => {
        const closeBtn = document.querySelector('button[aria-label="close" i]');
        if (closeBtn) { closeBtn.click(); return; }
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          if (node.nodeValue.includes('Your sandbox has been extended.')) {
            let el = node.parentElement;
            for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
              const btns = [...el.querySelectorAll('button')];
              if (btns.length) { btns[btns.length - 1].click(); return; }
            }
            break;
          }
        }
      }).catch(() => {});
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }
```

**Exact new block:**
```javascript
    const _sessionExtendedModal = page.locator('text="Your sandbox has been extended."').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      const _closeBox = await page.evaluate(() => { const cb = document.querySelector('button[aria-label="close" i]'); if (cb) { const r = cb.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n; while ((n = w.nextNode())) { if (n.nodeValue.includes('Your sandbox has been extended.')) { let el = n.parentElement; for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) { const bs = [...el.querySelectorAll('button')]; if (bs.length) { const r = bs[bs.length - 1].getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } } break; } } return null; }).catch(() => null);
      if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
      await _sessionExtendedModal.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {
        console.error('WARN: "Session extended" modal did not close within 5s — proceeding anyway');
      });
    }
```

---

### Change 7 — `acg_extend.js`: Immediate path (`_extendedConfirm`)

**Exact old block:**
```javascript
      const _extendedConfirm = page.locator('text="Your sandbox has been extended."').first();
      if (await _extendedConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
        await page.evaluate(() => {
          const closeBtn = document.querySelector('button[aria-label="close" i]');
          if (closeBtn) { closeBtn.click(); return; }
          const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let node;
          while ((node = walker.nextNode())) {
            if (node.nodeValue.includes('Your sandbox has been extended.')) {
              let el = node.parentElement;
              for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
                const btns = [...el.querySelectorAll('button')];
                if (btns.length) { btns[btns.length - 1].click(); return; }
              }
              break;
            }
          }
        }).catch(() => {});
        await _extendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
```

**Exact new block:**
```javascript
      const _extendedConfirm = page.locator('text="Your sandbox has been extended."').first();
      if (await _extendedConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
        const _closeBox = await page.evaluate(() => { const cb = document.querySelector('button[aria-label="close" i]'); if (cb) { const r = cb.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n; while ((n = w.nextNode())) { if (n.nodeValue.includes('Your sandbox has been extended.')) { let el = n.parentElement; for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) { const bs = [...el.querySelectorAll('button')]; if (bs.length) { const r = bs[bs.length - 1].getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } } break; } } return null; }).catch(() => null);
        if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
        await _extendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
```

---

### Change 8 — `acg_extend.js`: general path (`_extendedConfirmGeneral`)

**Exact old block:**
```javascript
    const _extendedConfirmGeneral = page.locator('text="Your sandbox has been extended."').first();
    if (await _extendedConfirmGeneral.isVisible({ timeout: 2000 }).catch(() => false)) {
      await page.evaluate(() => {
        const closeBtn = document.querySelector('button[aria-label="close" i]');
        if (closeBtn) { closeBtn.click(); return; }
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
        let node;
        while ((node = walker.nextNode())) {
          if (node.nodeValue.includes('Your sandbox has been extended.')) {
            let el = node.parentElement;
            for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
              const btns = [...el.querySelectorAll('button')];
              if (btns.length) { btns[btns.length - 1].click(); return; }
            }
            break;
          }
        }
      }).catch(() => {});
      await _extendedConfirmGeneral.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    }
```

**Exact new block:**
```javascript
    const _extendedConfirmGeneral = page.locator('text="Your sandbox has been extended."').first();
    if (await _extendedConfirmGeneral.isVisible({ timeout: 2000 }).catch(() => false)) {
      const _closeBox = await page.evaluate(() => { const cb = document.querySelector('button[aria-label="close" i]'); if (cb) { const r = cb.getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT); let n; while ((n = w.nextNode())) { if (n.nodeValue.includes('Your sandbox has been extended.')) { let el = n.parentElement; for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) { const bs = [...el.querySelectorAll('button')]; if (bs.length) { const r = bs[bs.length - 1].getBoundingClientRect(); return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; } } break; } } return null; }).catch(() => null);
      if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
      await _extendedConfirmGeneral.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    }
```

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Changes 1–4 — 4 existing dismiss sites updated |
| `scripts/lib/acg/playwright/acg_extend.js` | Change 5 — new `addLocatorHandler` block inserted; Changes 6–8 — 3 existing dismiss sites updated |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- `node --check scripts/lib/acg/playwright/acg_extend.js` — must pass
- No shellcheck — these are JavaScript files, not shell scripts
- No other files touched
- Only the listed blocks change — all surrounding lines unchanged

---

## Definition of Done

- [ ] `addLocatorHandler` inserted in `acg_extend.js` between the navigation block and the first fixed-point dismiss check
- [ ] All 7 existing dismiss sites updated: evaluate now returns `{ x, y }` bounding rect; `page.mouse.click()` used instead of `element.click()`
- [ ] No other lines modified in either file
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] `node --check scripts/lib/acg/playwright/acg_extend.js` passes
- [ ] No other files modified
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg): page.mouse.click bounding-rect + addLocatorHandler in acg_extend.js for Session extended toast
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `acg_credentials.js` and `acg_extend.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT run shellcheck — these are JS files, run `node --check` only
- Do NOT change any locator declarations, `isVisible`, `waitFor`, or `console.error` lines beyond the listed blocks
- Do NOT change any other button selectors (Extend Session, Cancel, Start Sandbox, etc.)
- Do NOT combine with any other change in the same commit
