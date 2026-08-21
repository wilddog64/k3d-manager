# ACG credential extraction landed on a stale Pluralsight `s2` route

## Live evidence

During `make up CLUSTER_PROVIDER=k3s-aws`, the persistent CDP session was reused and authenticated,
but credential extraction navigated to a stale Pluralsight route:

```text
ACG_SESSION_OK
INFO: Using provider aws
INFO: Found existing sandbox tab: https://s2.pluralsight.com/404.html
INFO: Navigating to https://app.pluralsight.com/hands-on/playground/cloud-sandboxes...
INFO: Waiting for page content to load...
INFO: Looking for AWS sandbox buttons...
WARN: Timed out waiting for sandbox buttons or credentials — proceeding anyway
INFO: Extracting credentials...
ERROR: page.waitForSelector: Timeout 15000ms exceeded.
Call log:
  - waiting for locator('input[aria-label="Copyable input"]') to be visible
```

The session check passed, so this was route navigation rather than lost authentication.

## Root cause

The Extend flow had stale-tab routing protection, but the credential extractor used a separate
navigation helper. When the current `hands-on/playground/cloud-sandboxes` route returned
`https://s2.pluralsight.com/404.html`, the extractor proceeded to wait for credential inputs on the
dead page.

## Fix

Credential navigation now recognizes `s2.pluralsight.com` and `/404.html` as stale routes. If the
current sandbox URL lands there, it retries using the legacy
`/cloud-playground/cloud-sandboxes` route. The recovery logic is covered by three Jest tests.

## Verification

```text
Test Suites: 7 passed, 7 total
Tests:       22 passed, 22 total
```

`node --check playwright/*.js playwright/lib/*.js playwright/providers/*.js` also passed.

## Live credential-test follow-up

The requested `make test-credential PROVIDER=aws` target does not exist:

```text
make: *** No rule to make target `test-credential'.  Stop.
test-credential exit=2
```

The canonical `make credential-test PROVIDER=aws` target was then run, but the managed CDP browser
was unavailable on port 9222 and exited during startup (`bind() failed: Address already in use`).
No live credential extraction result is claimed; the 7-suite, 22-test Jest run validates the changed
route logic.
