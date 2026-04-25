# Bug: acg-up lacks Vault seal check (Readiness Gate)

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `bin/acg-up`, `scripts/plugins/vault.sh`

---

## Summary

When the local management cluster (k3d/OrbStack) restarts due to Mac sleep or engine updates, Vault automatically enters a **Sealed** state. The `bin/acg-up` script does not check for this state before attempting to seed secrets in Step 9, leading to a `curl Error 22` (HTTP failure) and terminating the deployment.

---

## Reproduction Steps

1. Force a restart of the local k3d cluster nodes (or reboot the host Mac).
2. Confirm Vault is sealed: `kubectl get pods -n secrets` shows `0/1 READY`.
3. Run `make up`.
4. Observe failure at Step 9: `INFO: [acg-up] Seeding Vault KV... make: *** [up] Error 22`.

---

## Root Cause

`bin/acg-up` is too "optimistic." It checks if the k3d cluster exists, but assumes that an existing cluster implies a healthy, unsealed Vault instance. It skips the `deploy_vault` logic (which contains unseal recovery) if the cluster is already present.

---

## Proposed Fix

Add a **Vault Readiness Gate** to `bin/acg-up` (or inside `deploy_cluster` for k3d) that:
1. Queries the Vault seal status via the API or CLI.
2. If sealed, automatically invokes `_vault_replay_cached_unseal` to unlock the hub before proceeding to secret seeding.

---

## Impact

Medium. Affects developer productivity after system reboots or sleep cycles.
