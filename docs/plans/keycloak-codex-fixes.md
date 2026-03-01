# Codex Fix Task — Keycloak Plugin Issues (v0.5.0)

**Branch:** `feature/infra-cluster-complete`
**Source:** Gemini verification 2026-03-02 — 7/7 issues confirmed
**Status:** Pending Codex implementation

---

## Context

Codex committed `deploy_keycloak` in `7cc0ca9`. Claude reviewed and found 7 issues.
Gemini confirmed all 7. Apply every fix below, then run verification.

---

## Verification (run AFTER all fixes)

```bash
shellcheck scripts/plugins/keycloak.sh
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/keycloak.bats
```

Both must pass before committing. Do not commit if either fails.

---

## Fix 1 — Add missing `VAULT_VARS_FILE` source

**File:** `scripts/plugins/keycloak.sh`

**Why:** `secretstore.yaml.tmpl` uses `${VAULT_ENDPOINT}`. Without sourcing vault vars,
`VAULT_ENDPOINT` is empty and the SecretStore points to no server.

```bash
# Before — after the KEYCLOAK_VARS_FILE block (lines ~17-22):
KEYCLOAK_CONFIG_DIR="$SCRIPT_DIR/etc/keycloak"
KEYCLOAK_VARS_FILE="$KEYCLOAK_CONFIG_DIR/vars.sh"
if [[ -r "$KEYCLOAK_VARS_FILE" ]]; then
   # shellcheck disable=SC1090
   source "$KEYCLOAK_VARS_FILE"
fi

# After — add vault vars source immediately after:
KEYCLOAK_CONFIG_DIR="$SCRIPT_DIR/etc/keycloak"
KEYCLOAK_VARS_FILE="$KEYCLOAK_CONFIG_DIR/vars.sh"
if [[ -r "$KEYCLOAK_VARS_FILE" ]]; then
   # shellcheck disable=SC1090
   source "$KEYCLOAK_VARS_FILE"
fi

VAULT_VARS_FILE="$SCRIPT_DIR/etc/vault/vars.sh"
if [[ -r "$VAULT_VARS_FILE" ]]; then
   # shellcheck disable=SC1090
   source "$VAULT_VARS_FILE"
fi
```

---

## Fix 2 — Move `_keycloak_apply_realm_configmap` inside `--enable-ldap` block

**File:** `scripts/plugins/keycloak.sh`

**Why:** Realm configmap is applied on every deploy regardless of `--enable-ldap`.
It should only run when LDAP is enabled, after the LDAP ExternalSecret is Ready.

```bash
# Before:
   if (( enable_ldap )); then
      envsubst < "$KEYCLOAK_CONFIG_DIR/externalsecret-ldap.yaml.tmpl" | _kubectl apply -f - >/dev/null
      if ! _kubectl -n "$KEYCLOAK_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$KEYCLOAK_LDAP_SECRET_NAME" 2>/dev/null; then
         _warn "[keycloak] Timeout waiting for LDAP ExternalSecret"
      fi
   fi

   _keycloak_apply_realm_configmap

# After:
   if (( enable_ldap )); then
      envsubst < "$KEYCLOAK_CONFIG_DIR/externalsecret-ldap.yaml.tmpl" | _kubectl apply -f - >/dev/null
      if ! _kubectl -n "$KEYCLOAK_NAMESPACE" wait --for=condition=Ready --timeout=60s externalsecret/"$KEYCLOAK_LDAP_SECRET_NAME" 2>/dev/null; then
         _warn "[keycloak] Timeout waiting for LDAP ExternalSecret"
      fi
      _keycloak_apply_realm_configmap
   fi
```

---

## Fix 3 — Update `_keycloak_apply_realm_configmap` to inject LDAP password from K8s secret

**File:** `scripts/plugins/keycloak.sh`

**Why:** The LDAP bind password is a secret — it must be read from the ESO-synced
K8s secret at ConfigMap creation time and passed via envsubst, not stored in vars.sh.
The envsubst whitelist also needs updating to match the new template variables.

```bash
# Before:
function _keycloak_apply_realm_configmap() {
   local rendered
   rendered=$(mktemp -t keycloak-realm.XXXXXX.json)
   trap '$(_cleanup_trap_command "$rendered")' RETURN
   envsubst '$KEYCLOAK_REALM_NAME $KEYCLOAK_REALM_DISPLAY_NAME $KEYCLOAK_LDAP_HOST $KEYCLOAK_LDAP_PORT $KEYCLOAK_LDAP_SEARCH_BASE $KEYCLOAK_LDAP_BINDDN_KEY $KEYCLOAK_LDAP_PASSWORD_KEY' \
      < "$KEYCLOAK_CONFIG_DIR/realm-config.json.tmpl" > "$rendered"

# After:
function _keycloak_apply_realm_configmap() {
   local rendered
   rendered=$(mktemp -t keycloak-realm.XXXXXX.json)
   trap '$(_cleanup_trap_command "$rendered")' RETURN

   # Read LDAP bind password from the ESO-synced K8s secret (set by Fix 2 ordering)
   local ldap_password
   ldap_password=$(_kubectl -n "$KEYCLOAK_NAMESPACE" get secret "$KEYCLOAK_LDAP_SECRET_NAME" \
      -o "jsonpath={.data.${KEYCLOAK_LDAP_PASSWORD_KEY}}" 2>/dev/null | base64 -d)

   KEYCLOAK_LDAP_ADMIN_PASSWORD="$ldap_password" \
   envsubst '$KEYCLOAK_REALM_NAME $KEYCLOAK_REALM_DISPLAY_NAME $KEYCLOAK_LDAP_HOST $KEYCLOAK_LDAP_PORT $KEYCLOAK_LDAP_BIND_DN $KEYCLOAK_LDAP_USERS_DN $KEYCLOAK_LDAP_ADMIN_PASSWORD' \
      < "$KEYCLOAK_CONFIG_DIR/realm-config.json.tmpl" > "$rendered"
```

---

## Fix 4 — Add missing variables to `vars.sh`

**File:** `scripts/etc/keycloak/vars.sh`

**Why:** `KEYCLOAK_LDAP_BIND_DN` (actual DN string), `KEYCLOAK_LDAP_USERS_DN`, and
`KEYCLOAK_VIRTUALSERVICE_GATEWAY` are referenced in templates but not defined.

```bash
# Add to the LDAP integration section (after KEYCLOAK_LDAP_SEARCH_BASE):
export KEYCLOAK_LDAP_BIND_DN="${KEYCLOAK_LDAP_BIND_DN:-cn=ldap-admin,dc=home,dc=org}"
export KEYCLOAK_LDAP_USERS_DN="${KEYCLOAK_LDAP_USERS_DN:-ou=users,dc=home,dc=org}"

# Add to the Istio / access configuration section:
export KEYCLOAK_VIRTUALSERVICE_GATEWAY="${KEYCLOAK_VIRTUALSERVICE_GATEWAY:-istio-system/default-gateway}"
```

---

## Fix 5 — Rewrite `realm-config.json.tmpl` to modern Keycloak 17+ format

**File:** `scripts/etc/keycloak/realm-config.json.tmpl`

**Why:** `userFederationProviders` is the legacy WildFly-era format ignored by
Keycloak 17+ (Quarkus). Bitnami ships Keycloak 21+. Must use `components` format.
Also fixes `bindDn`/`bindCredential` to use actual value variables.

Replace the entire file with:

```json
{
  "realm": "${KEYCLOAK_REALM_NAME}",
  "displayName": "${KEYCLOAK_REALM_DISPLAY_NAME}",
  "enabled": true,
  "registrationAllowed": false,
  "loginTheme": "keycloak",
  "components": {
    "org.keycloak.storage.UserStorageProvider": [
      {
        "name": "openldap",
        "providerId": "ldap",
        "subComponents": {
          "org.keycloak.storage.ldap.mappers.LDAPStorageMapper": [
            {
              "name": "username",
              "providerId": "user-attribute-ldap-mapper",
              "subComponents": {},
              "config": {
                "ldap.attribute": ["cn"],
                "user.model.attribute": ["username"],
                "read.only": ["true"],
                "always.read.value.from.ldap": ["false"],
                "is.mandatory.in.ldap": ["true"]
              }
            }
          ]
        },
        "config": {
          "enabled": ["true"],
          "priority": ["0"],
          "editMode": ["READ_ONLY"],
          "syncRegistrations": ["false"],
          "vendor": ["other"],
          "usernameLDAPAttribute": ["cn"],
          "rdnLDAPAttribute": ["cn"],
          "uuidLDAPAttribute": ["entryUUID"],
          "userObjectClasses": ["inetOrgPerson, organizationalPerson"],
          "connectionUrl": ["ldap://${KEYCLOAK_LDAP_HOST}:${KEYCLOAK_LDAP_PORT}"],
          "usersDn": ["${KEYCLOAK_LDAP_USERS_DN}"],
          "authType": ["simple"],
          "bindDn": ["${KEYCLOAK_LDAP_BIND_DN}"],
          "bindCredential": ["${KEYCLOAK_LDAP_ADMIN_PASSWORD}"],
          "searchScope": ["1"],
          "useTruststoreSpi": ["ldapsOnly"],
          "connectionPooling": ["true"],
          "cachePolicy": ["DEFAULT"],
          "debug": ["false"]
        }
      }
    ]
  }
}
```

---

## Fix 6 — Clean up `values.yaml.tmpl`: remove legacy import, fix `KEYCLOAK_USER`

**File:** `scripts/etc/keycloak/values.yaml.tmpl`

**Why:** `extraVolumeMounts`/`extraVolumes`/`extraEnvVars` with `KEYCLOAK_IMPORT` is the
pre-17 import method — ignored and conflicts with `keycloakConfigCli`.
`KEYCLOAK_USER` must be the admin username string, not the password secretKeyRef.

```yaml
# Before (remove these entire blocks):
extraVolumeMounts:
  - name: realm-config
    mountPath: /realm
extraVolumes:
  - name: realm-config
    configMap:
      name: keycloak-realm-config
extraEnvVars:
  - name: KEYCLOAK_IMPORT
    value: /realm/realm-config.json

# And fix KEYCLOAK_USER inside keycloakConfigCli.env:
# Before:
    - name: KEYCLOAK_USER
      valueFrom:
        secretKeyRef:
          name: ${KEYCLOAK_ADMIN_SECRET_NAME}
          key: ${KEYCLOAK_ADMIN_PASSWORD_KEY}

# After:
    - name: KEYCLOAK_USER
      value: ${KEYCLOAK_ADMIN_USERNAME}
```

The final `keycloakConfigCli` block should look like:

```yaml
keycloakConfigCli:
  enabled: true
  existingConfigmap: keycloak-realm-config
  podAnnotations:
    sidecar.istio.io/inject: "false"
  env:
    - name: KEYCLOAK_URL
      value: http://keycloak.${KEYCLOAK_NAMESPACE}.svc.cluster.local:${KEYCLOAK_SERVICE_PORT}
    - name: KEYCLOAK_USER
      value: ${KEYCLOAK_ADMIN_USERNAME}
    - name: KEYCLOAK_PASSWORD
      valueFrom:
        secretKeyRef:
          name: ${KEYCLOAK_ADMIN_SECRET_NAME}
          key: ${KEYCLOAK_ADMIN_PASSWORD_KEY}
```

---

## Fix 7 — Parameterize `virtualservice.yaml.tmpl`

**File:** `scripts/etc/keycloak/virtualservice.yaml.tmpl`

**Why:** Namespace hardcoded to `istio-system` and gateway hardcoded — inconsistent
with the ArgoCD pattern which uses `${ARGOCD_NAMESPACE}` and `${ARGOCD_VIRTUALSERVICE_GATEWAY}`.
Use `${KEYCLOAK_NAMESPACE}` for the metadata namespace (consistent with ArgoCD).
`KEYCLOAK_VIRTUALSERVICE_GATEWAY` is added to vars.sh in Fix 4.

```yaml
# Before:
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: keycloak
  namespace: istio-system
spec:
  hosts:
    - ${KEYCLOAK_VIRTUALSERVICE_HOST}
  gateways:
    - istio-system/default-gateway

# After:
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: keycloak
  namespace: ${KEYCLOAK_NAMESPACE}
spec:
  hosts:
    - ${KEYCLOAK_VIRTUALSERVICE_HOST}
  gateways:
    - ${KEYCLOAK_VIRTUALSERVICE_GATEWAY}
```

---

## Files Changed Summary

| File | Change |
|---|---|
| `scripts/plugins/keycloak.sh` | Fix 1: add VAULT_VARS_FILE source |
| `scripts/plugins/keycloak.sh` | Fix 2: move `_keycloak_apply_realm_configmap` inside `enable_ldap` |
| `scripts/plugins/keycloak.sh` | Fix 3: update `_keycloak_apply_realm_configmap` to read LDAP password from K8s secret |
| `scripts/etc/keycloak/vars.sh` | Fix 4: add `KEYCLOAK_LDAP_BIND_DN`, `KEYCLOAK_LDAP_USERS_DN`, `KEYCLOAK_VIRTUALSERVICE_GATEWAY` |
| `scripts/etc/keycloak/realm-config.json.tmpl` | Fix 5: rewrite to modern `components` format |
| `scripts/etc/keycloak/values.yaml.tmpl` | Fix 6: remove legacy import, fix `KEYCLOAK_USER` |
| `scripts/etc/keycloak/virtualservice.yaml.tmpl` | Fix 7: parameterize namespace and gateway |

---

## Do NOT

- Change any other files
- Modify `keycloak.bats` (tests should pass as-is after fixes)
- Open a PR (Claude opens PR after fixes)
