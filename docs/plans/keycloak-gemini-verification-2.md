# Gemini Verification Task — Keycloak Plugin Round 2

**Branch:** `feature/infra-cluster-complete`
**Requested by:** Claude (2026-03-03)
**Status:** Verified by Gemini (2026-03-03) ✅

---

## Step 1 — Mechanical Checks

```bash
# Shellcheck
$ shellcheck scripts/plugins/keycloak.sh
# Result: PASS (empty output)

# Bats
$ PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/keycloak.bats
keycloak.bats
 ✓ deploy_keycloak --help shows usage
 ✓ deploy_keycloak skips when CLUSTER_ROLE=app
 ✓ KEYCLOAK_NAMESPACE defaults to identity
 ✓ KEYCLOAK_HELM_RELEASE defaults to keycloak
 ✓ deploy_keycloak rejects unknown option
 ✓ _keycloak_seed_vault_admin_secret function exists

6 tests, 0 failures
```

---

## Step 2 — Gemini Findings

### Issue 1 — Missing `KEYCLOAK_LDAP_USERS_DN` in envsubst whitelist
- **Confirmed:** Yes. In `scripts/plugins/keycloak.sh` (line 212), the variable is missing from the `envsubst` call, meaning the `${KEYCLOAK_LDAP_USERS_DN}` placeholder in the JSON template will not be replaced.
- **Fix Required:** Yes.

### Issue 2 — `usernameLDAPAttribute` uid vs cn
- **Confirmed:** `uid` is correct.
- **Evidence:** `scripts/etc/ldap/jenkins-users-groups.ldif` defines users with `objectClass: inetOrgPerson` and uses both `uid` and `cn`. However, `uid` is the standard attribute for the login name in this object class. The current template value `["uid"]` is correct.

### Issue 3 — static `"id": "ldap-provider"` safety
- **Confirmed:** Safe.
- **Reasoning:** `keycloak-config-cli` uses the `"id"` field to identify existing components for updates rather than recreates. Providing a stable ID ensures idempotency across multiple `deploy_keycloak` runs.

---

## Step 3 — Codex Fix Spec

### Fix 1 — P1: Add `KEYCLOAK_LDAP_USERS_DN` to envsubst whitelist
**File:** `scripts/plugins/keycloak.sh`

```bash
# Before (line 212):
   KEYCLOAK_LDAP_BIND_DN="$bind_dn" KEYCLOAK_LDAP_PASSWORD="$bind_pw" \
      envsubst '$KEYCLOAK_REALM_NAME $KEYCLOAK_REALM_DISPLAY_NAME $KEYCLOAK_LDAP_HOST $KEYCLOAK_LDAP_PORT $KEYCLOAK_LDAP_BASE_DN $KEYCLOAK_LDAP_BIND_DN $KEYCLOAK_LDAP_PASSWORD' \
      < "$KEYCLOAK_CONFIG_DIR/realm-config.json.tmpl" > "$rendered"

# After:
   KEYCLOAK_LDAP_BIND_DN="$bind_dn" KEYCLOAK_LDAP_PASSWORD="$bind_pw" \
      envsubst '$KEYCLOAK_REALM_NAME $KEYCLOAK_REALM_DISPLAY_NAME $KEYCLOAK_LDAP_HOST $KEYCLOAK_LDAP_PORT $KEYCLOAK_LDAP_BASE_DN $KEYCLOAK_LDAP_USERS_DN $KEYCLOAK_LDAP_BIND_DN $KEYCLOAK_LDAP_PASSWORD' \
      < "$KEYCLOAK_CONFIG_DIR/realm-config.json.tmpl" > "$rendered"
```

---

## Sign-off
Verified by Gemini 2026-03-03. shellcheck: **PASS**. bats: **6/6 passed**.
Findings: 1 minor fix required (envsubst whitelist). All other logic is sound.
