# Issue: `acg_credentials.js` waits 300s for `/id` login, but outer runner kills it at 120s

## What was tested

Ran:

```bash
make up CLUSTER_PROVIDER=k3s-gcp
```

Observed output:

```text
[make] CLUSTER_PROVIDER=k3s-gcp — running deploy_cluster...
running under bash version 5.3.9(1)-release
INFO: Detected macOS environment.
INFO: Using cluster provider: k3s-gcp
INFO: [k3s-gcp] Extracting GCP sandbox credentials...
INFO: Using provider gcp
INFO: Navigating to https://app.pluralsight.com/hands-on/playground/cloud-sandboxes...
INFO: Waiting for page content to load...
INFO: Pluralsight redirected to /id — waiting for manual sign-in (up to 300s)...
ERROR: Script timed out after 120s
ERROR: [gcp] Failed to extract credentials via Playwright
make: *** [up] Error 1
```

## Root cause

There is a timeout-contract mismatch between the Playwright script and its caller:

- `scripts/playwright/acg_credentials.js` intentionally waits up to **300 seconds** for the user to complete manual sign-in at `/id`
- the outer runner / wrapper terminates the script after **120 seconds**

This means the `/id` recovery path can never complete as designed whenever manual sign-in actually takes longer than 120 seconds.

The bug is intermittent because it depends on session state:

- if the user is already authenticated, the script may avoid `/id` and succeed
- if the session is expired and the page redirects to `/id`, the wrapper kills the script before the 300-second wait finishes

## Why this is a real bug

"Sign in once beforehand" is only a workaround. The implemented code explicitly supports a `/id` manual-login path, so the caller must allow that path to run long enough to finish. A 120-second outer timeout contradicts the 300-second inner wait window.

## Recommended follow-up

1. Locate the exact 120-second timeout source in the wrapper/caller path for `acg_credentials.js`
2. Align the outer timeout with the Playwright script’s `/id` wait window, or reduce the inner wait so both layers share the same contract
3. Add a clear diagnostic when the wrapper kills the Playwright process so the source of the timeout is obvious
