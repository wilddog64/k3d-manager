# Gemini Verification Task — Keycloak Plugin (v0.5.0)

**Branch:** `feature/infra-cluster-complete`
**Requested by:** Claude (2026-03-01)
**Status:** Pending Gemini verification

---

## Your Job

1. Run `shellcheck` and `bats` — both must pass
2. Confirm or deny each issue in the **Suspected Issues** table below
3. If confirmed, write a fix spec for Codex (exact before/after diffs)
4. Update this file with your findings and sign off

Do **not** fix code yourself — write the Codex spec only.

---

## Step 1 — Mechanical Checks

```bash
cd /path/to/k3d-manager

# Shellcheck
shellcheck scripts/plugins/keycloak.sh

# Bats
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/keycloak.bats
```

Report exact output of both. If bats fails, note which cases fail and why.

---

## Step 2 — Confirm or Deny Each Suspected Issue

### Issue 1 — `_keycloak_apply_realm_configmap` called unconditionally

**File:** `scripts/plugins/keycloak.sh:108`

**Suspected:** `_keycloak_apply_realm_configmap` is called at line 108 unconditionally,
before the Helm install, regardless of whether `--enable-ldap` was passed.
Per the plan, it should only run inside `if (( enable_ldap ))` after the LDAP
ExternalSecret is Ready.

**Verify:** Read lines 100–120. Is the call inside or outside the `if (( enable_ldap ))` block?

**Risk if confirmed:** Every `deploy_keycloak` (even without LDAP) creates the
`keycloak-realm-config` ConfigMap with placeholder variable names instead of values,
and `keycloakConfigCli` will attempt to import it.

---

### Issue 2 — Missing `VAULT_VARS_FILE` source

**File:** `scripts/plugins/keycloak.sh` (header, lines 1–25)

**Suspected:** The plugin does not source `scripts/etc/vault/vars.sh`, so `VAULT_ENDPOINT`
is undefined when `envsubst` renders `secretstore.yaml.tmpl`. Compare with
`scripts/plugins/argocd.sh` lines 20–25 which explicitly sources vault vars.

**Verify:** Check if `VAULT_VARS_FILE` or `VAULT_ENDPOINT` is sourced anywhere in the
plugin header.

**Risk if confirmed:** SecretStore `.spec.provider.vault.server` will be empty string,
causing ESO to fail to connect to Vault.

---

### Issue 3 — `realm-config.json.tmpl` injects key names not values

**File:** `scripts/etc/keycloak/realm-config.json.tmpl:25-26`

**Suspected:**
```json
"bindDn": "${KEYCLOAK_LDAP_BINDDN_KEY}",
"bindCredential": "${KEYCLOAK_LDAP_PASSWORD_KEY}"
```
`KEYCLOAK_LDAP_BINDDN_KEY` defaults to `LDAP_BIND_DN` (the secret key name).
`KEYCLOAK_LDAP_PASSWORD_KEY` defaults to `LDAP_ADMIN_PASSWORD` (the secret key name).
These are the Kubernetes secret field names, not the actual LDAP bind DN or password.
The rendered ConfigMap will contain the string `"LDAP_BIND_DN"` as the bind DN,
which is not a valid LDAP distinguished name.

**Verify:** Check `scripts/etc/keycloak/vars.sh` — is there a `KEYCLOAK_LDAP_BIND_DN`
variable (the actual DN string like `cn=ldap-admin,dc=home,dc=org`)? Is it referenced
in the template?

**Risk if confirmed:** LDAP federation will fail to connect — Keycloak will send
`LDAP_BIND_DN` as the bind DN to the LDAP server.

---

### Issue 4 — `realm-config.json.tmpl` uses deprecated `userFederationProviders` format

**File:** `scripts/etc/keycloak/realm-config.json.tmpl:7`

**Suspected:** The template uses `"userFederationProviders"` which is the legacy
Keycloak realm export format (Keycloak < 17, WildFly-based). Bitnami's Keycloak chart
ships Keycloak 21+ (Quarkus-based), which uses the `"components"` format for user
federation. `keycloak-config-cli` will either ignore or error on the legacy format.

The plan specified the correct modern format:
```json
"components": {
  "org.keycloak.storage.UserStorageProvider": [...]
}
```

**Verify:** Check the Bitnami Keycloak chart version used (`helm show chart bitnami/keycloak`
or check `KEYCLOAK_HELM_CHART_VERSION` in vars.sh). Confirm the Keycloak app version —
if 17+, `userFederationProviders` is ignored by `keycloak-config-cli`.

**Risk if confirmed:** LDAP federation silently not configured — `deploy_keycloak --enable-ldap`
appears to succeed but Keycloak has no LDAP provider.

---

### Issue 5 — `values.yaml.tmpl` `KEYCLOAK_USER` mapped to password

**File:** `scripts/etc/keycloak/values.yaml.tmpl:29-33`

**Suspected:**
```yaml
- name: KEYCLOAK_USER
  valueFrom:
    secretKeyRef:
      name: ${KEYCLOAK_ADMIN_SECRET_NAME}
      key: ${KEYCLOAK_ADMIN_PASSWORD_KEY}
```
`KEYCLOAK_USER` (the admin username) is populated from the password secretKeyRef.
Both `KEYCLOAK_USER` and `KEYCLOAK_PASSWORD` point to the same key. The username
should be the literal string `admin` (or `${KEYCLOAK_ADMIN_USERNAME}`), not a
secret reference.

**Verify:** Read lines 25–40 of `values.yaml.tmpl`. Do both `KEYCLOAK_USER` and
`KEYCLOAK_PASSWORD` reference the same secretKeyRef key?

**Risk if confirmed:** `keycloak-config-cli` will send the admin password as the username,
causing authentication failure and realm import to fail.

---

### Issue 6 — `values.yaml.tmpl` duplicate/conflicting realm import methods

**File:** `scripts/etc/keycloak/values.yaml.tmpl:10-19`

**Suspected:** The template includes both:
- `extraVolumeMounts` + `extraEnvVars.KEYCLOAK_IMPORT` — legacy pre-17 import method
- `keycloakConfigCli.enabled: true` — modern Bitnami-supported method

These two methods are mutually exclusive. `KEYCLOAK_IMPORT` is not supported in
Keycloak 17+ (Quarkus). Having both may cause undefined behavior or chart errors.

**Verify:** Check whether `extraVolumeMounts`, `extraVolumes`, and `extraEnvVars` with
`KEYCLOAK_IMPORT` are present alongside `keycloakConfigCli.enabled: true`.

**Risk if confirmed:** Chart may fail with unknown values, or `KEYCLOAK_IMPORT` is
silently ignored leaving only `keycloakConfigCli` active (less bad but wasteful and
confusing).

---

### Issue 7 — `virtualservice.yaml.tmpl` hardcoded namespace and gateway

**File:** `scripts/etc/keycloak/virtualservice.yaml.tmpl:5,10`

**Suspected:**
```yaml
metadata:
  namespace: istio-system          # hardcoded
gateways:
  - istio-system/default-gateway   # hardcoded
```
The ArgoCD VirtualService uses `${ARGOCD_NAMESPACE}` for the metadata namespace
and `${ARGOCD_VIRTUALSERVICE_GATEWAY}` for the gateway. Keycloak's template
hardcodes both. `KEYCLOAK_VIRTUALSERVICE_GATEWAY` is defined in the plan's vars.sh
spec but was not added to `scripts/etc/keycloak/vars.sh`.

**Verify:** Check `vars.sh` for `KEYCLOAK_VIRTUALSERVICE_GATEWAY`. Check if the
namespace and gateway in the VS template are parameterized or hardcoded.

**Risk if confirmed:** Cannot override gateway without editing the template file.
Minor for home lab but violates the project's configuration-driven pattern.

---

## Step 3 — Sign-off

After verifying all issues, update this file with:

```
## Gemini Findings

| Issue | Confirmed? | Fix Required? |
|---|---|---|
| 1 — realm configmap unconditional | Yes/No | Yes/No |
| 2 — missing VAULT_VARS_FILE | Yes/No | Yes/No |
| 3 — bindDn/bindCredential key names | Yes/No | Yes/No |
| 4 — deprecated userFederationProviders | Yes/No | Yes/No |
| 5 — KEYCLOAK_USER maps to password | Yes/No | Yes/No |
| 6 — duplicate realm import methods | Yes/No | Yes/No |
| 7 — hardcoded VS namespace/gateway | Yes/No | Yes/No |

## Codex Fix Spec
[Write exact before/after diffs for all confirmed issues]

## Sign-off
Verified by Gemini [date]. shellcheck: PASS/FAIL. bats: N/6 passed.
```
