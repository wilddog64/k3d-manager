# Bug: `bin/acg-sync-apps` does not preflight local port 8080

**Date:** 2026-04-24
**Status:** COMPLETE (`3a1e2554`)
**Branch:** `k3d-manager-v1.1.0`

## Problem

`bin/acg-sync-apps` starts a local ArgoCD port-forward on `127.0.0.1:8080`. When that port is
already occupied, `kubectl port-forward` exits immediately with:

```text
Unable to listen on port 8080: ... bind: address already in use
```

The script now surfaces that stderr, but the failure still arrives only after the forwarder
has already been started. There is no preflight guard to tell the user that 8080 is already
busy before the sync attempt begins.

## Root Cause

The script only checks whether `https://localhost:8080/` becomes reachable after launching the
background `kubectl port-forward`. It does not check whether the local port is already bound
before starting the forward.

## Fix

`bin/acg-sync-apps` now checks whether local port 8080 is already bound before starting the
ArgoCD port-forward. If the port is occupied, the script exits immediately with a clear error.

## Validation

`shellcheck -x bin/acg-sync-apps` passes, and a focused bats test confirms both cases:

- occupied port 8080 exits early with a clear message
- a free port still reaches the existing early-forward failure path and surfaces the log tail

## Impact

Low. This is a usability and diagnosis gap, not a functional regression in the sync logic itself.
