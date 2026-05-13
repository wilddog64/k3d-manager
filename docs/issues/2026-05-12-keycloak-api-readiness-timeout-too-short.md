# Issue: Keycloak readiness gate times out too early during cold rebuilds

## Status
FIXED

## What Happened
After rebuilding the clusters, `make up` failed while waiting for Keycloak to become ready:

```text
INFO: [acg-up] Keycloak API not ready yet (attempt 29/30) — waiting 10s...
INFO: [acg-up] Keycloak API not ready yet (attempt 30/30) — waiting 10s...
ERROR: [acg-up] Keycloak API not Ready after 5 min — realm import is required for SSO and cannot be skipped
make: *** [up] Error 1
```

## Root Cause
The Keycloak readiness loop in `bin/acg-up` used a fixed 5-minute ceiling (`30 x 10s`). On a cold cluster rebuild, Keycloak can take longer than that before `/health/ready` becomes reachable, so the bootstrap aborted before it had a chance to import the realm.

## Fix
- Make the Keycloak readiness timeout configurable.
- Increase the default wait window to 15 minutes.
- Keep the realm import fail-fast once Keycloak is actually reachable.

## Follow-Up
- Keep the timeout configurable via `KEYCLOAK_READY_TIMEOUT_SECONDS` and `KEYCLOAK_READY_POLL_INTERVAL_SECONDS`.
- If cold rebuilds continue to exceed the default, tune the timeout rather than weakening the import requirement.
