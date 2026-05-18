# Bug: acg-credentials — "Start Sandbox" click fails — element outside of viewport after handler fires

**Branch:** `k3d-manager-v1.4.6`
**Files:** `scripts/lib/acg/playwright/acg_credentials.js`

---

## Problem

`_clickStartSandbox` calls `buttonLocator.scrollIntoViewIfNeeded()` then
`buttonLocator.click({ force: true })`. The `addLocatorHandler` for "Extend Your Session"
fires **during** the click attempt — at the moment Playwright has resolved the element and
is mid-click. The handler extends the session, React re-renders the page and causes a layout
shift. The button moves out of the viewport. Playwright reports:

```
ERROR: locator.click: Element is outside of the viewport
Call log:
  - waiting for locator('button:has-text("Start Sandbox")').first()
    - locator resolved to <button ...>
  - attempting click action
    - scrolling into view if needed
    - done scrolling
```

`buttonLocator.click()` has no `.catch()` — the error propagates and exits the script.
The credential extraction retries once (same result), then `make up` fails with `Error 1`.

**Root cause:** The handler fires during the click window and causes a layout shift that
invalidates the scroll position established just before. `_clickStartSandbox` has no retry
when the click fails due to this race.

---

## Reproduction

1. Run `make up` with `CLUSTER_PROVIDER=k3s-aws`
2. The sandbox page loads and the "Extend Your Session" dialog appears while Playwright is
   trying to click "Start Sandbox"
3. `addLocatorHandler` fires — session extended — page re-renders
4. "Start Sandbox" button moves out of viewport
5. `buttonLocator.click({ force: true })` throws "Element is outside of the viewport"
6. Script exits with error

---

## Fix

Replace the final two lines of `_clickStartSandbox` (the scroll + click) with a retry loop
that re-scrolls and re-clicks up to 3 times, waiting 800 ms between attempts. Only the last
attempt propagates the error.

### Change 1 — `acg_credentials.js` lines 162–163: add retry loop in `_clickStartSandbox`

**Exact old block:**
```javascript
  await buttonLocator.scrollIntoViewIfNeeded().catch(() => {});
  await buttonLocator.click({ force: true });
}
```

**Exact new block:**
```javascript
  for (let _attempt = 0; _attempt < 3; _attempt++) {
    await buttonLocator.scrollIntoViewIfNeeded().catch(() => {});
    try {
      await buttonLocator.click({ force: true });
      break;
    } catch (_clickErr) {
      if (_attempt === 2) throw _clickErr;
      await page.waitForTimeout(800).catch(() => {});
    }
  }
}
```

**Why:** After the handler fires and the layout shifts, the button is back in the DOM —
it just needs a fresh scroll. The 800 ms wait lets the React re-render settle before the
next scroll attempt. Three attempts cover: initial failure (handler race), one retry
(post-settle), with the third propagating the original error if the button is genuinely
unclickable.

---

## Files Changed

| File | Changes |
|------|---------|
| `scripts/lib/acg/playwright/acg_credentials.js` | Change 1 — replace 2-line scroll+click at end of `_clickStartSandbox` with 8-line retry loop |

---

## Rules

- `node --check scripts/lib/acg/playwright/acg_credentials.js` — must pass
- No other files touched
- Only the final 2 lines of `_clickStartSandbox` change — all other functions unchanged

---

## Definition of Done

- [ ] `_clickStartSandbox` ends with the 8-line retry loop (lines 162–169)
- [ ] No other functions modified
- [ ] `node --check scripts/lib/acg/playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(acg-credentials): retry scroll+click in _clickStartSandbox when button moves out of viewport
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/lib/acg/playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT change the beginning of `_clickStartSandbox` (the prompt/session-extended dismiss blocks)
- Do NOT change any other function
