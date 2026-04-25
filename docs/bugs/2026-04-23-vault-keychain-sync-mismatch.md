# Bug: Vault storage / cached unseal state can still drift out of sync

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/plugins/vault.sh`, `scripts/lib/system.sh`

---

## Summary

`make up` can still fail with `Error 22` during the Vault seeding step when Vault storage state and cached unseal material drift apart. The likely operator-facing symptom is that Vault remains sealed even though cached shards exist, and the later seeding step fails because `acg-up` expects a healthy unsealed Vault.

---

## Reproduction Steps

1. Run `make up` to seed secrets into an existing Vault.
2. Force a re-initialization of Vault (e.g., via `deploy_vault --confirm`) without first deleting the persistent volume (`data-vault-0`).
3. Observe that Vault remains **Sealed** and rejects the stored Keychain shards with `invalid key` or `cipher: message authentication failed`.
4. Run `make up` again.
5. Observe failure at Step 9: `Error 22`.

---

## Root Cause

- Vault storage is persistent. If a re-initialization is forced while old data still exists on disk, Vault may reject cached unseal shards because the underlying storage expects a different initialization state.
- The automation does cache shards by namespace/release, so stale cached material is part of the failure surface.
- However, the code already deletes cached entries before storing replacements, and it already attempts automatic recovery when cached shards are rejected or missing.
- The bug is therefore not simply "Keychain never replaced old shards." The more precise problem is that the current automatic recovery and operator feedback are still not sufficient for every drifted Vault state that can occur locally.

---

## Current Code Reality

- macOS secret storage already does delete-before-add replacement in `scripts/lib/system.sh`.
- Vault bootstrap already attempts automatic recovery in `scripts/plugins/vault.sh` when cached shards are rejected or missing.
- The remaining gap is that the operator can still end up in a state where these recovery paths do not restore Vault cleanly enough before `acg-up` reaches the seeding phase.

## Proposed Fix

1. **Harden Re-initialization:** `deploy_vault` should surface clearer guardrails and diagnostics around persistent data reuse versus reset paths.
2. **Clarify Recovery State:** Distinguish between sealed-but-recoverable, sealed-with-stale-cache, and storage-reset-required states in operator output.
3. **Manual Remediation (Current Worst Case):** If automatic recovery still cannot reconcile the state, a "Nuclear Reset" may be required: delete the Vault Pod, delete the PVC, purge the cached unseal entries, and run a clean initialization.

---

## Impact

High. Can block all cluster deployments when local Vault recovery lands in a state that the current automation does not fully reconcile.
