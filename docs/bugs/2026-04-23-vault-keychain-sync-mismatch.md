# Bug: Vault Database and Keychain Synchronization Mismatch

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/plugins/vault.sh`, `scripts/lib/system.sh`

---

## Summary

`make up` continues to fail with `Error 22` during the Vault seeding step. Investigation reveals a **cryptographic state mismatch**: the Vault persistent storage (PVC) contains data encrypted with a previous Master Key, while the macOS Keychain contains an unseal shard from a different initialization attempt.

---

## Reproduction Steps

1. Run `make up` to seed secrets into an existing Vault.
2. Force a re-initialization of Vault (e.g., via `deploy_vault --confirm`) without first deleting the persistent volume (`data-vault-0`).
3. Observe that Vault remains **Sealed** and rejects the stored Keychain shards with `invalid key` or `cipher: message authentication failed`.
4. Run `make up` again.
5. Observe failure at Step 9: `Error 22`.

---

## Root Cause

Vault storage is persistent. If a re-initialization is forced while old data exists on the disk, Vault becomes "State-Confused." It expects the original Master Key for the existing data but receives a new key generated during the recent `operator init`. 

Furthermore, our automation caches shards in the macOS Keychain based on the namespace/release name. If multiple initializations happen, the Keychain may hold "Ghost Shards" that no longer match the active database.

---

## Proposed Fix

1.  **Harden Re-initialization:** The `deploy_vault` command should check for existing PVCs and refuse to re-initialize unless the storage is explicitly purged first.
2.  **Atomic Keychain Sync:** Update the unseal-key caching logic to perform a `delete` before every `add` to ensure the Keychain only ever contains the most recent, valid shard.
3.  **Manual Remediation (Current):** A "Nuclear Reset" is required: delete the Vault Pod, delete the PVC, purge the Keychain entries, and run a clean initialization.

---

## Impact

High. Prevents all cluster deployments until the local management hub is manually synchronized and unsealed.
