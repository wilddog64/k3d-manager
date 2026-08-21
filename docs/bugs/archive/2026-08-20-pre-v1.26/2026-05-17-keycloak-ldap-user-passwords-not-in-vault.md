# Bug: Keycloak LDAP user passwords (admin/developer/operator) not stored in Vault — lost on every make up

**Branch:** `k3d-manager-v1.4.6`
**Files:**
- `bin/acg-up` — insert Step 10d.5 after line 811 (`fi` closing the realm import block)

---

## Before You Start

```
git pull origin k3d-manager-v1.4.6
```

Read this spec in full before touching any file.

---

## Problem

`bin/acg-up` deploys the shopping-cart identity stack (Keycloak + LDAP) via ArgoCD. The LDAP
bootstrap LDIF creates three users — `admin`, `developer`, `operator` — with SSHA-hashed
passwords baked into the LDIF. The plaintext passwords are not stored anywhere.

On every `make up` the LDAP pod may be recreated from the bootstrap LDIF, resetting passwords
to the original SSHA hash (unknown plaintext). Users cannot log into the shopping-cart
frontend because the Keycloak LDAP federation cannot validate any known password.

`_ldap_admin_pass` (the LDAP bind credential) is already available in scope at the insertion
point. The pattern for generating + Vault-storing passwords is already established in `bin/acg-up`
for `ldap/admin`, `keycloak/admin`, and `keycloak/clients`.

---

## Fix

### Change 1 — `bin/acg-up`: add Step 10d.5 after the realm import block

**Exact insertion point — after this line (line 811):**
```bash
fi
```
(This is the `fi` that closes the outer `if _kubectl ... get deployment/keycloak` block at line 738.
It is immediately followed by the blank line before `if _is_mac; then` for Step 10e.)

**Insert this block between lines 811 and 813:**
```bash

_info "[acg-up] Step 10d.5/14 — Seeding Keycloak LDAP user passwords in LDAP + Vault..."
_ldap_pod=$(kubectl get pod -n identity --context k3d-k3d-cluster \
  -l app.kubernetes.io/name=ldap \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "${_ldap_pod}" ]]; then
  _warn "[acg-up] LDAP pod not found in identity namespace — skipping user password seed"
else
  for _ldap_user in admin developer operator; do
    _ldap_user_vault_path="keycloak/users/${_ldap_user}"
    if _vault_kv_exists "${_ldap_user_vault_path}"; then
      _ldap_user_pass=$(_vault_kv_get_field "${_ldap_user_vault_path}" "password")
    else
      _ldap_user_pass=$(openssl rand -base64 18 | tr -d '=+/')
      _vault_kv_put "{\"username\":\"${_ldap_user}\",\"password\":\"${_ldap_user_pass}\"}" "${_ldap_user_vault_path}"
    fi
    if kubectl exec -n identity --context k3d-k3d-cluster "${_ldap_pod}" -- \
        ldappasswd -x -H ldap://localhost:389 \
        -D "cn=admin,dc=shopping-cart,dc=local" \
        -w "${_ldap_admin_pass}" \
        -s "${_ldap_user_pass}" \
        "uid=${_ldap_user},ou=users,dc=shopping-cart,dc=local" >/dev/null 2>&1; then
      _info "[acg-up] LDAP password set for user '${_ldap_user}'"
    else
      _warn "[acg-up] Failed to set LDAP password for user '${_ldap_user}' — login may fail"
    fi
  done
  _info "[acg-up] Retrieve passwords: bin/vault-exec --namespace secrets -- vault kv get -field=password secret/keycloak/users/<user>"
fi

```

---

## Exact context to locate the insertion point

The block should appear between these two lines:

```bash
fi
                          ← INSERT HERE (blank line then the new block then blank line)
if _is_mac; then
  _info "[acg-up] Step 10e/14 — Installing Istio ingress HTTP listener (keycloak + frontend → 127.0.0.1:80, auto-restart)..."
```

---

## Files Changed

| File | Change |
|------|--------|
| `bin/acg-up` | Add Step 10d.5 after realm import block: generate + Vault-store + LDAP-set passwords for admin/developer/operator |

---

## Rules

- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files modified
- `_vault_kv_exists`, `_vault_kv_get_field`, `_vault_kv_put` are already in scope — do not redefine
- `_ldap_admin_pass` is already in scope at the insertion point — do not re-read from Vault
- Failure to set a password is a `_warn`, not `_err` — identity stack issues must not block the rest of make up
- The `for` loop variable `_ldap_user` uses underscore prefix (private convention for acg-up local vars)

---

## Definition of Done

- [ ] Step 10d.5 block inserted between lines 811 and 813 (exact new block above)
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

**Commit message (exact):**
```
fix(acg-up): seed Keycloak LDAP user passwords in Vault on every make up
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT add `_vault_kv_*` helper definitions — they are already defined earlier in `bin/acg-up`
- Do NOT change the `_warn` to `_err` — password seed failure must not halt make up

---

## After the Fix

To retrieve a user's password at any time:

```bash
bin/vault-exec --namespace secrets -- vault kv get -field=password secret/keycloak/users/developer
```
