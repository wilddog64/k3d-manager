# Bug: `bin/acg-sync-apps` hides `kubectl port-forward` failures behind a generic timeout

**Date:** 2026-04-24
**Status:** OPEN
**Branch:** `k3d-manager-v1.1.0`

## Problem

`bin/acg-sync-apps` starts an `argocd-server` port-forward in the background and waits up to
15 seconds for `https://localhost:8080/` to respond. When the forward never becomes reachable,
the script exits with:

```text
INFO: [sync-apps] ERROR: argocd-server port-forward not ready after 15s — aborting
```

That message does not say whether the failure was:

- a bad context or missing service
- a host port collision
- an early `kubectl port-forward` exit

Because stderr from the background port-forward is discarded, the real cause is hidden.

## Root Cause

The script currently does this:

```bash
kubectl port-forward svc/argocd-server -n "${ARGOCD_NS}" 8080:443 \
  --context "${INFRA_CONTEXT}" >/dev/null 2>&1 &
```

Then it only polls `curl` against `localhost:8080`. If the forward fails immediately, there is
no log to inspect and no early exit path.

## Expected Fix

Capture port-forward stderr to a log file, fail fast if the background process exits before the
socket becomes ready, and print the log tail when readiness times out.

## Impact

Low to medium. The script already detects the failure, but the current output is too generic to
diagnose the real cause quickly.
