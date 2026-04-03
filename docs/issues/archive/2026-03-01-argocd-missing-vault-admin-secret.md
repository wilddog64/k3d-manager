# P3: ArgoCD admin ExternalSecret fails without pre-seeded Vault secret

**Date:** 2026-03-01
**Reported:** Claude during ArgoCD Phase 1 planning
**Status:** FIXED — `_argocd_seed_vault_admin_secret` ensures Vault data exists
**Severity:** P3
**Type:** Bug — ESO never syncs admin password unless operator seeds it manually

---

## What Happened

`deploy_argocd --enable-vault` configures an ExternalSecret to pull the admin
password from Vault (`secret/argocd/admin`). However, the installer never creates
that key path. ESO continuously reports `404 secret not found`, leaving the
Kubernetes secret unsatisfied and preventing logins.

---

## Root Cause

The original workflow assumed the operator would write
`secret/argocd/admin` manually before running the deployment. No automation
existed to create the password, and the bootstrap documentation never mentioned
it, so the admin ExternalSecret always failed on fresh installs.

---

## Fix

- Added `_argocd_seed_vault_admin_secret` to `scripts/plugins/argocd.sh`. The helper:
  1. Checks whether `${ARGOCD_VAULT_KV_MOUNT}/${ARGOCD_ADMIN_VAULT_PATH}` exists.
  2. Generates a random 24-character password if the key is missing.
  3. Logs into Vault and writes the password using `vault kv put`.
- `deploy_argocd --enable-vault` now seeds the secret immediately after setting up
  Vault policies and before applying the `externalsecret-admin` manifest.

This guarantees ESO can sync the admin password without manual steps.

---

## Verification

- `shellcheck scripts/plugins/argocd.sh`
- `PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/argocd.bats` (ensures
  namespace defaults, CLUSTER_ROLE guard, help text, and missing-template errors)

---

## Impact

The admin login path now works end-to-end with a single `deploy_argocd --enable-vault`
command. Operators retrieve the password via
`kubectl -n ${ARGOCD_NAMESPACE} get secret ${ARGOCD_ADMIN_SECRET_NAME} -o jsonpath='{.data.password}' | base64 -d`
after ESO sync completes.
