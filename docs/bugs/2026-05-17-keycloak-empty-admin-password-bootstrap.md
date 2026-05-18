# Bug: Keycloak bootstraps with empty admin password when ExternalSecret or Vault field is missing

**Branch:** `k3d-manager-v1.4.6`
**Files:**
- `scripts/plugins/keycloak.sh` — lines 104–112
- `bin/acg-up` — lines 623–631

---

## Before You Start

```
git pull origin k3d-manager-v1.4.6
```

Read this spec in full before touching any file.

---

## Problem

Two independent gaps let Keycloak start (or the realm import run) with an empty admin
password, producing a `password empty` failure that is logged but not surfaced as a hard
error — so the deploy path keeps going silently.

**Gap 1 — `deploy_keycloak` warns instead of failing on ExternalSecret timeout.**
`scripts/plugins/keycloak.sh:107–109`: when the admin ExternalSecret doesn't become Ready
within 60 s, the function logs a warning and falls through to `helm upgrade`. Keycloak then
starts with no password, and the admin token request in Step 10d of `acg-up` fails with
`invalid_grant` / `password empty`.

**Gap 2 — `acg-up` never validates `_kc_admin_pass` / `_kc_db_pass` after reading from Vault.**
`bin/acg-up:623–631`: when `keycloak/admin` already exists in Vault, `_vault_kv_get_field`
is called but the result is not checked. If the field is blank (e.g. the secret was
written without the key), the script proceeds with `_kc_admin_pass=""` — identical to the
empty-password failure mode.

---

## Fix

### Change 1 — `scripts/plugins/keycloak.sh`: hard-fail + non-empty secret check

**Exact old block (lines 107–109):**

```bash
      if ! _kubectl -n "$KEYCLOAK_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$KEYCLOAK_ADMIN_SECRET_NAME" 2>/dev/null; then
         _warn "[keycloak] Timeout waiting for admin ExternalSecret"
      fi
```

**Exact new block:**

```bash
      if ! _kubectl -n "$KEYCLOAK_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$KEYCLOAK_ADMIN_SECRET_NAME" 2>/dev/null; then
         _err "[keycloak] Admin ExternalSecret not Ready; refusing to start Keycloak with an empty admin password"
         return 1
      fi
      local _admin_pw
      _admin_pw=$(_kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_ADMIN_SECRET_NAME" \
         -o jsonpath="{.data.${KEYCLOAK_ADMIN_PASSWORD_KEY}}" | base64 -d)
      if [[ -z "${_admin_pw}" ]]; then
         _err "[keycloak] Secret '$KEYCLOAK_ADMIN_SECRET_NAME' has an empty '${KEYCLOAK_ADMIN_PASSWORD_KEY}'"
         return 1
      fi
```

---

### Change 2 — `bin/acg-up`: validate Vault fields after read

**Exact old block (lines 623–631):**

```bash
if _vault_kv_exists "keycloak/admin"; then
  _info "[acg-up] Reusing existing Vault secret keycloak/admin"
  _kc_admin_pass=$(_vault_kv_get_field "keycloak/admin" "admin_password")
  _kc_db_pass=$(_vault_kv_get_field "keycloak/admin" "db_password")
else
  _kc_admin_pass=$(openssl rand -base64 24 | tr -d '=+/')
  _kc_db_pass=$(openssl rand -base64 24 | tr -d '=+/')
  _vault_kv_put "{\"admin_password\":\"${_kc_admin_pass}\",\"db_password\":\"${_kc_db_pass}\"}" keycloak/admin
fi
```

**Exact new block:**

```bash
if _vault_kv_exists "keycloak/admin"; then
  _info "[acg-up] Reusing existing Vault secret keycloak/admin"
  _kc_admin_pass=$(_vault_kv_get_field "keycloak/admin" "admin_password")
  _kc_db_pass=$(_vault_kv_get_field "keycloak/admin" "db_password")
  if [[ -z "${_kc_admin_pass}" || -z "${_kc_db_pass}" ]]; then
    _acg_fail "[acg-up] Vault secret keycloak/admin is missing admin_password or db_password — restore the secret before continuing"
  fi
else
  _kc_admin_pass=$(openssl rand -base64 24 | tr -d '=+/')
  _kc_db_pass=$(openssl rand -base64 24 | tr -d '=+/')
  _vault_kv_put "{\"admin_password\":\"${_kc_admin_pass}\",\"db_password\":\"${_kc_db_pass}\"}" keycloak/admin
fi
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/keycloak.sh` | Hard-fail on ExternalSecret timeout; verify secret key is non-empty |
| `bin/acg-up` | Validate `_kc_admin_pass` and `_kc_db_pass` after Vault read |

---

## Rules

- `shellcheck -S warning scripts/plugins/keycloak.sh` — zero new warnings
- `shellcheck -S warning bin/acg-up` — zero new warnings
- No other files modified

---

## Definition of Done

- [ ] `keycloak.sh` lines 107–109 replaced with hard-fail + non-empty check (exact new block above)
- [ ] `acg-up` lines 623–631 replaced with Vault field validation (exact new block above)
- [ ] `shellcheck -S warning scripts/plugins/keycloak.sh` passes with zero new warnings
- [ ] `shellcheck -S warning bin/acg-up` passes with zero new warnings
- [ ] Committed to `k3d-manager-v1.4.6`
- [ ] `git push origin k3d-manager-v1.4.6` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status
- [ ] Report back: commit SHA + `git show <sha> --stat`

**Commit message (exact):**
```
fix(keycloak): hard-fail on empty admin secret in deploy_keycloak and acg-up Vault read
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.4.6`
- Do NOT touch the LDAP federation registration — that is a separate issue
