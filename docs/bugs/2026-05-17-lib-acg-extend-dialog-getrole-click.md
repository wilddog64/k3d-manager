# Bug: lib-acg — `locator('button', { hasText: 'Cancel' })` silently times out; Cancel may not be a native `<button>` element

**Branch (lib-acg work):** `fix/acg-credentials-extend-dialog`
**Files (lib-acg):**
- `playwright/acg_credentials.js` — replace `locator('button', { hasText: 'Cancel' })` with `getByRole('button', { name: 'Cancel' })`; replace silent `.catch(() => {})` with error-logging catch

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

`locator('button', { hasText: 'Cancel' }).click({ timeout: 5000 }).catch(() => {})` does not
dismiss the dialog. The silent `.catch(() => {})` hides whether the failure is:
- selector timeout (Cancel button not a native `<button>` element → `locator('button')` finds nothing)
- actionability failure (element found but intercepted)
- click sent but React ignored it

**Root cause (most likely):** Pluralsight's React component library may render Cancel as a
`<div role="button">` or a custom component root element, not a native `<button>`. The
`locator('button', ...)` selector only matches native `<button>` elements — it silently times
out and the `.catch(() => {})` hides the TimeoutError.

**Fix:**
1. Replace `locator('button', { hasText: 'Cancel' })` with `getByRole('button', { name: 'Cancel' })`.
   `getByRole` matches any element with ARIA role `button` (native `<button>`, `<div role="button">`,
   `<a role="button">`, etc.) with accessible name "Cancel". This is the correct selector for
   a React component library where the root element may not be a native button.
2. Replace `.catch(() => {})` with `.catch(e => console.error('WARN: Cancel click error:', e.message))`
   so the next run reveals the actual failure mode (TimeoutError = selector problem;
   ActionabilityError = element found but blocked; no error = click sent but React ignored it).

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: getByRole + error-logging catch

**Exact old block (lines 379–395, inside `_dismissExtendYourSessionDialog`, after the `_dialogVisible` check):**

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

**Exact new block:**

```javascript
        console.error('INFO: "Extend Your Session" dialog detected — clicking Cancel...');
        await page.locator('[role="dialog"]')
          .filter({ hasText: 'Extend Your Session' })
          .getByRole('button', { name: 'Cancel' })
          .click({ timeout: 5000 })
          .catch(e => console.error('WARN: Cancel click error:', e.message));
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
| `playwright/acg_credentials.js` | `locator('button', { hasText })` → `getByRole('button', { name })`; silent catch → error-logging catch |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- No other files modified

---

## Definition of Done

- [ ] `locator('button', { hasText: 'Cancel' })` replaced with `getByRole('button', { name: 'Cancel' })`
- [ ] `.catch(() => {})` replaced with `.catch(e => console.error('WARN: Cancel click error:', e.message))`
- [ ] `waitForFunction` timeout remains 5000
- [ ] WARN + continue on timeout (no `process.exit(1)`)
- [ ] INFO log still says `"clicking Cancel..."` (unchanged)
- [ ] `node --check playwright/acg_credentials.js` passes
- [ ] No other files modified
- [ ] Committed to `fix/acg-credentials-extend-dialog` in lib-acg
- [ ] `git push origin fix/acg-credentials-extend-dialog` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat` output

**Commit message (exact):**
```
fix(acg): use getByRole to click Cancel in extend dialog; log click errors
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/acg_credentials.js`
- Do NOT commit to `main` — work on `fix/acg-credentials-extend-dialog`
- Do NOT modify k3d-manager — this spec is lib-acg only
- Do NOT restore `process.exit(1)`
- Do NOT restore silent `.catch(() => {})` — error logging is required for diagnosis
- Do NOT touch `acg_extend.js`
