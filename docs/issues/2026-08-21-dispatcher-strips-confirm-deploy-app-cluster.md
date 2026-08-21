# Dispatcher `deploy_*` guard strips `--confirm` from `deploy_app_cluster`

**Date:** 2026-08-21
**Branch found on:** `k3d-manager-v1.26.0`
**Severity:** Medium — usability / shared-guard blast radius
**Status:** OPEN (deferred out of v1.26.0)
**Origin:** Finding 2b of `docs/bugs/2026-08-21-lifecycle-e2e-live-acceptance-findings.md`

## Symptom

```
scripts/k3d-manager deploy_app_cluster --confirm
# → deploy_app_cluster requires --confirm
```

The flag is present on the command line but never reaches the function.

## Root cause

The dispatcher's `deploy_*` safety guard (`__k3dm_deploy_guard_args`) **consumes** `--confirm`
— it sets an internal confirmed flag and strips `--confirm` from the argument list before the
plugin function runs. `deploy_app_cluster` then independently checks for `--confirm` as its own
`$1`, which is gone, so it aborts.

## Current workaround

Invoke `deploy_app_cluster` through a **lib-sourcing wrapper** (source
`system.sh`/`system_overrides.sh`/`core.sh`/`provider.sh`/`shopping_cart.sh`, then call
`deploy_app_cluster --confirm`) — the same pattern the e2e-sandbox spec uses. This bypasses the
dispatcher guard entirely.

## Fix direction (mind the blast radius)

Pick ONE, and audit every `deploy_*` function before changing the shared guard:

1. Have `__k3dm_deploy_guard_args` export a `K3DM_DEPLOY_CONFIRMED` env var that
   `deploy_app_cluster` (and peers) honour instead of re-parsing `--confirm`; **or**
2. Drop `deploy_app_cluster`'s redundant own-`--confirm` gate, since the guard already gates it.

Either way, add BATS asserting `scripts/k3d-manager deploy_app_cluster --confirm` reaches the
confirmed path, and that the guard still blocks the un-confirmed invocation.

## Why deferred

The guard is shared across every `deploy_*` entry point; a careless change could weaken the
confirm gate on other destructive deploy paths. The lib-sourcing wrapper is a working
stopgap, so this is not release-blocking.
