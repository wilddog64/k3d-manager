# Bug: acg_extend.js — addLocatorHandler fires in infinite loop — missing noWaitAfter: true

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_extend.js`

---

## Problem

`acg_extend.js` hangs after the "Session extended" toast × button is clicked. The cross
button IS being clicked (visible in the browser), but the script never proceeds past that
point.

**Root cause:** `addLocatorHandler` default behavior re-invokes the handler when the trigger
locator is still visible after the handler resolves. If the toast does not fully disappear
before the handler's 5 s `waitFor` times out (e.g. React close animation still in progress),
Playwright fires the handler again. This repeats indefinitely — one 5 s cycle per iteration —
holding the script in an infinite loop with no terminal output.

The Playwright docs state:
> "After calling the handler Playwright will wait until the overlay is not visible anymore
> before the actual action is performed. If the handler didn't make the overlay disappear,
> Playwright will keep calling the handler."

`{ noWaitAfter: true }` skips this re-check: the handler fires once per intercepted action,
the blocked action proceeds regardless of whether the locator is still visible.

---

## Reproduction

1. Run `make up` with `CLUSTER_PROVIDER=k3s-aws`.
2. Watch the browser — the × button on the "Session extended" toast is clicked.
3. Terminal hangs at `INFO: [acg] Extending ACG sandbox TTL at …` forever.

---

## Fix

### Change 1 — `acg_extend.js`: add `{ noWaitAfter: true }` to `addLocatorHandler`

**Exact old block (lines 139–169 of current file):**

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

**Exact new block (add `{ noWaitAfter: true }` as third argument):**

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

The only change is the addition of `, { noWaitAfter: true }` before the closing `)` of
`addLocatorHandler`. All other lines are identical.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/acg/playwright/acg_extend.js` | Add `{ noWaitAfter: true }` to `addLocatorHandler` call |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_extend.js` — must pass
- No shellcheck — this is a JavaScript file
- No other files touched
- Only the `addLocatorHandler` call changes — no surrounding lines modified

---

## Definition of Done

- [ ] `{ noWaitAfter: true }` added as third argument to `addLocatorHandler` in `acg_extend.js`
- [ ] No other lines modified in `acg_extend.js`
- [ ] `node --check scripts/lib/acg/playwright/acg_extend.js` passes
- [ ] No other files modified
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg): addLocatorHandler noWaitAfter: true to prevent infinite re-invocation loop
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `acg_extend.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT run shellcheck — this is a JS file, run `node --check` only
- Do NOT change the handler body — only add the options argument
- Do NOT change `acg_credentials.js` — that file has no `addLocatorHandler` loop issue
