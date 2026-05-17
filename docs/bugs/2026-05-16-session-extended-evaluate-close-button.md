# Bug: acg — "Session extended" toast × never clicked — page-level aria-label + role selectors both find 0 matches, fallback hangs 30 s

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_credentials.js`, `scripts/lib/acg/playwright/acg_extend.js`

---

## Problem

After the text-locator fix (`70ce5ca9`), `isVisible()` now correctly returns true — the toast
is detected. But the click still fails:

1. `page.locator('button[aria-label="Close" i]').count()` → 0 — the × button has **no aria-label**
2. Fallback: `page.locator('[role="alert"] button, [role="status"] button').first().click()` — the
   toast container has **no role="alert" or role="status"**, so Playwright waits the full 30-second
   default timeout before throwing. `.catch(() => {})` swallows the error. `make up` hangs ~35 s per
   dismiss site (30 s locator timeout + 5 s `waitFor`).

**Root cause:** The ACG "Session extended" toast uses neither a standard `aria-label` nor a standard
ARIA role on its container. Playwright's attribute/role selectors cannot find the × button.

---

## Fix

Replace the 2-line `_hasCIClose` click block at all 7 dismiss sites with a single `page.evaluate()`
call that uses DOM TreeWalker to locate the text node, walks up to the nearest ancestor that contains
a button, and clicks the last button in that ancestor. This bypasses Playwright's locator engine
entirely — no 30-second timeout, no aria-label dependency.

---

### Pattern applied at all 7 sites

**OLD (2 lines — current state after `70ce5ca9`):**
```javascript
    const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
    await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
```

**NEW (9 lines — evaluate DOM traversal):**
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

The evaluate:
1. Tries `button[aria-label="close" i]` via native DOM (`querySelector` is case-insensitive with `i`)
2. Falls back to TreeWalker: finds the toast text node, walks up at most 8 levels to find the nearest
   ancestor that has buttons, clicks the last one (the × in a toast is always the last button)

---

### Change 1 — `acg_credentials.js`: `_clickStartSandbox` (`_sessionExtended`)

**Exact old block:**
```javascript
  const _sessionExtended = page.locator('text="Your sandbox has been extended."').first();
  if (await _sessionExtended.isVisible({ timeout: 2000 }).catch(() => false)) {
    const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
    await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
    await _sessionExtended.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
  }
```

**Exact new block:**
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

---

### Change 2 — `acg_credentials.js`: `addLocatorHandler` (`_sessionExtendedConfirm`)

**Exact old block:**
```javascript
          const _sessionExtendedConfirm = page.locator('text="Your sandbox has been extended."').first();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
            await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
```

**Exact new block:**
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

---

### Change 3 — `acg_credentials.js`: proactive dismissal (`_sessionExtendedModal`)

**Exact old block:**
```javascript
    const _sessionExtendedModal = page.locator('text="Your sandbox has been extended."').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
      await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
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

---

### Change 4 — `acg_credentials.js`: `_waitForCredentials` poll loop (`_sessionExtendedConfirm`)

**Exact old block:**
```javascript
              const _sessionExtendedConfirm = page.locator('text="Your sandbox has been extended."').first();
              if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
                const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
                await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
                await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
              }
```

**Exact new block:**
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

---

### Change 5 — `acg_extend.js`: initial dismissal (`_sessionExtendedModal`)

**Exact old block:**
```javascript
    const _sessionExtendedModal = page.locator('text="Your sandbox has been extended."').first();
    if (await _sessionExtendedModal.isVisible({ timeout: 3000 }).catch(() => false)) {
      console.error('INFO: Dismissing "Session extended" modal...');
      const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
      await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
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

---

### Change 6 — `acg_extend.js`: Immediate path (`_extendedConfirm`)

**Exact old block:**
```javascript
      const _extendedConfirm = page.locator('text="Your sandbox has been extended."').first();
      if (await _extendedConfirm.isVisible({ timeout: 3000 }).catch(() => false)) {
        const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
        await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
        await _extendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
```

**Exact new block:**
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

---

### Change 7 — `acg_extend.js`: general path (`_extendedConfirmGeneral`)

**Exact old block:**
```javascript
    const _extendedConfirmGeneral = page.locator('text="Your sandbox has been extended."').first();
    if (await _extendedConfirmGeneral.isVisible({ timeout: 2000 }).catch(() => false)) {
      const _hasCIClose = await page.locator('button[aria-label="Close" i]').count().catch(() => 0) > 0;
      await (_hasCIClose ? page.locator('button[aria-label="Close" i]').first() : page.locator('[role="alert"] button, [role="status"] button').first()).click({ force: true }).catch(() => {});
      await _extendedConfirmGeneral.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
    }
```

**Exact new block:**
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

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Changes 1–4 — 4 sites |
| `scripts/lib/acg/playwright/acg_extend.js` | Changes 5–7 — 3 sites |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- `node --check scripts/lib/acg/playwright/acg_extend.js` — must pass
- No other files touched
- Only the 7 listed dismiss blocks change — all surrounding lines unchanged

---

## Definition of Done

- [ ] All 7 dismiss sites updated: 2-line `_hasCIClose` click block → `page.evaluate()` DOM traversal
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
fix(acg): page.evaluate DOM traversal to click Session extended toast close button
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `acg_credentials.js` and `acg_extend.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change the `text="Your sandbox has been extended."` locator declarations (line A at each site)
- Do NOT change the `isVisible` or `waitFor` lines — only the 2-line click block changes
- Do NOT change any other button selectors (Extend Session, Cancel, Start Sandbox, etc.)
- Do NOT combine with any other change in the same commit
