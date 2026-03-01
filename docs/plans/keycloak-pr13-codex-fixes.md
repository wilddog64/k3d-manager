# Codex Fix Spec — PR #13 Copilot Review (Keycloak)

**Branch:** `feature/infra-cluster-complete`
**Source:** Codex (chatgpt-codex-connector) review on PR #13
**Date:** 2026-03-03
**Written by:** Claude (no Gemini verification needed — pure logic, no cluster dependency)

---

## Issue 1 — P1: `auth.existingSecret` dangling without `--enable-vault`

**File:** `scripts/plugins/keycloak.sh`

`values.yaml.tmpl` always sets `auth.existingSecret: keycloak-admin-secret`, but that
secret is only created when `--enable-vault` is passed. Without it, the Keycloak pod
cannot start.

**Fix:** When `enable_vault=0`, generate a random password and create the secret
directly via `kubectl`. Insert this block immediately after the `enable_vault` block
(before the `enable_ldap` block), approximately at line 107:

```bash
# Before (nothing — secret is never created without --enable-vault):
   fi

   if (( enable_ldap )); then

# After (insert between the two blocks):
   fi

   if (( ! enable_vault )); then
      _info "[keycloak] --enable-vault not set — creating admin secret directly"
      local _direct_pw
      _direct_pw=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#%^&*' </dev/urandom | head -c 24)
      _kubectl -n "$KEYCLOAK_NAMESPACE" create secret generic "$KEYCLOAK_ADMIN_SECRET_NAME" \
         --from-literal="${KEYCLOAK_ADMIN_PASSWORD_KEY}=${_direct_pw}" \
         --dry-run=client -o yaml | _kubectl apply -f - >/dev/null
      _info "[keycloak] Admin secret '$KEYCLOAK_ADMIN_SECRET_NAME' created (no Vault)"
   fi

   if (( enable_ldap )); then
```

---

## Issue 2 — P1: `keycloakConfigCli.enabled: true` always — ConfigMap missing without `--enable-ldap`

**Files:** `scripts/plugins/keycloak.sh` + `scripts/etc/keycloak/values.yaml.tmpl`

`keycloakConfigCli.enabled: true` is hardcoded in the template. The ConfigMap
`keycloak-realm-config` is only created in the `--enable-ldap` path. Without
`--enable-ldap`, the config-cli job cannot find the ConfigMap and the install fails.

**Fix A — `values.yaml.tmpl`:** Replace the hardcoded `enabled: true` with a variable:

```yaml
# Before (line 11):
keycloakConfigCli:
  enabled: true

# After:
keycloakConfigCli:
  enabled: ${KEYCLOAK_CONFIG_CLI_ENABLED}
```

**Fix B — `keycloak.sh`:** Set the variable before rendering values, and add it to the
envsubst whitelist. The values rendering block is around line 116–120:

```bash
# Before:
   local values_file
   values_file=$(mktemp -t keycloak-values.XXXXXX.yaml)
   trap '$(_cleanup_trap_command "$values_file")' EXIT
   envsubst '$KEYCLOAK_ADMIN_USERNAME $KEYCLOAK_ADMIN_SECRET_NAME $KEYCLOAK_ADMIN_PASSWORD_KEY $KEYCLOAK_NAMESPACE $KEYCLOAK_SERVICE_PORT $KEYCLOAK_VIRTUALSERVICE_HOST' \
      < "$KEYCLOAK_CONFIG_DIR/values.yaml.tmpl" > "$values_file"

# After:
   local values_file config_cli_enabled="false"
   if (( enable_ldap )); then config_cli_enabled="true"; fi
   values_file=$(mktemp -t keycloak-values.XXXXXX.yaml)
   trap '$(_cleanup_trap_command "$values_file")' EXIT
   KEYCLOAK_CONFIG_CLI_ENABLED="$config_cli_enabled" \
   envsubst '$KEYCLOAK_ADMIN_USERNAME $KEYCLOAK_ADMIN_SECRET_NAME $KEYCLOAK_ADMIN_PASSWORD_KEY $KEYCLOAK_NAMESPACE $KEYCLOAK_SERVICE_PORT $KEYCLOAK_VIRTUALSERVICE_HOST $KEYCLOAK_CONFIG_CLI_ENABLED' \
      < "$KEYCLOAK_CONFIG_DIR/values.yaml.tmpl" > "$values_file"
```

---

## Issue 3 — P2: SecretStore not created when `--enable-ldap` used without `--enable-vault`

**File:** `scripts/plugins/keycloak.sh`

The LDAP ExternalSecret requires a SecretStore. SecretStore creation currently lives
inside the `enable_vault` block only. Running `deploy_keycloak --enable-ldap` (without
`--enable-vault`) leaves the LDAP ExternalSecret unready.

**Fix:** Hoist SecretStore + Vault policy setup to run whenever either `enable_vault`
or `enable_ldap` is active. Restructure the `enable_vault` block (lines 98–106):

```bash
# Before:
   if (( enable_vault )); then
      _keycloak_seed_vault_admin_secret
      _keycloak_setup_vault_policies
      envsubst < "$KEYCLOAK_CONFIG_DIR/secretstore.yaml.tmpl" | _kubectl apply -f - >/dev/null
      envsubst < "$KEYCLOAK_CONFIG_DIR/externalsecret-admin.yaml.tmpl" | _kubectl apply -f - >/dev/null
      if ! _kubectl -n "$KEYCLOAK_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$KEYCLOAK_ADMIN_SECRET_NAME" 2>/dev/null; then
         _warn "[keycloak] Timeout waiting for admin ExternalSecret"
      fi
   fi

# After:
   if (( enable_vault || enable_ldap )); then
      _keycloak_setup_vault_policies
      envsubst < "$KEYCLOAK_CONFIG_DIR/secretstore.yaml.tmpl" | _kubectl apply -f - >/dev/null
   fi

   if (( enable_vault )); then
      _keycloak_seed_vault_admin_secret
      envsubst < "$KEYCLOAK_CONFIG_DIR/externalsecret-admin.yaml.tmpl" | _kubectl apply -f - >/dev/null
      if ! _kubectl -n "$KEYCLOAK_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$KEYCLOAK_ADMIN_SECRET_NAME" 2>/dev/null; then
         _warn "[keycloak] Timeout waiting for admin ExternalSecret"
      fi
   fi
```

---

## Verification

After applying all three fixes:

```bash
shellcheck scripts/plugins/keycloak.sh
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/keycloak.bats
```

Both must pass. Push to `feature/infra-cluster-complete`. Do not open a new PR —
same PR #13 picks up the new commits automatically.
