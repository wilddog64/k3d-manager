# Bug: LDAP users share a hardcoded test password instead of Vault-generated unique passwords

**Date:** 2026-04-26
**Severity:** High — shared static credential, not real-world
**Spec type:** bug
**Branch:** `k3d-manager-v1.2.0`

---

## Problem

All LDAP users (`chengkai.liang`, `test-user`, `jenkins-admin`) share a single hardcoded
password `test1234` baked into `scripts/etc/ldap/bootstrap-basic-schema.ldif` as a static
SSHA hash. This violates the real-world requirement that every user credential must be:
1. Unique per user
2. Generated at bootstrap time (not committed to the repo)
3. Stored in Vault as the system of record
4. Retrievable via `ldap_get_user_password <username>` for automation use

Additionally, the ArgoCD Dex LDAP bind password (`cn=ldap-admin`) is applied ephemerally
via `kubectl patch` after cluster creation. It is not persisted to Vault or wired into
`deploy_ldap`, so it is lost on Hub cluster rebuild.

---

## Root Cause

`scripts/etc/ldap/bootstrap-basic-schema.ldif` — lines 49, 65, 81:
```
userPassword: {SSHA}Fvoa1XMaBL4y9QP0E6KcYYQUO901vjJg   # test1234
```

The LDIF is loaded as a static file (`LDAP_LDIF_FILE` default:
`scripts/etc/ldap/bootstrap-basic-schema.ldif`), sealed into the
`openldap-bitnami-ldif-import` secret, and applied at chart deploy time. There is no
post-deploy step to rotate passwords or store them in Vault.

---

## Fix

### Phase 1 — Remove hardcoded passwords from LDIF

In `scripts/etc/ldap/bootstrap-basic-schema.ldif`, remove the `userPassword:` line from
every user entry. OpenLDAP will create the account with no password (login disabled until
set). This is safe because Phase 2 immediately sets passwords after deploy.

Remove these three lines (one per user):
```
userPassword: {SSHA}Fvoa1XMaBL4y9QP0E6KcYYQUO901vjJg
```

Update the comment at the top from:
```
# Password for all users: test1234 (SSHA hash)
```
to:
```
# Passwords are NOT set in the LDIF — they are generated at bootstrap time and stored in Vault.
# Retrieve with: scripts/k3d-manager ldap_get_user_password <username>
```

### Phase 2 — Add `_ldap_rotate_user_passwords` to `scripts/plugins/ldap.sh`

Add a new private function after `_ldap_seed_ldif_secret` (~line 565):

```bash
function _ldap_rotate_user_passwords() {
  local vault_ns="${VAULT_NS:-${VAULT_NS_DEFAULT:-vault}}"
  local vault_release="${VAULT_RELEASE:-${VAULT_RELEASE_DEFAULT:-vault}}"
  local mount="${LDAP_VAULT_KV_MOUNT:-secret}"
  local base_dn="${LDAP_BASE_DN:-dc=home,dc=org}"
  local bind_dn="${LDAP_BINDDN:-cn=ldap-admin,dc=home,dc=org}"
  local ldap_pod ldap_ns admin_pass

  ldap_ns="${LDAP_NAMESPACE:-identity}"
  ldap_pod=$(kubectl get pod -n "${ldap_ns}" --context "${_KUBECTL_CONTEXT:-k3d-k3d-cluster}" \
    -l app.kubernetes.io/name=openldap-bitnami \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
  if [[ -z "$ldap_pod" ]]; then
    _err "[ldap] OpenLDAP pod not found in namespace ${ldap_ns}"
  fi

  admin_pass=$(_vault_exec --no-exit "$vault_ns" \
    "vault kv get -field=LDAP_ADMIN_PASSWORD ${mount}/ldap/openldap-admin" \
    "$vault_release" 2>/dev/null || true)
  if [[ -z "$admin_pass" ]]; then
    _err "[ldap] Could not read LDAP admin password from Vault at ${mount}/ldap/openldap-admin"
  fi

  local users=("chengkai.liang" "test-user" "jenkins-admin")
  for user in "${users[@]}"; do
    local vault_path="${mount}/ldap/users/${user}"
    local existing_pw=""
    existing_pw=$(_vault_exec --no-exit "$vault_ns" \
      "vault kv get -field=password ${vault_path}" \
      "$vault_release" 2>/dev/null || true)

    if [[ -n "$existing_pw" ]]; then
      _info "[ldap] Password for ${user} already in Vault — skipping generation"
      local pw="$existing_pw"
    else
      local pw
      pw=$(openssl rand -base64 24 | tr -d '=+/')
      _vault_exec "$vault_ns" \
        "vault kv put ${vault_path} password=${pw}" \
        "$vault_release" >/dev/null
      _info "[ldap] Generated and stored password for ${user} in Vault"
    fi

    kubectl exec -n "${ldap_ns}" --context "${_KUBECTL_CONTEXT:-k3d-k3d-cluster}" \
      "${ldap_pod}" -- \
      ldappasswd -x -H ldap://localhost:1389 \
        -D "${bind_dn}" -w "${admin_pass}" \
        -s "${pw}" \
        "cn=${user},ou=users,${base_dn}" >/dev/null
    _info "[ldap] Password set for ${user}"
  done
  _info "[ldap] All user passwords rotated and stored in Vault under ${mount}/ldap/users/"
}
```

### Phase 3 — Call rotation from `deploy_ldap`

In `scripts/plugins/ldap.sh`, at the end of the `deploy_ldap` public function, after the
LDIF import completes, add:

```bash
_info "[ldap] Rotating user passwords (Vault-generated, unique per user)..."
_ldap_rotate_user_passwords
```

### Phase 4 — Persist Dex bind password into `argocd-secret` during `deploy_argocd`

In `scripts/plugins/argocd.sh` (or wherever `deploy_argocd` applies the Helm chart),
after the chart is installed, add a step to read the LDAP admin password from Vault and
patch it into `argocd-secret`:

```bash
_ldap_admin_pw=$(vault kv get -field=LDAP_ADMIN_PASSWORD secret/ldap/openldap-admin 2>/dev/null || true)
if [[ -n "${_ldap_admin_pw}" ]]; then
  _ldap_admin_pw_b64=$(printf '%s' "${_ldap_admin_pw}" | base64)
  kubectl patch secret argocd-secret -n cicd --context k3d-k3d-cluster \
    --type=merge -p "{\"data\":{\"dex.ldap.bindPW\":\"${_ldap_admin_pw_b64}\"}}"
  kubectl rollout restart deployment/argocd-dex-server -n cicd --context k3d-k3d-cluster
  _info "[argocd] Dex LDAP bind password patched from Vault"
fi
```

---

## Files to Change

| File | Change |
|------|--------|
| `scripts/etc/ldap/bootstrap-basic-schema.ldif` | Remove 3 `userPassword:` lines; update comment |
| `scripts/plugins/ldap.sh` | Add `_ldap_rotate_user_passwords`; call from `deploy_ldap` |
| `scripts/plugins/argocd.sh` | Patch `argocd-secret` Dex bind PW from Vault after chart install |

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
- `git pull origin k3d-manager-v1.2.0`
- Read all three target files in full before touching anything
- Branch: all work on `k3d-manager-v1.2.0`

---

## Definition of Done

- [ ] `bootstrap-basic-schema.ldif` has no `userPassword:` lines; comment updated
- [ ] `_ldap_rotate_user_passwords` exists in `ldap.sh` and passes shellcheck
- [ ] `deploy_ldap` calls `_ldap_rotate_user_passwords` after LDIF import
- [ ] `deploy_argocd` patches `argocd-secret` with Dex bind PW from Vault
- [ ] `ldap_get_user_password chengkai.liang` returns a non-empty value after a clean bootstrap
- [ ] All passwords in Vault under `secret/ldap/users/<username>` are unique
- [ ] No `test1234` string appears anywhere in the codebase
- [ ] shellcheck passes with zero new warnings on modified files
- [ ] Committed on `k3d-manager-v1.2.0` with message:
      `fix(ldap): replace hardcoded test1234 with Vault-generated unique user passwords`
- [ ] Pushed to origin and SHA reported
- [ ] `memory-bank/activeContext.md` updated with commit SHA

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.2.0`
- Do NOT generate a single shared password for all users — each user gets their own
- Do NOT hardcode passwords or store them in the LDIF
