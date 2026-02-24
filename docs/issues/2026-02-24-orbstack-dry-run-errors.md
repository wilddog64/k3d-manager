# OrbStack Provider Dry-Run Errors

**Date:** 2026-02-24
**Status:** Documented

## Description

When running `./scripts/k3d-manager create_cluster --dry-run` with `CLUSTER_PROVIDER=orbstack`, two distinct errors occur.

### 1. Grep Error in `_provider_k3d_create_cluster`

The following error is observed:
```
grep: unrecognized option `--dry-run'
usage: grep [-abcdDEFGHhIiJLlMmnOopqRSsUVvwXxZz] [-A num] [-B num] [-C[num]]
        [-e pattern] [-f file] [--binary-files=value] [--color=when]
        [--context[=num]] [--directories=action] [--label] [--line-buffered]
        [--null] [pattern] [file ...]
ERROR: failed to execute k3d cluster list: 141
```

This happens because `_provider_k3d_create_cluster` takes the first argument as the cluster name and passes it to `grep`:

```bash
function _provider_k3d_create_cluster() {
   local cluster_name="${1:-k3d-cluster}"
   # ...
   if _provider_k3d_list_clusters | grep -q "$cluster_name"; then
   # ...
```

If `--dry-run` is passed as the first argument, `grep -q "--dry-run"` fails because it interprets `--dry-run` as an option. It should be `grep -q -- "$cluster_name"`.

### 2. K3d Schema Validation Failure

If the script continues (or if the grep error is bypassed), k3d fails to create the cluster because `--dry-run` is not a valid hostname/cluster name:

```
FATA[0000] Schema Validation failed for config file /tmp/k3d-cluster.SuU1Xj.yaml: - metadata.name: Does not match format 'hostname' 
ERROR: failed to execute k3d cluster create --config /tmp/k3d-cluster.SuU1Xj.yaml: 1
```

The `create_cluster` command does not seem to have native support for a `--dry-run` flag in the way it was invoked, leading it to be treated as the cluster name.

## Impact

The `--dry-run` flag is currently broken for `create_cluster` when passed as the first argument, and it's not a recognized flag for the underlying implementation.

## Steps to Reproduce

1. Ensure OrbStack is running.
2. Run `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager create_cluster --dry-run`.
