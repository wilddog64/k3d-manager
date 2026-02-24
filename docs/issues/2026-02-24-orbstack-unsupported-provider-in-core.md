# OrbStack Provider Unsupported in `deploy_cluster`

**Date:** 2026-02-24
**Status:** ✅ Fixed (2026-02-24)

## Description

The `deploy_cluster` function in `scripts/lib/core.sh` does not include `orbstack` in its allowed provider list, despite `orbstack` being a supported provider in other parts of the system (like the `_cluster_provider` function in the same file and the `scripts/lib/providers/` directory).

When running:
```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_cluster k3d-manager-test
```

The script fails with:
```
INFO: Detected macOS environment.
ERROR: Unsupported cluster provider: orbstack
```

## Impact

Users cannot use the `deploy_cluster` command with the `orbstack` provider, which is the primary E2E entry point for setting up a full cluster environment on OrbStack.

## Root Cause

In `scripts/lib/core.sh`, the `deploy_cluster` function has a hardcoded `case` statement that only recognizes `k3d` and `k3s`:

```bash
   case "$provider" in
      k3d|k3s)
         ;;
# ...
```

## Steps to Reproduce

1. Set `CLUSTER_PROVIDER=orbstack`.
2. Run `./scripts/k3d-manager deploy_cluster`.

## Fix

- Extended the provider allow-list in `scripts/lib/core.sh` so `deploy_cluster` accepts `orbstack` alongside `k3d` and `k3s`.
- Environment variables `CLUSTER_PROVIDER`, `K3D_MANAGER_PROVIDER`, and `K3D_MANAGER_CLUSTER_PROVIDER` now reach `_provider_orbstack_deploy_cluster` instead of failing the guard clause.

## Verification

- With `CLUSTER_PROVIDER=orbstack`, invoking `./scripts/k3d-manager deploy_cluster` now proceeds to the OrbStack provider (it will only stop if OrbStack itself needs installation/GUI activation).
- `./scripts/k3d-manager test lib` passes, confirming the guard change doesn’t regress existing providers.
