# Gemini Verification Task — Keycloak Fixes Round 2 (v0.5.0)

**Branch:** `feature/infra-cluster-complete`
**Requested by:** Claude (2026-03-01)
**Status:** Pending Gemini verification

---

## Context

Codex applied all 7 fixes from `docs/plans/keycloak-codex-fixes.md`.
Claude reviewed the result and found one confirmed new bug plus two items
needing sanity-check. Gemini must verify all three before PR opens.

---

## Step 1 — Mechanical Checks

```bash
shellcheck scripts/plugins/keycloak.sh
PATH="/opt/homebrew/bin:$PATH" bats scripts/tests/plugins/keycloak.bats
```

Report exact output of both. If either fails, write Codex fix spec.

---

## Step 2 — Confirm Bug: Missing `KEYCLOAK_LDAP_USERS_DN` in envsubst whitelist

**File:** `scripts/plugins/keycloak.sh` — `_keycloak_apply_realm_configmap` function

**Issue:** The envsubst whitelist on line 212 is:
```bash
envsubst '$KEYCLOAK_REALM_NAME $KEYCLOAK_REALM_DISPLAY_NAME $KEYCLOAK_LDAP_HOST \
  $KEYCLOAK_LDAP_PORT $KEYCLOAK_LDAP_BASE_DN $KEYCLOAK_LDAP_BIND_DN $KEYCLOAK_LDAP_PASSWORD'
```

But `scripts/etc/keycloak/realm-config.json.tmpl` line 22 contains:
```json
"usersDn": ["${KEYCLOAK_LDAP_USERS_DN}"],
```

`KEYCLOAK_LDAP_USERS_DN` is **not in the whitelist** — envsubst will leave the
literal string `${KEYCLOAK_LDAP_USERS_DN}` in the rendered ConfigMap. Keycloak
will send this string to the LDAP server as the users search base, causing
federation to fail silently.

**Verify:** Read line 212 of `keycloak.sh` and line 22 of `realm-config.json.tmpl`.
Confirm `KEYCLOAK_LDAP_USERS_DN` is absent from the whitelist but present in the template.

**Fix for Codex (if confirmed):**
```bash
# Before:
   KEYCLOAK_LDAP_BIND_DN="$bind_dn" KEYCLOAK_LDAP_PASSWORD="$bind_pw" \
      envsubst '$KEYCLOAK_REALM_NAME $KEYCLOAK_REALM_DISPLAY_NAME $KEYCLOAK_LDAP_HOST $KEYCLOAK_LDAP_PORT $KEYCLOAK_LDAP_BASE_DN $KEYCLOAK_LDAP_BIND_DN $KEYCLOAK_LDAP_PASSWORD' \

# After:
   KEYCLOAK_LDAP_BIND_DN="$bind_dn" KEYCLOAK_LDAP_PASSWORD="$bind_pw" \
      envsubst '$KEYCLOAK_REALM_NAME $KEYCLOAK_REALM_DISPLAY_NAME $KEYCLOAK_LDAP_HOST $KEYCLOAK_LDAP_PORT $KEYCLOAK_LDAP_BASE_DN $KEYCLOAK_LDAP_USERS_DN $KEYCLOAK_LDAP_BIND_DN $KEYCLOAK_LDAP_PASSWORD' \
```

---

## Step 3 — Sanity Check: `usernameLDAPAttribute` uid vs cn

**File:** `scripts/etc/keycloak/realm-config.json.tmpl` lines 24-25

**Issue:** The template uses:
```json
"usernameLDAPAttribute": ["uid"],
"rdnLDAPAttribute": ["uid"],
```

The ArgoCD Dex LDAP connector in `scripts/etc/argocd/vars.sh` uses `cn` as the
username attribute for the same OpenLDAP deployment:
```bash
ARGOCD_LDAP_USER_SEARCH_FILTER  # searches by cn
```
And `scripts/etc/argocd/values.yaml.tmpl` has `username: cn`.

If OpenLDAP users have `cn` as their RDN (as `inetOrgPerson` entries typically do
in this project), then `uid` will fail to match any users.

**Verify:** Check `scripts/etc/ldap/` or LDIF bootstrap files to confirm whether
users are keyed by `cn` or `uid`. Then confirm whether the template should use
`cn` instead of `uid`.

**If `cn` is correct — Codex fix:**
```json
# Before:
"usernameLDAPAttribute": ["uid"],
"rdnLDAPAttribute": ["uid"],
"userObjectClasses": ["inetOrgPerson"],

# After:
"usernameLDAPAttribute": ["cn"],
"rdnLDAPAttribute": ["cn"],
"userObjectClasses": ["inetOrgPerson, organizationalPerson"],
```

---

## Step 4 — Sanity Check: Static `id` field in components block

**File:** `scripts/etc/keycloak/realm-config.json.tmpl` line 10

**Issue:** The component has:
```json
"id": "ldap-provider",
```

Static string IDs (non-UUID) are supported by `keycloak-config-cli` for
idempotent imports — it treats the `id` as the idempotency key. However, if
Keycloak auto-generates UUIDs for new providers, a re-import with this static
`id` may create a duplicate instead of updating.

**Verify:** Check the `keycloak-config-cli` documentation or known behaviour —
is specifying a static `id` safe for idempotent re-imports, or should the `id`
field be removed and let Keycloak auto-assign?

**If `id` should be removed — Codex fix:**
```json
# Remove the "id" line entirely:
{
  "providerId": "ldap",
  "name": "ldap",
  "config": { ... }
}
```

---

## Step 5 — Sign-off

Update this file with:

```
## Gemini Findings

| Check | Result |
|---|---|
| shellcheck | PASS / FAIL |
| bats | N/6 passed |
| Bug: missing KEYCLOAK_LDAP_USERS_DN | Confirmed / Denied |
| Sanity: uid vs cn | uid correct / cn correct / needs change |
| Sanity: static id field | Safe / Remove |

## Codex Fix Spec
[Exact diffs for any confirmed issues]

## Sign-off
Verified by Gemini [date].
```
