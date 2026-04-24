# Bug: Step 3.6 Hub bootstrap skips deploy_ldap — deploy_argocd fails on direct call with --confirm

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** HIGH (make up fails at Step 3.6 ArgoCD bootstrap on every fresh Hub create)
**Branch:** `k3d-manager-v1.1.0`

## Summary

`deploy_argocd` (called via dispatcher in Step 3.6) checks for the `ldap` namespace.
On a fresh Hub it is missing, so `deploy_argocd` calls `deploy_ldap --confirm` directly.
`_ldap_parse_deploy_opts` does not handle `--confirm` — it hits the `_err "[ldap] unknown
option: $1"` catch-all and exits 1:

```
INFO: [argocd] Verifying infrastructure foundations...
make: *** [up] Error 1
```

## Root Cause

`deploy_argocd`'s smart dependency chain calls `deploy_ldap --confirm` directly (not via
the `scripts/k3d-manager` dispatcher). The dispatcher is what consumes and strips `--confirm`
before forwarding to the function. Called directly, `--confirm` reaches `_ldap_parse_deploy_opts`
which does not accept it.

The same pattern exists for `deploy_vault --confirm` inside `deploy_argocd`, but that path
is not hit on a fresh Hub because `deploy_vault` was already run in Step 3.6 and `secrets`
namespace exists.

## Fix

Add `deploy_ldap --confirm` via dispatcher to Step 3.6, between `deploy_vault` and
`deploy_argocd`. When `deploy_argocd` runs, both `secrets` and `ldap` namespaces already
exist, so it skips both direct dependency calls and proceeds to Helm install.

**File:** `bin/acg-up`

**Old (lines 115–121):**
```bash
if [[ "${_hub_newly_created}" -eq 1 ]]; then
  _info "[acg-up] Step 3.6/12 — Bootstrapping Hub cluster (Vault + LDAP + ArgoCD)..."
  kubectl config use-context "${_HUB_CLUSTER_CTX}" >/dev/null 2>&1 || true
  "${REPO_ROOT}/scripts/k3d-manager" deploy_vault --confirm
  "${REPO_ROOT}/scripts/k3d-manager" deploy_argocd --confirm
  _info "[acg-up] Hub cluster bootstrapped."
fi
```

**New (lines 115–122):**
```bash
if [[ "${_hub_newly_created}" -eq 1 ]]; then
  _info "[acg-up] Step 3.6/12 — Bootstrapping Hub cluster (Vault + LDAP + ArgoCD)..."
  kubectl config use-context "${_HUB_CLUSTER_CTX}" >/dev/null 2>&1 || true
  "${REPO_ROOT}/scripts/k3d-manager" deploy_vault --confirm
  "${REPO_ROOT}/scripts/k3d-manager" deploy_ldap --confirm
  "${REPO_ROOT}/scripts/k3d-manager" deploy_argocd --confirm
  _info "[acg-up] Hub cluster bootstrapped."
fi
```

One line added. No other lines change.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `bin/acg-up` lines 115–122 in full.
3. Read `scripts/plugins/ldap.sh` function `_ldap_parse_deploy_opts` — confirm it does NOT
   handle `--confirm` (hits `_err "[ldap] unknown option: $1"` catch-all).
4. Read `scripts/plugins/argocd.sh` function `deploy_argocd` lines 81–90 — confirm it calls
   `deploy_ldap --confirm` directly when `ldap` namespace is missing.
5. Run `shellcheck -x bin/acg-up` — must exit 0 before and after.

---

## Rules

- `shellcheck -x bin/acg-up` must exit 0.
- Only `bin/acg-up` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `bin/acg-up` lines 115–122 match the **New** block above exactly.
2. `shellcheck -x bin/acg-up` exits 0.
3. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(acg-up): add deploy_ldap to Step 3.6 Hub bootstrap before deploy_argocd
   ```
4. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
5. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA under Open Items.
6. `memory-bank/progress.md`: add `[x] **acg-up Hub bootstrap LDAP missing** — COMPLETE (<sha>)` under Known Bugs / Gaps.
7. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `bin/acg-up`.
- Do NOT commit to `main`.
- Do NOT modify `scripts/plugins/argocd.sh` or `scripts/plugins/ldap.sh`.
- Do NOT call `deploy_ldap --confirm` directly — always call via `"${REPO_ROOT}/scripts/k3d-manager"`.
