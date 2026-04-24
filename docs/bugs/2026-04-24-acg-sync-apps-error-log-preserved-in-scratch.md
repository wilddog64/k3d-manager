# Bug: `bin/acg-sync-apps` deletes the failure log and keeps it out of `./scratch/`

**Date:** 2026-04-24
**Status:** COMPLETE (`890ba2a6`)
**Branch:** `k3d-manager-v1.1.0`

## Problem

`bin/acg-sync-apps` writes its port-forward log to an ephemeral location and then removes that
log in the `EXIT` trap. When the script fails, there is no persistent evidence left behind.

The desired behavior is:

- logs live under `./scratch/`
- the error log is preserved when the script exits non-zero
- state cleanup still happens so dead ownership markers do not linger

## Root Cause

The `EXIT` trap deletes the log file unconditionally for owned port-forwards.

## Fix

`bin/acg-sync-apps` now writes its log to `./scratch/logs/` and preserves the log when the
script exits non-zero. The ownership state file is still cleaned up on exit so stale reuse
metadata does not linger.

## Validation

`shellcheck -x bin/acg-sync-apps` passes, `bats scripts/tests/bin/acg_sync_apps.bats` passes,
and a bounded live `make sync-apps` run now leaves the failure log behind at:

```text
scratch/logs/acg-sync-apps-argocd-pf.68C2ZO.log
```

## Impact

Medium. This blocks diagnosis of downstream ArgoCD failures because the evidence disappears on
exit.
