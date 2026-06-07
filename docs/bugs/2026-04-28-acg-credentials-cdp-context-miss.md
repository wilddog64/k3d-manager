# Bug: ACG credential extraction misses visible sandbox credentials

**Date:** 2026-04-28
**Status:** Fixed pending PR
**Severity:** Critical

## What Was Tested

`k3d-manager` called `acg_get_credentials` through the lib-acg subtree during `make up`.

Observed output:

```text
[make] Running bin/acg-up...
INFO: [acg-up] Step 1/12 — Getting k3s-aws credentials...
INFO: [acg] Extracting AWS credentials from https://app.pluralsight.com/cloud-playground/cloud-sandboxes...
make: *** [up] Error 1
```

The Pluralsight sandbox was already running and displayed AWS username, password, access key ID, and secret access key. Credential values are intentionally omitted.

## Root Cause

The extraction path had three brittle assumptions:

- AWS sandbox defaults still used the legacy `cloud-playground/cloud-sandboxes` URL.
- `acg_credentials.js` only reused CDP when it already saw a Pluralsight tab; otherwise it disconnected and launched a separate context, which could miss the signed-in browser state.
- Direct navigation to `/hands-on/playground/cloud-sandboxes` can bounce to signed-in `/library/`, leaving the script waiting for sandbox controls on the wrong page.

A live validation attempt also showed macOS `open -a "Google Chrome"` failed even though `/Applications/Google Chrome.app` existed:

```text
Unable to find application named 'Google Chrome'
ERROR: Antigravity browser not ready on port 9222 after 30s — launch Antigravity with --remote-debugging-port=9222
```

## Fix

- Default AWS sandbox URL now uses `https://app.pluralsight.com/hands-on/playground/cloud-sandboxes`.
- CDP browser context is reused even when no Pluralsight tab exists yet.
- If sandbox controls are not visible and the current page is not a sandbox route, the script retries through `/hands-on` and then returns to the sandbox URL.
- Copilot review follow-up replaced the fixed `/hands-on` retry sleep with a DOM readiness/link/text condition and clarified the intentional fallthrough when sandbox controls still do not appear.
- Copilot inline review follow-up replaced k3d-manager-specific fallback paste commands with the repo-local `source scripts/plugins/acg.sh && pbpaste | acg_import_credentials` command.
- `acg_get_credentials` prints sanitized Playwright diagnostics on failure.
- macOS CDP launch prefers the direct Chrome executable and logs Chrome stderr/stdout to `~/.local/share/k3d-manager/chrome-cdp.log`.

## Verification

From the k3d-manager consumer before moving the fix into lib-acg:

```text
./scripts/k3d-manager acg_get_credentials
running under bash version 5.3.9(1)-release
INFO: [acg] Extracting AWS credentials from https://app.pluralsight.com/hands-on/playground/cloud-sandboxes...
INFO: [aws] Credentials written to /Users/cliang/.aws/credentials
INFO: [aws] Access key: AKIA****
```

AWS STS verification:

```text
aws sts get-caller-identity --query 'Arn' --output text
arn:aws:iam::905293745314:user/cloud_user
```

Local lib-acg checks must pass before PR:

```text
node --check playwright/acg_credentials.js
shellcheck scripts/plugins/acg.sh scripts/lib/cdp.sh scripts/vars.sh
```
