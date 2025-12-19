# Vault Resilience Plan

## Goals
- Keep the existing Vault deployment functional after node or system reboots.
- Provide a clear path toward future auto-unseal with minimal rework.

## Current State
- Vault pods seal on restart because no auto-unseal backend is configured.
- Unseal shards currently exist only in the operator’s setup logs.
- Shared secret helpers (Keychain on macOS, libsecret on Linux) already exist in `scripts/lib/system.sh`.

## Plan of Action
1. **Capture Unseal Shards Securely**
   - Use the existing sensitive-variable helpers to store each unseal key in the local Keychain/secret-tool.
   - Ensure helpers can list, retrieve, and delete shards without leaking them in traces.
2. **Automate Manual Unseal**
   - Provide a `reunseal_vault` helper that reads stored shards and runs `vault operator unseal` for each portion.
   - Have the script detect sealed status first, skipping work if Vault is already unsealed.
3. **Document Reboot Recovery**
   - Write a short runbook covering: reboot detection, shard retrieval, unseal helper usage, and verification steps.
   - Note where a cloud KMS or transit auto-unseal could plug in later (keep function interfaces flexible).
4. **Future Interfaces**
   - Expose hooks or config stanzas so the unseal helper can be replaced by a KMS backend when available.

## Deliverables
- Local key storage helpers for Vault unseal shards.
- `reunseal_vault` script runnable from `k3d-manager` or a make target.
- Reboot recovery documentation and pointers for future automation.

## Next Steps After Review
- Implement helper functions and script.
- Test by sealing/unsealing Vault manually.
- Iterate on docs based on operator feedback.
