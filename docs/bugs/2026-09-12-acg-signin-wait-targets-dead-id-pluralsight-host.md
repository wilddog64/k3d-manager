# ACG sign-in recovery waits 300s on `id.pluralsight.com`, a host that no longer exists

**Date:** 2026-09-12
**Status:** OPEN — root cause measured, fix not yet written.
**Branch (all work):** `fix/acg-prism-monogram-selector`
**Severity:** high — deterministic 5-minute hang, then a 5-minute repeat in the restart
path, on every run that needs to sign in. This is the real cause of the failed
`make credential-test PROVIDER=aws` gate on 2026-09-12.

## Problem

`scripts/lib/acg/playwright/lib/sandbox.js:112`, inside `handleSignIn`:

```js
await signInLink.click();
await page.waitForURL('**id.pluralsight.com**', { timeout: 300000 });
```

`id.pluralsight.com` **does not resolve**:

```
$ dig +short id.pluralsight.com
(no answer)
$ curl -L https://id.pluralsight.com/
curl: (6) Could not resolve host: id.pluralsight.com
```

Pluralsight moved identity to a **path on the main host** — `https://app.pluralsight.com/id`
— measured directly against a signed-out profile:

```
FINAL URL : https://app.pluralsight.com/id
TITLE     : Sign In | Pluralsight
```

So the URL pattern can never match. `waitForURL` runs its full 300000ms and throws. Because
`_extractCredentials` catches and falls through to the sandbox-restart path, which calls
`handleSignIn` again, a single run burns **two** 300s timeouts before exiting 1.

The same dead host appears in the sign-in link selector one line up
(`sandbox.js:104`):

```js
const signInLink = page.locator('a[href*="id.pluralsight.com"], a:has-text("Sign In"), button:has-text("Sign In")').first();
```

That one still works only because the `:has-text("Sign In")` alternatives match; the
`href` alternative is dead weight. Measured on the live signed-out page:
`a[href*="/id/signin"]` → count 2, `button:has-text("Sign in")` → count 1.

## Observed failure

```
INFO: Not signed in — clicking Sign In...
ERROR: page.waitForURL: Timeout 300000ms exceeded.
  waiting for navigation to "**id.pluralsight.com**" until "load"
WARN: Credential extraction failed — restarting sandbox...
WARN: Sandbox card buttons did not appear within 30s. URL: https://app.pluralsight.com/id | Buttons: ["Sign in"]
ERROR: Neither Delete Sandbox nor Open Sandbox visible. URL: https://app.pluralsight.com/id | Buttons: ["Sign in"]
```

Note the reported URL in the restart path is already `https://app.pluralsight.com/id` —
the browser had arrived at the sign-in page immediately. Only the *matcher* was wrong.

## Required change

### `scripts/lib/acg/playwright/lib/sandbox.js`

1. **Line 104** — drop the dead host from the sign-in link selector and add the current
   identity path:

```js
  const signInLink = page.locator('a[href*="/id/signin"], a[href*="/id"], a:has-text("Sign In"), button:has-text("Sign In")').first();
```

2. **Line 112** — wait for the identity page by its real URL shape. Replace:

```js
  await page.waitForURL('**id.pluralsight.com**', { timeout: 300000 });
```

with a predicate that accepts the current host+path form, and a timeout that fails in
seconds rather than minutes when the navigation does not happen:

```js
  await page.waitForURL(
    (url) => /^https:\/\/app\.pluralsight\.com\/id(\/|$|\?)/.test(url.toString()),
    { timeout: 60000 },
  );
```

3. **Line 143** — `waitForURL('**app.pluralsight.com**', { timeout: 300000 })` is the
   post-login wait. It matches the right host, but it will also match the sign-in page
   itself (`app.pluralsight.com/id`), so it can return while still unauthenticated. Tighten
   it to require leaving the identity path:

```js
  await page.waitForURL(
    (url) => /^https:\/\/app\.pluralsight\.com\//.test(url.toString())
      && !/^https:\/\/app\.pluralsight\.com\/id(\/|$|\?)/.test(url.toString()),
    { timeout: 300000 },
  );
```

Keep 300000ms here — this one legitimately waits on a human completing login.

### Reuse, do not duplicate

`urlLooksSignedOut` already encodes the `app.pluralsight.com/id` shape in
`scripts/lib/acg/playwright/lib/pluralsight_login.js` (added in `308bb3c`). Import and
reuse it in `sandbox.js` rather than writing the regex a third time.

### Tests — `scripts/lib/acg/tests/providers/sandbox.test.js`

Add cases that would have caught this:

1. `handleSignIn` resolves when the page navigates to `https://app.pluralsight.com/id`
   (fails before the fix — the old glob never matches).
2. The sign-in link locator string contains no `id.pluralsight.com` substring — a direct
   regression guard against the dead host returning.
3. The post-login wait predicate returns `false` for `https://app.pluralsight.com/id` and
   `true` for `https://app.pluralsight.com/hands-on/playground/cloud-sandboxes`.

## Verification that does NOT need a live sandbox

A throwaway profile is a guaranteed signed-out session and reproduces the sign-in path in
about a minute, without touching the operator's `:9222` profile:

```
"$HOME/Library/Caches/ms-playwright/chromium-1223/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing" \
  --remote-debugging-port=9333 --password-store=basic \
  --user-data-dir=<throwaway> --no-first-run --no-default-browser-check &
```

Then drive `handleSignIn` against port 9333. Kill only the PID you started; verify 9333 is
down and 9222 is still up afterwards.

## Definition of done

- [ ] No occurrence of `id.pluralsight.com` remains in PRODUCTION code:
      `grep -rn "id\.pluralsight\.com" scripts/lib/acg/ --exclude-dir=tests --exclude-dir=node_modules`
      prints nothing. The regression-guard test in `sandbox.test.js` legitimately contains
      the string — it asserts the string's absence from the locator — so it is excluded.
      Do NOT split the literal to satisfy a grep; scope the grep instead.
- [ ] `cd scripts/lib/acg && npm run check` clean; `npm test` green including the new cases.
- [ ] `make lint`, `make shellcheck-lib`, `make bats` green.
- [ ] Only `sandbox.js` and `sandbox.test.js` modified.

## What NOT to do

- Do NOT create a PR, merge, or commit to `main`.
- Do NOT use `--no-verify`.
- Do NOT run `make credential-test` / `restart-test` / `extend-test`, or touch the
  operator's `:9222` Chrome or the `pw-profile` directory — a live session is signed in
  there and killing that browser destroys it (`Identity.Session` is a non-persistent
  cookie).
- Do NOT print, echo, or log credential values.
