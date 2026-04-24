# Bug: `bin/acg-up` never bootstraps Hub cluster — Step 4 fails on fresh Hub

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** HIGH (make down → make up always fails at Step 4 after a clean teardown)
**Branch:** `k3d-manager-v1.1.0`

## Summary

Step 3.5 (`73382eb2`) auto-creates the local Hub k3d cluster when missing, but does not
bootstrap its workloads. Step 4 immediately tries to port-forward to `svc/vault` in the
`secrets` namespace, which does not exist on a fresh cluster. The script aborts:

```
Error from server (NotFound): namespaces "secrets" not found
[acg-up] Vault not responding on localhost:8200 — port-forward may have failed.
make: *** [up] Error 1
```

`kubectl get ns` on a fresh Hub shows only base namespaces:
`default`, `istio-system`, `kube-node-lease`, `kube-public`, `kube-system`.

## Root Cause

`bin/acg-up` was written assuming the Hub cluster already has Vault, LDAP, and ArgoCD
running from a prior session. It never bootstraps them. `make down` now deletes the Hub
cluster (`3fd6f4d6`), so every `make down → make up` cycle hits this gap.

## Fix

Track whether the Hub cluster was just created (`_hub_newly_created`). When it was,
run a new Step 3.6 that bootstraps Vault, LDAP, and ArgoCD on the Hub before continuing.

Bootstrap must run via `"${REPO_ROOT}/scripts/k3d-manager"` subprocess to isolate EXIT/RETURN
traps from `bin/acg-up`'s shell. `deploy_vault` is called first (without `--confirm` — that
flag is not accepted by `_vault_parse_deploy_opts` and triggers `_err`). `deploy_argocd` is
called second — it sees `secrets` ns exists and skips the vault re-deploy.

**File:** `bin/acg-up`

**Old (lines 102–111):**
```bash
_HUB_CLUSTER_CTX="k3d-${HUB_CLUSTER_NAME:-k3d-cluster}"
_info "[acg-up] Step 3.5/12 — Verifying local Hub cluster (create if missing)..."
if ! k3d cluster list 2>/dev/null | grep -q "^${HUB_CLUSTER_NAME:-k3d-cluster}[[:space:]]"; then
  _info "[acg-up] Local Hub cluster '${HUB_CLUSTER_NAME:-k3d-cluster}' not found — creating it now..."
  deploy_cluster --provider k3d "${HUB_CLUSTER_NAME:-k3d-cluster}"
fi
if ! kubectl get nodes --context "${_HUB_CLUSTER_CTX}" --request-timeout=10s >/dev/null 2>&1; then
  _err "[acg-up] Local Hub cluster '${_HUB_CLUSTER_CTX}' is unreachable — OrbStack/k3d may be in a broken state after sleep. Check 'orbctl status'."
fi
_info "[acg-up] Local Hub cluster verified."
```

**New (lines 102–124):**
```bash
_HUB_CLUSTER_CTX="k3d-${HUB_CLUSTER_NAME:-k3d-cluster}"
_hub_newly_created=0
_info "[acg-up] Step 3.5/12 — Verifying local Hub cluster (create if missing)..."
if ! k3d cluster list 2>/dev/null | grep -q "^${HUB_CLUSTER_NAME:-k3d-cluster}[[:space:]]"; then
  _info "[acg-up] Local Hub cluster '${HUB_CLUSTER_NAME:-k3d-cluster}' not found — creating it now..."
  deploy_cluster --provider k3d "${HUB_CLUSTER_NAME:-k3d-cluster}"
  _hub_newly_created=1
fi
if ! kubectl get nodes --context "${_HUB_CLUSTER_CTX}" --request-timeout=10s >/dev/null 2>&1; then
  _err "[acg-up] Local Hub cluster '${_HUB_CLUSTER_CTX}' is unreachable — OrbStack/k3d may be in a broken state after sleep. Check 'orbctl status'."
fi
_info "[acg-up] Local Hub cluster verified."

if [[ "${_hub_newly_created}" -eq 1 ]]; then
  _info "[acg-up] Step 3.6/12 — Bootstrapping Hub cluster (Vault + LDAP + ArgoCD)..."
  kubectl config use-context "${_HUB_CLUSTER_CTX}" >/dev/null 2>&1 || true
  "${REPO_ROOT}/scripts/k3d-manager" deploy_vault
  "${REPO_ROOT}/scripts/k3d-manager" deploy_argocd
  _info "[acg-up] Hub cluster bootstrapped."
fi
```

Lines changed: `_hub_newly_created=0` added before the if-block; `_hub_newly_created=1` added
inside the if-block after `deploy_cluster`; Step 3.6 block added after `_info "Local Hub
cluster verified."`.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `bin/acg-up` lines 99–135 in full.
3. Read `memory-bank/activeContext.md`.
4. Run `shellcheck -x bin/acg-up` — must exit 0 before and after.

---

## Rules

- `shellcheck -x bin/acg-up` must exit 0.
- Only `bin/acg-up` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `bin/acg-up` lines 102–124 match the **New** block above exactly.
2. `shellcheck -x bin/acg-up` exits 0.
3. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-up): add Step 3.6 Hub cluster bootstrap (Vault + LDAP + ArgoCD) on fresh create
   ```
4. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
5. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA under Open Items.
6. `memory-bank/progress.md`: add `[x] **acg-up Hub cluster bootstrap** — COMPLETE (<sha>)` under Known Bugs / Gaps.
7. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `bin/acg-up`.
- Do NOT commit to `main`.
- Do NOT call `deploy_vault --confirm` — `--confirm` is not a recognized flag and triggers `_err`.
- Do NOT source `vault.sh` or `argocd.sh` inline — always invoke via `"${REPO_ROOT}/scripts/k3d-manager"` subprocess.
