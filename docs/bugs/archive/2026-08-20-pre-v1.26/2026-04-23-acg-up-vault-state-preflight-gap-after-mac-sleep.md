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

**Specific mechanism (2026-04-24):** Mac enters clamshell/deep sleep → OrbStack VMs are killed
on system restart → k3d container running Vault is destroyed → Vault auto-seals. On resume,
`acg-up` reaches Step 4 (Vault port-forward) and later fails at seeding with a confusing error
rather than detecting the sealed state early.

General pattern:
- Mac resumes from sleep / clamshell state.
- Local Hub-side assumptions may no longer hold:
  - OrbStack may have restarted (k3d containers gone),
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

---

## Implementation Spec (2026-04-24)

**Status:** OPEN

### Files Implicated

- `bin/acg-up` (two insertion points — both are AWS-only path, after line 97 GCP early-exit)

### Fix

**Insertion A — Hub cluster preflight (insert between lines 101 and 102, before Step 4):**

**Old (lines 101–102):**
```bash

_info "[acg-up] Step 4/12 — Starting Vault port-forward (k3d → localhost:8200)..."
```

**New (lines 101–102+):**
```bash

_HUB_CLUSTER_CTX="k3d-${HUB_CLUSTER_NAME:-k3d-cluster}"
_info "[acg-up] Step 3.5/12 — Verifying local Hub cluster (OrbStack clamshell resume guard)..."
if ! k3d cluster list 2>/dev/null | grep -q "^${HUB_CLUSTER_NAME:-k3d-cluster}[[:space:]]"; then
  _err "[acg-up] Local Hub cluster '${HUB_CLUSTER_NAME:-k3d-cluster}' not found — OrbStack may have restarted after Mac sleep. Run 'k3d cluster list' and check OrbStack, then re-run."
fi
if ! kubectl get nodes --context "${_HUB_CLUSTER_CTX}" --request-timeout=10s >/dev/null 2>&1; then
  _err "[acg-up] Local Hub cluster '${_HUB_CLUSTER_CTX}' is unreachable — OrbStack/k3d may be in a broken state after sleep. Check 'orbctl status'."
fi
_info "[acg-up] Local Hub cluster verified."

_info "[acg-up] Step 4/12 — Starting Vault port-forward (k3d → localhost:8200)..."
```

**Insertion B — Vault seal check (insert after line 115, after the existing `sleep 3` and PID log):**

**Old (line 115–117):**
```bash
_info "[acg-up] Vault port-forward PID: ${_vault_pf_pid} (log: ${HOME}/.local/share/k3d-manager/vault-pf.log)"

_info "[acg-up] Step 5/12 — Creating ghcr-pull-secret in all app namespaces..."
```

**New (line 115–117+):**
```bash
_info "[acg-up] Vault port-forward PID: ${_vault_pf_pid} (log: ${HOME}/.local/share/k3d-manager/vault-pf.log)"

_vault_health=$(curl -sf --max-time 5 http://localhost:8200/v1/sys/health 2>/dev/null || echo '{}')
_vault_sealed=$(printf '%s' "${_vault_health}" | grep -o '"sealed":[^,}]*' | grep -o 'true\|false' || echo 'unknown')
if [[ "${_vault_sealed}" == "true" ]]; then
  _err "[acg-up] Vault is sealed — likely caused by OrbStack restart after Mac sleep. Unseal with stored shards, then re-run."
elif [[ "${_vault_sealed}" == "unknown" ]]; then
  _err "[acg-up] Vault not responding on localhost:8200 — port-forward may have failed. Check: ${HOME}/.local/share/k3d-manager/vault-pf.log"
fi
_info "[acg-up] Vault is unsealed and reachable."

_info "[acg-up] Step 5/12 — Creating ghcr-pull-secret in all app namespaces..."
```

### Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `bin/acg-up` lines 95–120 in full.
3. Read `memory-bank/activeContext.md`.
4. Run `shellcheck bin/acg-up` — must exit 0 before and after.

### Rules

- `shellcheck bin/acg-up` must exit 0.
- Only `bin/acg-up` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

### Definition of Done

1. Insertion A matches the **New** block above exactly, positioned between lines 101 and 102.
2. Insertion B matches the **New** block above exactly, positioned after line 115.
3. `shellcheck bin/acg-up` exits 0.
4. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-up): detect local Hub unreachable and Vault sealed after OrbStack restart
   ```
5. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
6. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA.
7. `memory-bank/progress.md`: mark `**Vault Preflight After Sleep**` as COMPLETE with SHA.
8. Report back: commit SHA + paste the memory-bank lines you updated.

### What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `bin/acg-up`.
- Do NOT commit to `main`.
- Do NOT touch `vault.sh` or any plugin — detection only, no recovery logic changes.
