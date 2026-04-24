# Bug: deploy_argocd hardcodes `ldap` namespace — always fails dependency check

**Date:** 2026-04-24
**Status:** OPEN
**Severity:** HIGH (deploy_argocd always calls deploy_ldap --confirm directly → _err → exit 1)
**Branch:** `k3d-manager-v1.1.0`

## Summary

`deploy_argocd` checks `_kubectl get ns ldap` to decide whether LDAP is deployed.
But `LDAP_NAMESPACE` defaults to `identity` (set in `scripts/etc/ldap/vars.sh`).
The `ldap` namespace never exists, so the check always fires and calls
`deploy_ldap --confirm` directly. `_ldap_parse_deploy_opts` does not handle `--confirm`
— it hits `_err "[ldap] unknown option: --confirm"` and exits 1:

```
INFO: [argocd] Verifying infrastructure foundations...
make: *** [up] Error 1
```

Pre-deploying LDAP in Step 3.6 (`c650f032`) did NOT fix this: LDAP deploys to the
`identity` namespace, but the check still looks for `ldap`.

## Root Cause

`scripts/plugins/argocd.sh` line 87 hardcodes the namespace name:

```bash
if ! _kubectl get ns ldap >/dev/null 2>&1; then
```

The actual LDAP namespace is determined by `LDAP_NAMESPACE`, which defaults to
`identity` in `scripts/etc/ldap/vars.sh`. The hardcoded check is always wrong when
`LDAP_NAMESPACE != "ldap"`.

## Fix

Replace the hardcoded `ldap` with `${LDAP_NAMESPACE:-ldap}` so the check uses the
actual configured namespace.

**File:** `scripts/plugins/argocd.sh`

**Old (line 87):**
```bash
   if ! _kubectl get ns ldap >/dev/null 2>&1; then
```

**New (line 87):**
```bash
   if ! _kubectl get ns "${LDAP_NAMESPACE:-ldap}" >/dev/null 2>&1; then
```

One word changed. No other lines change.

---

## Before You Start

1. `git pull origin k3d-manager-v1.1.0`
2. Read `scripts/plugins/argocd.sh` lines 81–90 in full.
3. Read `scripts/etc/ldap/vars.sh` line 1 — confirms `LDAP_NAMESPACE` defaults to `identity`.
4. Run `shellcheck -x scripts/plugins/argocd.sh` — must exit 0 before and after.

---

## Rules

- `shellcheck -x scripts/plugins/argocd.sh` must exit 0.
- Only `scripts/plugins/argocd.sh` may be touched.
- Do NOT add `--no-verify` to any git command.
- Do NOT commit to `main`.
- Do NOT create a PR.

---

## Definition of Done

1. `scripts/plugins/argocd.sh` line 87 matches the **New** block above exactly.
2. `shellcheck -x scripts/plugins/argocd.sh` exits 0.
3. Committed on `k3d-manager-v1.1.0` with message:
   ```
   fix(argocd): use LDAP_NAMESPACE variable in dependency check instead of hardcoded 'ldap'
   ```
4. Branch pushed to `origin/k3d-manager-v1.1.0` before reporting done.
5. `memory-bank/activeContext.md`: add entry for this fix as COMPLETE with real commit SHA under Open Items.
6. `memory-bank/progress.md`: add `[x] **argocd LDAP namespace hardcoded** — COMPLETE (<sha>)` under Known Bugs / Gaps.
7. Report back: commit SHA + paste the memory-bank lines you updated.

---

## What NOT To Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `scripts/plugins/argocd.sh`.
- Do NOT commit to `main`.
- Do NOT change the `deploy_vault` dependency check on line 83 — only the `ldap` check on line 87.
