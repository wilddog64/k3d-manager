# Bug: `acg-up` reseeds Keycloak admin credentials on every rebuild

**Status:** OPEN  
**Area:** `bin/acg-up` / Vault KV bootstrap / shopping-cart-infra Keycloak bootstrap

## Summary
`bin/acg-up` currently writes a fresh random `keycloak/admin` secret into Vault on every run:

```bash
_kc_admin_pass=$(openssl rand -base64 24 | tr -d '=+/')
_kc_db_pass=$(openssl rand -base64 24 | tr -d '=+/')
_vault_kv_put "{\"admin_password\":\"${_kc_admin_pass}\",\"db_password\":\"${_kc_db_pass}\"}" keycloak/admin
```

That is unsafe for rebuilds when the live Keycloak database persists, because the Keycloak admin user password stored in the DB does not automatically rotate to match the newly seeded Vault value.

## Evidence
The live Vault secret `secret/keycloak/admin` has multiple versions. Version `1` still works against the Keycloak admin token endpoint, while the current version does not.

### Working historical version
```text
MATCH_VERSION=1
```

### Failing current version
```text
{"error":"invalid_grant","error_description":"Invalid user credentials"}
HTTP:401
```

## Root Cause
`acg-up` treats the Keycloak admin secret as disposable bootstrap data, but the rebuilt cluster keeps the live Keycloak database state. The password in Vault changes, but the password in Keycloak's DB does not.

## Recommended Fix
- Reuse existing Vault values for `secret/keycloak/admin` when they already exist.
- Do not reseed Keycloak admin credentials on every rebuild.
- Preserve the existing `admin_password` so the admin token flow remains stable across cluster rebuilds.

## Follow-up
- Once the bootstrap is idempotent, refresh the live Vault `keycloak/admin` secret back to the version that still matches Keycloak's DB.
