# Bug: `bin/acg-down` is not provider-aware — GCP remote teardown is missing

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** HIGH (GCP remote cluster never cleaned up; AWS plugin sourced unconditionally)
**Branch:** `k3d-manager-v1.1.0`

## Summary

`bin/acg-down` always sources `aws.sh` + `acg.sh` and calls `acg_teardown --confirm`
(CloudFormation delete) regardless of `CLUSTER_PROVIDER`. For `CLUSTER_PROVIDER=k3s-gcp`:
- The GCE instance, firewall rule, SSH config, and kubeconfig context are never deleted.
- Sourcing `aws.sh` is wasteful and will fail or warn if AWS env vars are not set.

`k3s-gcp.sh` already contains a `destroy_cluster --confirm` function that handles the full
GCP remote teardown (GCE instance → firewall rule → SSH config → kubeconfig context). It just
needs to be called from `bin/acg-down`.

## Impact on E2E Testing

A clean E2E cycle requires both clusters torn down before re-provisioning:
- Local Hub (k3d): `k3d cluster delete` — already works for both providers ✓
- Remote (GCP): `destroy_cluster --confirm` — currently skipped ✗

Without GCP remote teardown, re-running `make up` leaves orphaned GCE instances.

## Root Cause

`bin/acg-down` lines 19–21 (hardcoded AWS plugin load):
```bash
source "${REPO_ROOT}/scripts/plugins/aws.sh"
source "${REPO_ROOT}/scripts/plugins/acg.sh"
source "${REPO_ROOT}/scripts/plugins/tunnel.sh"
```

And line 42–43 / 54 (AWS-only operations always run):
```bash
_info "[acg-down] Stopping tunnel..."
tunnel_stop 2>/dev/null || true
...
acg_teardown --confirm
```

`bin/acg-up` already reads `CLUSTER_PROVIDER` and dispatches at line 32. `bin/acg-down` needs
the same pattern.

## Files Implicated

- `bin/acg-down` (full file — restructure source loading and remote teardown dispatch)

---

## Fix

Full replacement of `bin/acg-down`. The local Hub teardown and Vault port-forward kill remain
unchanged; only the remote teardown step is dispatched by provider.

**New `bin/acg-down`:**
```bash
#!/usr/bin/env bash
# bin/acg-down
#
# Tear down the ACG cluster — stop tunnel (AWS), delete remote cluster, stop Vault PF.
# Requires --confirm to prevent accidental teardown.
#
# Usage:
#   bin/acg-down --confirm [--keep-hub]
#
# Environment:
#   CLUSTER_PROVIDER   k3s-aws (default) or k3s-gcp
#   ACG_REGION         AWS region (default: us-west-2)
#   GCP_PROJECT        GCP project ID (required when CLUSTER_PROVIDER=k3s-gcp)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${REPO_ROOT}/scripts"
source "${REPO_ROOT}/scripts/lib/system.sh"
source "${REPO_ROOT}/scripts/lib/core.sh"

: "${SCRIPT_DIR}"

_cluster_provider="${CLUSTER_PROVIDER:-k3s-aws}"
_confirm=0
_keep_hub=0
for _arg in "$@"; do
  case "${_arg}" in
    --confirm)  _confirm=1 ;;
    --keep-hub) _keep_hub=1 ;;
  esac
done

if [[ "${_confirm}" -eq 0 ]]; then
  echo "Usage: bin/acg-down --confirm [--keep-hub]"
  echo ""
  echo "  --confirm    Required. Tears down remote cluster and local Hub cluster."
  echo "  --keep-hub   Optional. Skip local Hub (k3d-cluster) teardown."
  exit 1
fi

case "${_cluster_provider}" in
  k3s-aws)
    source "${REPO_ROOT}/scripts/plugins/aws.sh"
    source "${REPO_ROOT}/scripts/plugins/acg.sh"
    source "${REPO_ROOT}/scripts/plugins/tunnel.sh"
    _info "[acg-down] Stopping tunnel..."
    tunnel_stop 2>/dev/null || true
    _info "[acg-down] Tearing down CloudFormation stack (AWS)..."
    acg_teardown --confirm
    ;;
  k3s-gcp)
    source "${REPO_ROOT}/scripts/lib/providers/k3s-gcp.sh"
    _info "[acg-down] Tearing down GCP cluster..."
    destroy_cluster --confirm
    ;;
  *)
    _info "[acg-down] Unknown CLUSTER_PROVIDER '${_cluster_provider}' — skipping remote teardown"
    ;;
esac

_info "[acg-down] Stopping Vault port-forward..."
_vault_pf_pid_file="${HOME}/.local/share/k3d-manager/vault-pf.pid"
if [[ -f "${_vault_pf_pid_file}" ]]; then
  kill "$(cat "${_vault_pf_pid_file}")" 2>/dev/null || true
  rm -f "${_vault_pf_pid_file}"
  _info "[acg-down] Vault port-forward stopped"
fi

if [[ "${_keep_hub}" -eq 0 ]]; then
  _HUB_CLUSTER="${HUB_CLUSTER_NAME:-k3d-cluster}"
  _info "[acg-down] Tearing down local Hub cluster (${_HUB_CLUSTER})..."
  if k3d cluster list 2>/dev/null | grep -q "^${_HUB_CLUSTER}[[:space:]]"; then
    k3d cluster delete "${_HUB_CLUSTER}"
    _info "[acg-down] Local Hub cluster deleted"
  else
    _info "[acg-down] Local Hub cluster not found — skipping"
  fi
else
  _info "[acg-down] --keep-hub set — local Hub cluster preserved"
fi

_info "[acg-down] Done. Remote cluster and local Hub deleted."
```

**Note:** `GCP_PROJECT` must be set in the environment before running `bin/acg-down` with
`CLUSTER_PROVIDER=k3s-gcp`. It is exported by `gcp_get_credentials` during `acg-up`. If
running teardown after a fresh shell, set it manually from the ACG session output.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `bin/acg-down` in full (current version).
3. Read `scripts/lib/providers/k3s-gcp.sh` lines 230–290 (the `destroy_cluster` function).
4. Read `memory-bank/activeContext.md`.
5. Run `shellcheck bin/acg-down` — must exit 0 before and after.

---

## Rules

- `shellcheck bin/acg-down` must exit 0.
- Only `bin/acg-down` may be touched — do NOT modify `k3s-gcp.sh` or `acg.sh`.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `bin/acg-down` matches the **New** block above exactly.
2. `shellcheck bin/acg-down` exits 0.
3. `CLUSTER_PROVIDER=k3s-aws bin/acg-down --confirm --keep-hub` dry-run path sources `aws.sh`
   and calls `acg_teardown` (verify by adding `echo` trace — do NOT actually run teardown).
4. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-down): provider-aware dispatch; add GCP remote teardown via destroy_cluster
   ```
5. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
6. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA.
7. `memory-bank/progress.md`: add `[x] **acg-down provider dispatch** — COMPLETE (<sha>)` under Known Bugs / Gaps.
8. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `bin/acg-down`.
- Do NOT commit to `main`.
- Do NOT remove the `--keep-hub` flag — it is an explicit opt-out for local Hub preservation.
