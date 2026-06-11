# Bug: sandbox.js addLocatorHandler trigger matches 2 elements — strict mode violation

**Date:** 2026-06-11
**Repo:** lib-acg
**Branch:** feat/v0.1.5
**File:** `playwright/lib/sandbox.js`

---

## Symptom

`make credential-test PROVIDER=<any>` fails with:

```
ERROR: page.waitForSelector: Error: strict mode violation: locator('text=/sandbox has been extended|session extended/i') resolved to 2 elements:
    1) <h3 class="pando-c_neutral.text.300">Session extended</h3>
    2) <p class="pando-mb_md">Your sandbox has been extended.</p>
```

Affects AWS and Azure both — `startSandbox` is shared across all providers.

---

## Root Cause

`sandbox.js` line 408: the `addLocatorHandler` trigger locator
`text=/sandbox has been extended|session extended/i` matches two elements
simultaneously (the toast `<h3>` heading AND the `<p>` body text). Playwright
enforces strict mode on this locator when internally watching for it to become
visible, resulting in a fatal error that aborts credential extraction.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js` line 408: scope trigger to heading element only

**Exact old line:**

```javascript
    page.locator('text=/sandbox has been extended|session extended/i'),
```

**Exact new line:**

```javascript
    page.locator('h3, h2').filter({ hasText: /sandbox has been extended|session extended/i }).first(),
```

This scopes the trigger to heading elements only — the `<h3>` toast title — avoiding
the `<p>` body text match that causes the strict mode violation.

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Line 408: scope addLocatorHandler trigger to heading elements |

---

## Rules

- `node --check playwright/lib/sandbox.js` must pass
- No other files touched

---

## Definition of Done

- [ ] Line 408 trigger changed to `page.locator('h3, h2').filter({ hasText: /.../ }).first()`
- [ ] `node --check playwright/lib/sandbox.js` passes
- [ ] Committed and pushed to `feat/v0.1.5`
- [ ] memory-bank updated with commit SHA and task status (in k3d-manager repo)

**Commit message (exact):**
```
fix(sandbox): scope addLocatorHandler trigger to heading — text regex matched h3+p causing strict mode violation
```

---

## What NOT to Do

- Do NOT create a PR yourself — Claude handles PR creation after verifying the commit
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `playwright/lib/sandbox.js`
- Do NOT commit to `main` — work on `feat/v0.1.5`
