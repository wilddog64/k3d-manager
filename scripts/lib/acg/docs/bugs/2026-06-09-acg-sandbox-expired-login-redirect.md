# Bugfix: v0.1.4 — expired sandbox retry lands on login page after stale Hands-on hop

**Branch:** `fix/acg-sandbox-expired-login-retry`
**Files:** `playwright/lib/sandbox.js`, `CHANGELOG.md`, `memory-bank/activeContext.md`, `memory-bank/progress.md`

---

## Problem

When a sandbox has expired, `acg-up` can fail while Playwright is recovering the ACG page state.
The current retry branch still routes through the older Hands-on URL before returning to the
sandbox page. On older Pluralsight routing this intermediate hop often lands on `/id` instead of
the sandbox page, which leaves the flow on the login screen and causes credential extraction to
fail.

This is intermittent by nature:
- deleting and re-creating the sandbox works fine
- re-running after expiry often works if the page is already back on the sandbox route
- the regression appears when the stale retry hop is taken after the sandbox has expired

**Root cause:** the retry logic still uses the old Hands-on intermediate navigation instead of
going directly back to `targetUrl`, so the resumed browser session is more likely to be redirected
to login and lose the sandbox context.

---

## Fix

### Change 1 — `playwright/lib/sandbox.js`: remove the stale Hands-on retry hop

**Expected behavior:**
- when the sandbox route is no longer active, retry directly to `targetUrl`
- do not navigate through `https://app.pluralsight.com/hands-on` as an intermediate recovery step
- if the retry lands on `/id`, `sign-in`, or `login`, fail fast with a clear expired-session error
- keep existing provider-scoped button/credential checks intact

**High-level change:**
1. delete the intermediate Hands-on navigation from the sandbox recovery block
2. navigate directly back to `targetUrl`
3. add an explicit login-page detection after the retry navigation
4. surface a clear message telling the user to re-open or re-create the sandbox if the session is expired

---

## Files Changed

| File | Change |
|------|--------|
| `playwright/lib/sandbox.js` | Remove the stale Hands-on retry hop and fail fast on login-page redirects after sandbox expiry |
| `CHANGELOG.md` | Add an `[Unreleased]` note for the sandbox-expiry login redirect regression |

---

## Rules

- `node --check playwright/lib/sandbox.js` must pass
- keep the fix narrowly scoped to the retry path and expired-session detection
- do not reintroduce a retry hop through `hands-on`

---

## Definition of Done

- [ ] Retry goes directly to `targetUrl` after sandbox expiry
- [ ] Login-page redirects fail fast with a clear expired-session message
- [ ] `node --check scripts/lib/acg/playwright/lib/sandbox.js` passes
- [ ] Bugfix branch committed and pushed to `main` via PR
- [ ] `main` merged back into the active `feat/v0.1.4` line after the fix lands

**Commit message (exact):**
```
fix(sandbox): remove stale Hands-on retry hop — expired sandbox lands on login page
```

---

## What NOT to Do

- Do NOT edit the subtree directly in `k3d-manager`
- Do NOT pull the newer `feat/v0.1.4` feature work into `main`
- Do NOT keep retrying through the old Hands-on URL
- Do NOT silently continue when the page is clearly on login
