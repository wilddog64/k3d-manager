# OrbStack Provider Unsupported in `deploy_cluster`

**Date:** 2026-02-24
**Status:** Documented

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
