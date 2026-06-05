# Bug: acg_restart — "Delete Sandbox" click fails — element outside of viewport after panel animation

**Branch (lib-acg):** `fix/next-improvements-5` (already current)
**File:** `playwright/acg_restart.js`

---

## Problem

After `Open Sandbox` is clicked and the panel expands, `deleteBtn.click({ force: true })`
at line 273 throws:

```
ERROR: locator.click: Element is outside of the viewport
Call log:
  - waiting for locator('button:has-text("Delete Sandbox")').first()
    - locator resolved to <button ...>
  - attempting click action
    - scrolling into view if needed
    - done scrolling
```

Playwright scrolls the button into view, but the panel open animation causes a layout shift
that moves the button back out of the viewport before the click lands. `force: true` skips
actionability checks but does not re-scroll after a layout shift.

**Root cause:** Line 273 calls `deleteBtn.click({ force: true })` with no
`scrollIntoViewIfNeeded` and no retry. The panel animation runs concurrently and invalidates
the scroll position, leaving the button outside the viewport on the first (and only) attempt.

---

## Fix

Replace the single `deleteBtn.click({ force: true })` at line 273 with the same
scroll + retry loop already applied to `_clickStartSandbox` in `acg_credentials.js`.

### Change — `playwright/acg_restart.js`: scroll + retry Delete Sandbox click

**Exact old block (lines 272–273):**

```javascript
    console.error('INFO: Clicking Delete Sandbox...');
    await deleteBtn.click({ force: true });
```

**Exact new block:**

```javascript
    console.error('INFO: Clicking Delete Sandbox...');
    for (let _attempt = 0; _attempt < 3; _attempt++) {
      await deleteBtn.scrollIntoViewIfNeeded().catch(() => {});
      try {
        await deleteBtn.click({ force: true });
        break;
      } catch (_clickErr) {
        if (_attempt === 2) throw _clickErr;
        await page.waitForTimeout(800).catch(() => {});
      }
    }
```

**Why:** Each retry re-scrolls the button into view. The 800 ms wait lets the panel
animation settle before the next attempt. Three attempts cover: initial failure (animation
race), one retry (post-settle), third propagates if genuinely unclickable.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_restart.js` | Replace 1-line click with 8-line scroll + retry loop |

---

## Rules

- `node --check playwright/acg_restart.js` must pass
- Code change limited to the listed file(s); CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] `playwright/acg_restart.js` line 273: single `deleteBtn.click({ force: true })` replaced with 8-line scroll + retry loop
- [ ] No other functions or files modified
- [ ] `node --check playwright/acg_restart.js` passes
- [ ] Committed and pushed to `fix/next-improvements-5` on lib-acg
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-restart): scroll + retry Delete Sandbox click — panel animation causes viewport shift
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_restart.js`
- Do NOT commit to `main`
- Do NOT change any other function in the file
