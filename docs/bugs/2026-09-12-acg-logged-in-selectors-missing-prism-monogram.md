# ACG logged-in selector set is missing the Pluralsight Prism avatar monogram

**Date:** 2026-09-12
**Status:** OPEN — carried over from the retired `wilddog64/lib-acg` repo
**Source:** unported change from `lib-acg` PR #47 (`fix/acg-session-profile-selector`,
commit `7ffdd5f`), opened 2026-07-30 and never merged. Recorded here so the fix is not
lost when the legacy repo is archived (absorption Phase 3).

## Problem

`LOGGED_IN_SELECTORS` in `scripts/lib/acg/playwright/lib/pluralsight_login.js` recognizes
only the older user-menu, account-label, avatar-image and Cloud Sandboxes markers:

```js
const LOGGED_IN_SELECTORS = [
  '[data-testid="user-menu"]',
  '[aria-label="User menu"]',
  '[aria-label*="account" i]',
  'img[alt*="avatar" i]',
  'text=/Cloud Sandboxes/i',
  'text=/Open Sandbox/i',
];
```

The current Pluralsight UI renders the signed-in identity as a Prism monogram inside
`.psPrismAvatar`, which none of these match. On the legacy tree this produced a false
`Pluralsight login timeout` from `make credential-test PROVIDER=aws` against an
already-authenticated session.

## Why it may not reproduce here

`scripts/lib/acg/acg_session_check.js` navigates to `SANDBOX_URL` first and then probes
with `pageLooksLoggedIn(page, { attempts: 4 })`, so the sandbox-page text selectors
(`Cloud Sandboxes` / `Open Sandbox`) usually match before the avatar is needed. The
missing selector is therefore a robustness gap, not a confirmed live failure — it removes
the only identity-based signal, leaving the check dependent on page-content text.

## Proposed fix

Add the monogram selector to `LOGGED_IN_SELECTORS`:

```js
  '.psPrismAvatar .psPrismMonogram[aria-label]',
```

The second half of the legacy change — an early `pageLooksLoggedIn` return before
navigating — is deliberately NOT ported: the divergent `acg_session_check.js` here already
handles navigation failure (`navigatedToSandbox`) and retries, so an unconditional
pre-navigation probe would add a redundant path.

## Gate before PR

`make credential-test PROVIDER=aws` must pass live (serialize-live-sandbox: one agent per
ACG sandbox) — a selector change cannot be verified by unit tests alone.

## Already covered, for the record

The other half of lib-acg PR #47 — the undefined `_sts_valid` call in
`bin/acg-credential-test` — was fixed independently and earlier in this repo; see
`docs/bugs/2026-06-23-acg-credential-test-undefined-sts-valid.md`. No port needed.
