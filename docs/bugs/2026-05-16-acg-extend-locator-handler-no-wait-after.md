# Bug: acg_extend.js + acg_credentials.js — addLocatorHandler post-handler wait loop — missing noWaitAfter: true

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_extend.js`, `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

Two `addLocatorHandler` calls are missing `noWaitAfter: true`, causing Playwright to hang
after the handler runs.

**`acg_extend.js`** — hangs after the "Session extended" toast × is clicked. The button IS
clicked (visible in browser) but the script never proceeds. Terminal stays frozen at
`INFO: [acg] Extending ACG sandbox TTL at …` indefinitely.

**`acg_credentials.js`** — `page.waitForSelector` for `input[aria-label="Copyable input"]`
times out after 15 s:

```
waiting for locator('input[aria-label="Copyable input"]') to be visible
  - found locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")'),
    intercepting action to run the handler
  - locator handler has finished, waiting for locator(…) to be hidden
  33 × locator resolved to visible
```

**Root cause (both files):** After a handler resolves, Playwright re-checks the trigger
locator. If it is still visible, Playwright either re-fires the handler (infinite loop) or
blocks the intercepted action until the locator hides (timeout). The "Extend Your Session"
dialog has a CSS slide-in animation (`data-transitioning="true"`) that keeps it technically
visible during the transition, so the post-handler wait always times out.

The Playwright docs state:
> "After calling the handler Playwright will wait until the overlay is not visible anymore
> before the actual action is performed. If the handler didn't make the overlay disappear,
> Playwright will keep calling the handler."

`{ noWaitAfter: true }` skips the post-handler visibility re-check: the handler fires, then
the blocked action proceeds immediately regardless of whether the locator is still visible.

---

## Reproduction

1. Run `make up` with `CLUSTER_PROVIDER=k3s-aws`.
2. **acg_extend.js hang:** terminal freezes at `INFO: [acg] Extending ACG sandbox TTL at …`
3. **acg_credentials.js hang:** `ERROR: page.waitForSelector: Timeout 15000ms exceeded` with
   33 × poll loop in the call log.

---

## Fix

### Change 1 — `acg_extend.js`: add `{ noWaitAfter: true }` as third argument

**Exact old block (lines 139–169):**

```javascript
    await page.addLocatorHandler(
      page.locator('text="Your sandbox has been extended."').first(),
      async () => {
        console.error('INFO: [handler] Dismissing "Session extended" toast...');
        const _closeBox = await page.evaluate(() => {
          const cb = document.querySelector('button[aria-label="close" i]');
          if (cb) {
            const r = cb.getBoundingClientRect();
            return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
          }
          const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let n;
          while ((n = w.nextNode())) {
            if (n.nodeValue.includes('Your sandbox has been extended.')) {
              let el = n.parentElement;
              for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
                const bs = [...el.querySelectorAll('button')];
                if (bs.length) {
                  const r = bs[bs.length - 1].getBoundingClientRect();
                  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
                }
              }
              break;
            }
          }
          return null;
        }).catch(() => null);
        if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
        await page.locator('text="Your sandbox has been extended."').first().waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      }
    );
```

**Exact new block (only change: `, { noWaitAfter: true }` added before closing `)`):**

```javascript
    await page.addLocatorHandler(
      page.locator('text="Your sandbox has been extended."').first(),
      async () => {
        console.error('INFO: [handler] Dismissing "Session extended" toast...');
        const _closeBox = await page.evaluate(() => {
          const cb = document.querySelector('button[aria-label="close" i]');
          if (cb) {
            const r = cb.getBoundingClientRect();
            return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
          }
          const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
          let n;
          while ((n = w.nextNode())) {
            if (n.nodeValue.includes('Your sandbox has been extended.')) {
              let el = n.parentElement;
              for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
                const bs = [...el.querySelectorAll('button')];
                if (bs.length) {
                  const r = bs[bs.length - 1].getBoundingClientRect();
                  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
                }
              }
              break;
            }
          }
          return null;
        }).catch(() => null);
        if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
        await page.locator('text="Your sandbox has been extended."').first().waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
      },
      { noWaitAfter: true }
    );
```

---

### Change 2 — `acg_credentials.js`: add `noWaitAfter: true` to existing `{ times: 1 }` options

**Exact old line (line 335):**

```javascript
      { times: 1 }
```

**Exact new line:**

```javascript
      { times: 1, noWaitAfter: true }
```

Context — the full `addLocatorHandler` call for reference (lines 296–336):

```javascript
    await page.addLocatorHandler(
      page.locator('[role="dialog"][data-open="true"]:has-text("Extend Your Session")'),
      async () => {
        console.error('INFO: [handler] Clicking "Extend Session" to extend sandbox...');
        const _extendBtn = page.locator('[role="dialog"]:has-text("Extend Your Session") button:has-text("Extend Session")').first();
        if (await _extendBtn.isVisible({ timeout: 3000 }).catch(() => false)) {
          await _extendBtn.click({ force: true }).catch(() => {});
          const _sessionExtendedConfirm = page.locator('text="Your sandbox has been extended."').first();
          if (await _sessionExtendedConfirm.isVisible({ timeout: 2000 }).catch(() => false)) {
            const _closeBox = await page.evaluate(() => {
              const cb = document.querySelector('button[aria-label="close" i]');
              if (cb) {
                const r = cb.getBoundingClientRect();
                return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
              }
              const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
              let n;
              while ((n = w.nextNode())) {
                if (n.nodeValue.includes('Your sandbox has been extended.')) {
                  let el = n.parentElement;
                  for (let i = 0; i < 8 && el && el !== document.body; i++, el = el.parentElement) {
                    const bs = [...el.querySelectorAll('button')];
                    if (bs.length) {
                      const r = bs[bs.length - 1].getBoundingClientRect();
                      return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
                    }
                  }
                  break;
                }
              }
              return null;
            }).catch(() => null);
            if (_closeBox) await page.mouse.click(_closeBox.x, _closeBox.y);
            await _sessionExtendedConfirm.waitFor({ state: 'hidden', timeout: 5000 }).catch(() => {});
          }
        }
        await page.locator('[role="dialog"]:has-text("Extend Your Session")').waitFor({ state: 'hidden', timeout: 3000 }).catch(() => {});
        await page.waitForTimeout(1000).catch(() => {});
      },
      { times: 1 }
    );
```

After Change 2 the last line before `);` reads `{ times: 1, noWaitAfter: true }`.
No other lines in this block change.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_extend.js` | Add `{ noWaitAfter: true }` as third arg to `addLocatorHandler` |
| `scripts/lib/acg/playwright/acg_credentials.js` | Change `{ times: 1 }` → `{ times: 1, noWaitAfter: true }` on the `addLocatorHandler` options line |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_extend.js` — must pass
- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- No shellcheck — these are JavaScript files
- No other files touched
- Only the options arguments change — no handler bodies modified

---

## Definition of Done

- [ ] `{ noWaitAfter: true }` added to `addLocatorHandler` in `acg_extend.js` (Change 1)
- [ ] `{ times: 1 }` → `{ times: 1, noWaitAfter: true }` in `acg_credentials.js` (Change 2)
- [ ] No other lines modified in either file
- [ ] `node --check scripts/lib/acg/playwright/acg_extend.js` passes
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg): add noWaitAfter: true to both addLocatorHandler calls
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `acg_extend.js` and `acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT run shellcheck — these are JS files, run `node --check` only
- Do NOT change handler bodies — only the options arguments change
- Do NOT add `noWaitAfter` to any location other than the two `addLocatorHandler` calls
