# ACG session check reports `ACG_SESSION_OK` on a signed-out page

**Date:** 2026-09-12
**Status:** OPEN — assigned to Codex.
**Branch (all work):** `fix/acg-prism-monogram-selector`
**Severity:** high — makes the `make credential-test` live gate untrustworthy and burns
~10 minutes of Playwright timeouts per run before failing.

## Problem

`LOGGED_IN_SELECTORS` in `scripts/lib/acg/playwright/lib/pluralsight_login.js` mixes two
different kinds of signal:

```js
const LOGGED_IN_SELECTORS = [
  '[data-testid="user-menu"]',
  '[aria-label="User menu"]',
  '[aria-label*="account" i]',
  'img[alt*="avatar" i]',
  '.psPrismAvatar .psPrismMonogram[aria-label]',
  'text=/Cloud Sandboxes/i',     // <-- page CONTENT, not identity
  'text=/Open Sandbox/i',        // <-- page CONTENT, not identity
];
```

The first five are **identity** markers — they only render for an authenticated user. The
last two are **page content** markers. Pluralsight renders the string `Cloud Sandboxes` on
the signed-OUT view of `SANDBOX_URL` too, so `pageLooksLoggedIn()` returns `true` for a
logged-out profile, and `acg_session_check.js` prints `ACG_SESSION_OK`.

## Observed failure (live run, 2026-09-12)

`K3DM_NONINTERACTIVE=1 make credential-test PROVIDER=aws` on
`fix/acg-prism-monogram-selector`, against a `pw-profile` whose Pluralsight session had
expired:

```
INFO: Chrome not running — launching with --remote-debugging-port=9222...
INFO: Checking Pluralsight (ACG) session in Antigravity browser...
ACG_SESSION_OK                              <-- FALSE GREEN
INFO: Using provider aws
INFO: Not signed in — clicking Sign In...   <-- contradicts the line above
ERROR: page.waitForURL: Timeout 300000ms exceeded.
  waiting for navigation to "**id.pluralsight.com**" until "load"
WARN: Credential extraction failed — restarting sandbox...
WARN: Sandbox card buttons did not appear within 30s. URL: https://app.pluralsight.com/id | Buttons: ["Sign in"]
ERROR: Neither Delete Sandbox nor Open Sandbox visible. URL: https://app.pluralsight.com/id | Buttons: ["Sign in"]
ERROR: Sandbox restart failed — delete it manually and re-run.
make: *** [credential-test] Error 1
```

Two consequences of the false green:

1. The `K3DM_NONINTERACTIVE=1` hard-fail branch in `acg_session_check.js` is **never
   reached**, so an expired session surfaces five minutes later as an unrelated-looking
   `waitForURL` timeout in extraction instead of immediately as `ACG_SESSION_EXPIRED`.
2. The interactive manual-login wait is never reached either — so on a TTY the operator is
   never prompted to sign in, which is why "the script still requires a human login after
   a while" presents as a mysterious timeout rather than a prompt.

## Root cause, in two layers

- **Detection (this bug).** Content selectors cannot distinguish signed-in from signed-out
  on the same URL. There is no negative check at all — nothing looks for `Sign in`.
- **Recovery (operational, out of scope for the code fix).** The `pw-profile` Pluralsight
  session expires periodically. `_cdp_ensure_acg_session` in `scripts/lib/acg/cdp.sh`
  sources credentials from `_secret_load_data k3dm-acg-pluralsight username|password`, and
  that Keychain item does **not exist** on the operator's machine, so `_autoLogin` returns
  `false` at its `!ACG_USERNAME || !ACG_PASSWORD` guard without trying anything and without
  saying why. See "Operator action" below.

This is **not** caused by commit `a8342e1` on this branch — that commit only *adds*
`.psPrismAvatar .psPrismMonogram[aria-label]`. It is, however, the reason `a8342e1`'s own
live gate cannot be trusted, which is why the fix lands on the same branch.

## Required change

### 1. `scripts/lib/acg/playwright/lib/pluralsight_login.js`

**a. Drop the two content selectors from `LOGGED_IN_SELECTORS`.** Replace the block
verbatim:

```js
const LOGGED_IN_SELECTORS = [
  '[data-testid="user-menu"]',
  '[aria-label="User menu"]',
  '[aria-label*="account" i]',
  'img[alt*="avatar" i]',
  '.psPrismAvatar .psPrismMonogram[aria-label]',
  'text=/Cloud Sandboxes/i',
  'text=/Open Sandbox/i',
];
```

with:

```js
const LOGGED_IN_SELECTORS = [
  '[data-testid="user-menu"]',
  '[aria-label="User menu"]',
  '[aria-label*="account" i]',
  'img[alt*="avatar" i]',
  '.psPrismAvatar .psPrismMonogram[aria-label]',
];

const SIGNED_OUT_SELECTORS = [
  'a[href*="/id/signin"]',
  'button:has-text("Sign in")',
  'a:has-text("Sign in")',
];
```

`.psPrismAvatar .psPrismMonogram[aria-label]` becomes the load-bearing positive signal —
that is exactly what `a8342e1` added it for.

**b. Add a negative check.** Insert after `anyVisible`:

```js
function urlLooksSignedOut(url) {
  return typeof url === 'string' && /^https:\/\/app\.pluralsight\.com\/id(\/|$|\?)/.test(url);
}

async function pageLooksSignedOut(page, timeoutMs = 1500) {
  if (urlLooksSignedOut(page.url())) {
    return true;
  }
  return anyVisible(page, SIGNED_OUT_SELECTORS, timeoutMs);
}
```

**c. Gate `pageLooksLoggedIn` on it.** Replace the body of the retry loop so a positive
signed-out signal short-circuits to `false` without burning the remaining attempts:

```js
async function pageLooksLoggedIn(page, options) {
  const { attempts = 1, perSelectorTimeoutMs = 1500, settleMs = 1000 } = options || {};
  for (let i = 0; i < attempts; i += 1) {
    if (await pageLooksSignedOut(page, perSelectorTimeoutMs)) {
      return false;
    }
    if (await anyVisible(page, LOGGED_IN_SELECTORS, perSelectorTimeoutMs)) {
      return true;
    }
    if (i < attempts - 1) {
      await page.waitForLoadState('networkidle', { timeout: 5000 }).catch(() => {});
      await page.waitForTimeout(settleMs);
    }
  }
  return false;
}
```

**d. Export the new symbols** — add `SIGNED_OUT_SELECTORS`, `pageLooksSignedOut` and
`urlLooksSignedOut` to `module.exports`, keeping the existing alphabetical-ish grouping
(constants first, then functions).

### 2. `scripts/lib/acg/acg_session_check.js`

Make a missing Keychain item say so. Replace:

```js
    if (process.env.ACG_USERNAME && process.env.ACG_PASSWORD) {
      console.error('INFO: Session not authenticated — attempting headless Pluralsight login...');
```

with:

```js
    if (!process.env.ACG_USERNAME || !process.env.ACG_PASSWORD) {
      console.error('WARN: No ACG credentials available — unattended login is disabled. Create the Keychain item k3dm-acg-pluralsight with username and password fields to enable it.');
    }

    if (process.env.ACG_USERNAME && process.env.ACG_PASSWORD) {
      console.error('INFO: Session not authenticated — attempting headless Pluralsight login...');
```

Do NOT print, log, or echo the credential values themselves — only their absence.

### 3. `scripts/lib/acg/tests/providers/pluralsight_login.test.js`

The existing fixtures treat `Cloud Sandboxes` / `Open Sandbox` as the logged-in markers and
will fail once those move out of `LOGGED_IN_SELECTORS`. Update them and add coverage:

- In `makePage` and `makeSlowRenderPage`, change the `isLoggedInSelector` predicate from
  `selector.includes('Cloud Sandboxes') || selector.includes('Open Sandbox')` to
  `selector.includes('psPrismMonogram')`.
- Both fixtures must return **not visible** for every selector in `SIGNED_OUT_SELECTORS`
  (`href*="/id/signin"`, `has-text("Sign in")`), or the new negative gate will short-circuit
  the existing render-race tests to `false`. `makePage`'s catch-all `true` default is the
  trap here — make signed-out selectors explicitly `false`.
- `makeSlowRenderPage`'s `url()` already returns the sandbox URL, which is correct; keep it.

Add a new `describe` block with at least these three cases:

1. **Reproduces the bug.** A page whose URL is `SANDBOX_URL`, where `Cloud Sandboxes` is
   visible but no identity selector and no signed-out selector is — `pageLooksLoggedIn`
   must return `false`. (Before the fix this returned `true`.)
2. **Signed-out short-circuit by markers.** A page at `SANDBOX_URL` with a visible
   `Sign in` button — `pageLooksLoggedIn(page, { attempts: 4, settleMs: 0 })` must return
   `false` and must NOT call `waitForLoadState` (proving it short-circuited rather than
   retrying four times).
3. **Signed-out short-circuit by URL.** `urlLooksSignedOut('https://app.pluralsight.com/id')`
   and `.../id/signin` are `true`; `SANDBOX_URL` and
   `https://app.pluralsight.com/identity-docs` are `false`.

## Operator action (NOT part of this change — do not script it)

Unattended recovery from an expired session needs one of:

- Keychain item `k3dm-acg-pluralsight` with `username` and `password` fields, so
  `_autoLogin` has something to use; or
- a one-time manual sign-in in the CDP Chrome profile at
  `~/.local/share/k3d-manager/pw-profile`.

Note that `loginWithPage` returns `{ ok: false, reason: 'mfa_required' }` when Pluralsight
issues an MFA challenge — unattended login cannot clear that, so MFA-protected accounts
will always need the manual path.

## Definition of done

- [ ] `pageLooksLoggedIn` returns `false` for a signed-out page at `SANDBOX_URL`.
- [ ] `cd scripts/lib/acg && npm run check` — clean.
- [ ] `cd scripts/lib/acg && npm test` — all jest suites green, including the three new cases.
- [ ] `make bats` — 132 BATS green (no shell files change; this is a regression guard).
- [ ] `make lint && make shellcheck-lib` — zero new warnings.
- [ ] No file outside the three listed above is modified.

## Gate before PR

`make credential-test PROVIDER=aws` must run live and pass. It cannot pass until the
operator action above is done. With this fix in place, a still-expired session fails in
**seconds** with `ACG_SESSION_EXPIRED` instead of after ~10 minutes of `waitForURL`
timeouts — which is itself the first observable confirmation that the fix works.

## What NOT to do

- Do NOT create a PR.
- Do NOT merge, and do NOT commit to `main`.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the three listed under "Required change".
- Do NOT touch `cdp.sh`, the Makefile, or anything under `scripts/lib/acg/bin/`.
- Do NOT run `make credential-test`, `make restart-test`, `make extend-test`, or any other
  live-sandbox target — one agent owns the ACG sandbox and it is not you.
- Do NOT print, echo, or log credential values.

---

## CORRECTION 2026-09-12 — the root cause stated above is WRONG

**Status: the stated root cause is disproved. The shipped change (`308bb3c`) is still
sound, but it is NOT a fix for the observed `credential-test` failure.**

The claim above — that `text=/Cloud Sandboxes/i` matches the signed-OUT view of
`SANDBOX_URL` and so produces a false `ACG_SESSION_OK` — was asserted from reading source,
never measured. It is false.

### Evidence

A throwaway Chrome profile (guaranteed signed out) on port 9333, navigated to
`SANDBOX_URL`:

```
FINAL URL : https://app.pluralsight.com/id
TITLE     : Sign In | Pluralsight
  visible=false count=0   text=/Cloud Sandboxes/i
  visible=false count=0   text=/Open Sandbox/i
  visible=false count=0   .psPrismAvatar .psPrismMonogram[aria-label]
  visible=true  count=2   a[href*="/id/signin"]
  visible=true  count=1   button:has-text("Sign in")
  visible=true  count=2   a:has-text("Sign in")
```

A signed-out `SANDBOX_URL` **redirects** to the sign-in page. `Cloud Sandboxes` and
`Open Sandbox` have **count 0** — they are not merely invisible, they are absent from the
DOM. They cannot produce a false green.

Confirmed end-to-end: `acg_session_check.js` at the **pre-fix** commit `a8342e1`, run
against that signed-out profile, printed `ACG_SESSION_EXPIRED` and exited in **8 seconds**.
The bug as described does not reproduce because it does not exist.

### What the change at `308bb3c` is actually worth

- The negative gate (`SIGNED_OUT_SELECTORS`, `pageLooksSignedOut`, `urlLooksSignedOut`) is
  **validated by the measurement above** — all three selectors match the real signed-out
  page, and the final URL `https://app.pluralsight.com/id` is exactly what
  `urlLooksSignedOut` recognizes. Keep it: it makes signed-out detection explicit and
  fail-fast instead of relying on the absence of positive signals.
- Removing the two content selectors is defensible hygiene — they are page content, not
  identity — but it fixed no live defect. Do not describe it as a bug fix.
- The missing-Keychain warning stands on its own merit.

### The real cause of the observed failure

Filed separately as
`docs/bugs/2026-09-12-acg-signin-wait-targets-dead-id-pluralsight-host.md`:
`handleSignIn` in `scripts/lib/acg/playwright/lib/sandbox.js:112` waits for
`**id.pluralsight.com**`, a hostname that **no longer resolves in DNS**. That is the
300000ms timeout in the failing log, and it is deterministic.

### Process note

The failing run's log was read correctly; the inference from it was not verified before
being written into a spec and handed to an implementer. A throwaway `--user-data-dir` is a
guaranteed signed-out profile and costs about one minute — that measurement should have
come before the spec, not after the commit.
