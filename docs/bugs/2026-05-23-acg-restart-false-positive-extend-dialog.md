# Bug: False-positive "Extend Your Session" dialog detection in acg_restart.js

**Date:** 2026-05-23
**File:** `playwright/acg_restart.js`
**Branch:** `fix/next-improvements-4`

---

## Problem

`acg_restart.js` prints `"Extend Your Session" dialog detected — clicking Cancel via DOM...`
when no dialog is actually visible on screen. This fires immediately after clicking Open Sandbox,
then the script falls through to `acg_credentials.js` which waits the full 420s.

**Root cause:** `_dismissExtendYourSessionDialog` (line 32–35) matches dialog elements using
`innerText.includes('Extend Your Session')` with no visibility guard. When the Pluralsight
SPA renders the dialog element in the DOM but keeps it hidden via CSS (e.g. `visibility:hidden`
or an ancestor with `display:none`), `innerText` may still return non-empty text, triggering
a false positive. The sibling function `_isExtendYourSessionVisible` (lines 50–58) already has
the correct `offsetParent !== null && getComputedStyle(d).display !== 'none'` guard — it is
just not reused in `_dismissExtendYourSessionDialog`.

---

## Reproduction

Run `make up` on a sandbox that has no active session extension prompt. Observe:
```
INFO: Clicking Open Sandbox...
INFO: "Extend Your Session" dialog detected — clicking Cancel via DOM...
INFO: Waiting for credentials to populate (up to 420s)...
```
Expected: the second line should not appear when no dialog is visible.

---

## Fix

### Change 1 — `playwright/acg_restart.js` lines 31–35

Add the same `offsetParent` + `getComputedStyle` visibility guard used in `_isExtendYourSessionVisible`.

**Exact old block:**

```javascript
async function _dismissExtendYourSessionDialog(page) {
  const visible = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
      .some(d => (d.innerText || '').includes('Extend Your Session'))
  ).catch(() => false);
```

**Exact new block:**

```javascript
async function _dismissExtendYourSessionDialog(page) {
  const visible = await page.evaluate(() =>
    Array.from(document.querySelectorAll('[data-testid="extend-sandbox-modal"], [role="dialog"], [role="alertdialog"]'))
      .some(d =>
        (d.innerText || '').includes('Extend Your Session') &&
        d.offsetParent !== null &&
        getComputedStyle(d).display !== 'none'
      )
  ).catch(() => false);
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_restart.js` | Add visibility guard to `_dismissExtendYourSessionDialog` to match `_isExtendYourSessionVisible` |

---

## Before You Start

1. `git -C /Users/cliang/src/gitrepo/personal/lib-acg pull origin fix/next-improvements-4`
2. Read this spec in full before touching any files
3. Read `playwright/acg_restart.js` lines 31–58 — confirm the old block at line 32 and the existing visibility check in `_isExtendYourSessionVisible` at line 51
4. Confirm you are on branch `fix/next-improvements-4` — never commit to `main`

---

## Rules

- `node --check playwright/acg_restart.js` — must pass with no errors
- Code change limited to `playwright/acg_restart.js`; CHANGELOG and memory-bank updates may also be required

---

## Definition of Done

- [ ] `_dismissExtendYourSessionDialog` lines 32–35 updated with visibility guard
- [ ] `node --check playwright/acg_restart.js` passes
- [ ] Committed and pushed to `fix/next-improvements-4`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(acg-restart): add visibility guard to _dismissExtendYourSessionDialog to prevent false-positive extend dialog detection
```

---

## What NOT to Do

- Do NOT modify `_isExtendYourSessionVisible` — it already has the correct check
- Do NOT modify any file other than `playwright/acg_restart.js`
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT commit to `main` — work on `fix/next-improvements-4`
