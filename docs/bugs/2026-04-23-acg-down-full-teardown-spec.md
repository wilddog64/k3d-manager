# Bug Fix Spec: `acg-down` must tear down local Hub cluster by default

**Date:** 2026-04-23
**Branch:** `k3d-manager-v1.1.0`
**File:** `bin/acg-down`
**Related bug doc:** `docs/bugs/2026-04-23-acg-down-should-reset-local-and-remote.md`

## Problem

`bin/acg-down` tears down the remote CloudFormation stack but leaves the local Hub
cluster (`k3d-cluster` / context `k3d-k3d-cluster`) running. Stale local Vault state,
ArgoCD apps, and orchestration assumptions survive into the next `make up` cycle, hiding
real end-to-end drift until a full local reset is forced.

The fix: default to tearing down both. Add `--keep-hub` as an explicit opt-in to preserve
local state when the operator knowingly wants to reuse it.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read this spec in full before touching any file.
3. Read `bin/acg-down` in full.
4. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`.

**Branch:** `k3d-manager-v1.1.0` — commit directly here, do NOT create a new branch.

---

## Change — `bin/acg-down`

### Old (lines 19–35 — full current script body after sourcing)

```bash
if [[ "${1:-}" != "--confirm" ]]; then
  echo "Usage: bin/acg-down --confirm"
  echo "Tears down the CloudFormation stack and stops the tunnel."
  exit 1
fi

_info "[acg-down] Stopping tunnel..."
tunnel_stop 2>/dev/null || true

_info "[acg-down] Stopping Vault port-forward..."
_vault_pf_pid_file="${HOME}/.local/share/k3d-manager/vault-pf.pid"
if [[ -f "${_vault_pf_pid_file}" ]]; then
  kill "$(cat "${_vault_pf_pid_file}")" 2>/dev/null || true
  rm -f "${_vault_pf_pid_file}"
  _info "[acg-down] Vault port-forward stopped"
fi

_info "[acg-down] Tearing down CloudFormation stack..."
acg_teardown --confirm

_info "[acg-down] Done. Sandbox resources deleted."
```

### New

```bash
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
  echo "  --confirm    Required. Tears down CloudFormation stack and local Hub cluster."
  echo "  --keep-hub   Optional. Skip local Hub (k3d-cluster) teardown."
  exit 1
fi

_info "[acg-down] Stopping tunnel..."
tunnel_stop 2>/dev/null || true

_info "[acg-down] Stopping Vault port-forward..."
_vault_pf_pid_file="${HOME}/.local/share/k3d-manager/vault-pf.pid"
if [[ -f "${_vault_pf_pid_file}" ]]; then
  kill "$(cat "${_vault_pf_pid_file}")" 2>/dev/null || true
  rm -f "${_vault_pf_pid_file}"
  _info "[acg-down] Vault port-forward stopped"
fi

_info "[acg-down] Tearing down CloudFormation stack..."
acg_teardown --confirm

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

_info "[acg-down] Done. Remote sandbox and local Hub deleted."
```

**Nothing else in `bin/acg-down` changes.** Do not touch the sourcing block at the top.

---

## Rules

- `shellcheck -S warning bin/acg-down` — zero new warnings
- Do NOT run BATS — this script requires live AWS credentials and a running k3d cluster
- Do NOT modify any file not listed above
- Do NOT modify `Makefile`, `bin/acg-up`, or any plugin

---

## Definition of Done

- [ ] `bin/acg-down` — arg parsing replaced; Hub teardown block added after `acg_teardown`
- [ ] `shellcheck -S warning bin/acg-down` passes with zero new warnings
- [ ] Committed on `k3d-manager-v1.1.0` with message:
      `fix(acg-down): tear down local Hub cluster by default; add --keep-hub opt-out`
- [ ] Pushed to `origin k3d-manager-v1.1.0` — do NOT report done until push succeeds
- [ ] `memory-bank/activeContext.md` updated: mark Teardown State Drift COMPLETE with commit SHA
- [ ] `memory-bank/progress.md` updated: Teardown State Drift row marked COMPLETE with commit SHA
- [ ] Report back: commit SHA + paste the memory-bank lines you updated

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-down`
- Do NOT commit to `main`
- Do NOT change default behavior of `--confirm` — it must still be required
- Do NOT add Hub teardown to `acg_teardown` in `acg.sh` — the fix belongs in `bin/acg-down` only
