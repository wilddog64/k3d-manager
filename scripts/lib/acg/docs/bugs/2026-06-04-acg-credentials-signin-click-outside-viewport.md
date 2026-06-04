# Bugfix: acg_credentials — sign-in click fails with "element outside viewport"

**Branch:** `fix/signin-click-outside-viewport` (merged to `main` via PR)
**File:** `playwright/acg_credentials.js`

---

## Problem

When the Pluralsight login session has expired, a session-timeout overlay renders over the
page. The Sign In link exists in the header but is positioned behind the intercepting element.
`signInLink.click()` has no `force: true`, so Playwright's actionability check rejects it
with "element is outside of the viewport" and the credential extraction fails.

**Root cause:** `signInLink.click()` at line 418 lacks `{ force: true }`, causing Playwright
to abort when the element is unreachable due to an overlapping session-timeout modal.

---

## Reproduction

1. Let the Pluralsight browser session expire (log out or wait for session timeout).
2. Run `acg_get_credentials` targeting a sandbox URL.
3. Observe the error: `ERROR: element is outside of the viewport` followed by `acg-up` failure.

---

## Fix

### Change 1 — `playwright/acg_credentials.js`: use DOM-triggered click to bypass intercepting overlay

**Exact old block:**
```javascript
  console.error('INFO: Not signed in — clicking Sign In...');
  await signInLink.click();
  await page.waitForURL('**id.pluralsight.com**', { timeout: 300000 }); // "Patient Bridge"
```

**Exact new block:**
```javascript
  console.error('INFO: Not signed in — clicking Sign In...');
  await signInLink.evaluate(el => el.click());
  await page.waitForURL('**id.pluralsight.com**', { timeout: 300000 }); // "Patient Bridge"
```

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/acg_credentials.js` | Add `{ force: true }` to `signInLink.click()` |

---

## Rules

- `node --check playwright/acg_credentials.js` — zero errors
- No other code files touched

---

## Definition of Done

- [ ] `signInLink` uses `evaluate(el => el.click())` (DOM-triggered, bypasses intercepting overlay)
- [ ] `node --check playwright/acg_credentials.js` clean
- [ ] Committed, pushed to `fix/signin-click-outside-viewport`, and merged to `main` via PR

**Commit message (exact):**
```
fix(playwright): force sign-in click to bypass session-timeout overlay
```

## What NOT to Do

- Do NOT modify any code file other than `playwright/acg_credentials.js`
- Do NOT skip pre-commit hooks (`--no-verify`)
