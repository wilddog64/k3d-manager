# Issue: `destroy_cluster` for k3d/orbstack requires explicit cluster name

**Date:** 2026-03-01
**Component:** `scripts/lib/providers/k3d.sh`, `scripts/lib/providers/orbstack.sh`

## Description

The `deploy_cluster` command for `k3d` and `orbstack` providers defaults the cluster name to `k3d-cluster` if none is provided. However, the `destroy_cluster` command (and `_provider_k3d_destroy_cluster` / `_provider_orbstack_destroy_cluster`) explicitly requires a cluster name and fails with "Cluster name is required" if omitted.

This inconsistency breaks the standard "no-args" workflow used in the `k3s` provider and expected in the task spec.

## Reproducer

```bash
CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager destroy_cluster
# Output: Cluster name is required
```

## Root Cause

In `scripts/lib/providers/k3d.sh`, the `_provider_k3d_destroy_cluster` function does not provide a default value for the `cluster_name` variable:

```bash
function _provider_k3d_destroy_cluster() {
   ...
   local cluster_name=$1

   if [[ -z "$cluster_name" ]]; then
      echo "Cluster name is required"
      exit 1
   fi
   ...
}
```

## Fix

Update `_provider_k3d_destroy_cluster` to default to `k3d-cluster`, matching the behavior of `_provider_k3d_deploy_cluster`.
