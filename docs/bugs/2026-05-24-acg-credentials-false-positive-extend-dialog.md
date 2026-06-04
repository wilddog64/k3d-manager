# Bug: False-positive "Extend Your Session" dialog detection in acg_credentials.js

**Date:** 2026-05-24
**File:** `playwright/acg_credentials.js`
**Branch:** `fix/next-improvements-6`
**Commit:** `fb3ae33`

---

## Problem

`acg_credentials.js` prints `"Extend Your Session" dialog detected — clicking Cancel via DOM...`
on every `make up` run even when no dialog is visible on screen. This triggers the
`_waitForCredentials` 420s poll unconditionally, adding unnecessary delay.

**Root cause:** Two locations in `acg_credentials.js` check for the dialog with no visibility
guard:

1. Entry check (line ~248): `.some(d => ... && d.offsetParent !== null)` — missing
   `getComputedStyle` check for `display` and `visibility`.
2. Local `_dismissExtendYourSessionDialog` (line ~262): `.some(d => (d.innerText || '').includes('Extend Your Session'))` —
   no `offsetParent`, no `getComputedStyle` guard at all.

Pluralsight's SPA keeps the dialog element in the DOM between page renders. When the element
is hidden via `display:none` or `visibility:hidden`, `innerText` still returns non-empty text
on some browser builds, causing both checks to false-positive.

---

## Fix

Added `offsetParent !== null && getComputedStyle(d).display !== 'none' && getComputedStyle(d).visibility !== 'hidden'`
to the entry check, the local `_dismissExtendYourSessionDialog` detection and find calls, and the
`_waitForSandboxEntry` `hasExtendDialog` predicate in `acg_credentials.js`. Also applied the same
`visibility !== 'hidden'` extension to `acg_restart.js` so all files use the identical three-part guard.

**Commit:** `fb3ae33` on `fix/next-improvements-6`

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Visibility guard on entry check, local dismiss function, and `_waitForSandboxEntry` hasExtendDialog predicate |
| `playwright/acg_restart.js` | Added `visibility !== 'hidden'` to align all guards to the same three-part predicate |
| `.github/copilot-instructions.md` | Narrowed `addLocatorHandler` rule to toast/overlay dismissal; clarified modal dialog dismissal uses DOM clicks intentionally |
