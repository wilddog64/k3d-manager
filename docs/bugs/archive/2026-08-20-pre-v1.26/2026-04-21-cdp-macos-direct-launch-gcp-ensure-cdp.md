# Bug: macOS CDP direct launch is unreliable for GCP credential flow

**Date:** 2026-04-21
**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/plugins/antigravity.sh`, `scripts/plugins/gcp.sh`

## Summary

GCP `make up` can fail on macOS when Chrome DevTools Protocol is not already reachable on
`localhost:9222`. The immediate failure is in `gcp_get_credentials`, but the deeper trigger is
that the shared browser launcher still uses `open -a "Google Chrome" --args` on macOS.

If Chrome is already running without the remote debugging flag, macOS reuses the existing app
instance and the new CDP flags are not applied. As a result, the GCP flow sees CDP as unavailable
and exits before credential extraction can begin.

## Current Behavior

1. `scripts/plugins/antigravity.sh` probes `http://localhost:9222/json`.
2. If CDP is not reachable, the macOS branch calls `open -a "Google Chrome" --args ...`.
3. A pre-existing Chrome app instance may ignore the requested CDP flags.
4. `scripts/plugins/gcp.sh` then checks CDP and hard-fails if the endpoint is still unavailable.

## Root Cause

- The macOS launch path in `_browser_launch` is not equivalent to the direct-binary launch used on
  Linux.
- `gcp_get_credentials` assumes CDP must already exist and does not distinguish between:
  - a missing shared CDP launch service, and
  - a launch attempt that silently failed because macOS reused an existing Chrome process.
- The current GCP plugin design notes explicitly say GCP should not launch or restart Chrome on its
  own, so any fix must stay aligned with the shared CDP ownership model.

## Constraints

- Do not change `PLAYWRIGHT_AUTH_DIR`, `vars.sh`, or the shared profile directory path without an
  explicit design decision.
- Keep shared browser ownership coherent between Antigravity and GCP; avoid introducing a second,
  competing Chrome lifecycle manager in `gcp.sh` unless the architecture is intentionally changed.

## Recommended Follow-up

1. Replace the macOS `open -a` launch path in `_browser_launch` with a direct Chrome binary launch
   so CDP flags are applied reliably.
2. Decide whether `gcp_get_credentials` should:
   - continue relying solely on the shared CDP launcher and emit a clearer operator-facing error, or
   - gain a minimal, design-approved recovery path that preserves the single-owner browser model.
3. Re-run the blocked GCP smoke path after the macOS CDP launch behavior is corrected.

## Impact

High for macOS-based GCP provisioning. The failure prevents the credential extraction step that the
rest of the GCP automation depends on.
