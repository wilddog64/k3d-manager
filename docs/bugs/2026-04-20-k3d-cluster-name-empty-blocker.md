# Bug: k3d cluster creation fails due to empty CLUSTER_NAME

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/lib/core.sh`, `scripts/etc/cluster.yaml.tmpl`

---

## Summary

When running `make up`, the local infra cluster (k3d) fails to start with a `FATA[0000] Schema Validation failed` error. This is because the `CLUSTER_NAME` variable is empty when the k3d YAML template is generated, resulting in an invalid `metadata.name: ""` field.

---

## Reproduction Steps

1. Run `make up` (or `CLUSTER_PROVIDER=k3s-aws make up`).
2. Observe logs:
   ```text
   k3d installed already
   FATA[0000] Schema Validation failed for config file /tmp/k3d-cluster.TWD6qg.yaml: - metadata.name: Does not match format 'hostname'
   ```

---

## Root Cause

1. **Dispatcher Logic:** In `scripts/lib/core.sh`, the `deploy_cluster` function reads `cluster_name_value="${positional[0]:-${CLUSTER_NAME:-}}"`.
2. **Missing Fallback:** If no name is provided as an argument and `$CLUSTER_NAME` is not exported, the variable becomes an empty string.
3. **Template Violation:** The template `scripts/etc/cluster.yaml.tmpl` uses `name: "${CLUSTER_NAME}"`. K3d requires a non-empty string following hostname rules.
4. **Trigger:** `bin/acg-up` reads `CLUSTER_PROVIDER` correctly via `_cluster_provider="${CLUSTER_PROVIDER:-k3s-aws}"` (line 32) — the provider dispatch is not broken. The empty `CLUSTER_NAME` occurs because no caller passes a cluster name argument and `$CLUSTER_NAME` is not pre-exported, leaving `core.sh` line 796 with an empty value and no default.

---

## Proposed Fix

Harden `scripts/lib/core.sh` line 796 to add a safe default:

```bash
# current
local cluster_name_value="${positional[0]:-${CLUSTER_NAME:-}}"

# replacement
local cluster_name_value="${positional[0]:-${CLUSTER_NAME:-k3d-cluster}}"
```

`bin/acg-up` does not need changes — its `CLUSTER_PROVIDER` handling is correct.

---

## Impact

Total Blocker. Neither AWS nor GCP can be deployed because the local infra cluster (which hosts Vault and ArgoCD) cannot be created.
