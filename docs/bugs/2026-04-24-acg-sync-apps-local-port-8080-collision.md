# Bug: `bin/acg-sync-apps` does not preflight local port 8080

**Date:** 2026-04-24
**Status:** OPEN
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

## Expected Fix

Add a local port 8080 occupancy check before starting the `kubectl port-forward`, and abort
immediately with a clear message if something is already listening there.

## Impact

Low. This is a usability and diagnosis gap, not a functional regression in the sync logic itself.
