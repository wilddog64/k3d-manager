# Bug: `acg-up` does not preflight local Vault state robustly after Mac sleep / clamshell resume

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `bin/acg-up`, `scripts/plugins/vault.sh`

---

## Summary

`bin/acg-up` assumes the local Hub-side Vault path is usable once the workflow reaches secret seeding. After Mac sleep / clamshell resume, that assumption is not always valid: the local runtime, port-forward path, or Vault seal state may have changed underneath the workflow.

This can cause `acg-up` to fail later at the seeding step instead of first classifying the local Vault state and choosing the right recovery path.

---

## Why this is a bug

- `acg-up` already owns the orchestration flow for bringing the stack up.
- Local Vault readiness is an existing prerequisite of that flow, not a new optional capability.
- A workstation sleep / clamshell cycle is a realistic operating condition for this repo's normal usage pattern.

So the missing behavior is not a net-new feature. It is a robustness gap in an existing orchestration command.

---

## Observed Failure Pattern

- Mac resumes from sleep / clamshell state.
- Local Hub-side assumptions may no longer hold:
  - runtime may not be in the expected state,
  - port-forward may be stale,
  - Vault may be sealed,
  - cached shards may be unusable for the current local state.
- `acg-up` continues until the Vault seeding step and then fails with a later, less precise error.

---

## Root Cause

- `acg-up` does not perform a strong enough local Vault preflight before seeding.
- It does not explicitly classify the Hub-side Vault path into states like:
  - unreachable,
  - uninitialized,
  - sealed but recoverable,
  - sealed with stale cache / drift,
  - healthy and unsealed.
- Existing Vault recovery helpers do exist, but `acg-up` does not make enough use of them early enough in the orchestration flow.

---

## Proposed Fix

Before Vault KV seeding, `acg-up` should explicitly:

1. Verify the local runtime / Hub path is reachable.
2. Verify the local Vault endpoint is reachable.
3. Classify Vault state (`uninitialized`, `sealed`, `unsealed`, `drifted`, `unreachable`).
4. Invoke the appropriate recovery path before seeding, or stop with a precise remediation message.

---

## Related

- Vault readiness gap: `docs/bugs/2026-04-20-vault-readiness-gate-missing.md`
- Vault ghost port-forward blocker: `docs/bugs/2026-04-22-vault-orphaned-port-forward-ghost-blocker.md`
- Vault storage / cached unseal drift: `docs/bugs/2026-04-23-vault-keychain-sync-mismatch.md`

---

## Impact

Medium to High. The stack can appear to fail "late" in `acg-up` after the workstation resumes, even though the real issue is that local Vault state was never re-validated before seeding.
