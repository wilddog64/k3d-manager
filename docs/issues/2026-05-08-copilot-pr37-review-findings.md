# Copilot PR #37 Review Findings

**PR:** #37 — fix(identity): wire Keycloak/LDAP ExternalSecrets + identity ArgoCD app
**Date:** 2026-05-08
**Findings:** 5

---

## Finding 1 — CRITICAL: postgres.yaml reads KC_DB_USERNAME from deleted Secret

**File:** `identity/keycloak/postgres.yaml` line 48
**Flagged by:** Copilot comment #3211239615

**Problem:**
`POSTGRES_USER` used `secretKeyRef: keycloak-secrets: KC_DB_USERNAME`, but `KC_DB_USERNAME`
was moved to `keycloak-config` ConfigMap. The `keycloak-secrets` ExternalSecret no longer
provides that key. Postgres pod would fail to start with a missing Secret key error.

**Fix:**
```yaml
# Before
- name: POSTGRES_USER
  valueFrom:
    secretKeyRef:
      name: keycloak-secrets
      key: KC_DB_USERNAME

# After
- name: POSTGRES_USER
  valueFrom:
    configMapKeyRef:
      name: keycloak-config
      key: KC_DB_USERNAME
```

**Root cause:** When moving static env vars from `secret.yaml` to ConfigMap, the deployment
that consumed them via `secretKeyRef` was not updated to match.

**Process note:** When migrating a Secret key to ConfigMap, grep all YAML for
`secretKeyRef.*<key-name>` before committing.

---

## Finding 2 — ExternalSecret target missing template labels (keycloak-secrets)

**File:** `identity/keycloak/keycloak-secrets-externalsecret.yaml` line 25
**Flagged by:** Copilot comment #3211239653

**Problem:** `spec.target` had no `template` block, so the generated Secret would lack
`app.kubernetes.io/*` labels used elsewhere for ESO-managed Secrets.

**Fix:** Added `target.template.type: Opaque` + `metadata.labels` mirroring the ExternalSecret's own labels.

---

## Finding 3 — ExternalSecret target missing template labels (keycloak-client-secrets)

**File:** `identity/keycloak/keycloak-client-secrets-externalsecret.yaml` line 24
**Flagged by:** Copilot comment #3211239675

Same as Finding 2 — same fix applied.

---

## Finding 4 — ExternalSecret target missing template labels (ldap-secrets)

**File:** `identity/ldap/kustomization.yaml` line 13 (flagged `ldap-secrets-externalsecret.yaml`)
**Flagged by:** Copilot comment #3211239698

Same pattern as Findings 2–3. Added `target.template` block to `ldap-secrets-externalsecret.yaml`.

**Root cause:** ExternalSecret spec template was written without `target.template`, which is
an optional but recommended block for label propagation to generated Secrets.

**Process note:** New ExternalSecret files must include `spec.target.template.type: Opaque`
and `metadata.labels` matching the ExternalSecret's own labels. Add this to the spec template.

---

## Finding 5 — Retrospective self-references its own PR as "merged"

**File:** `docs/retro/2026-05-08-pr36-keycloak-eso-retrospective.md` line 4
**Flagged by:** Copilot comment #3211239721

**Problem:** The doc stated `PR #36 — merged to main (SHA)` but was being committed in PR #37.
Copilot read this as a self-referential claim about the current PR. The SHA was correct (PR #36
was already merged), but the wording was ambiguous.

**Fix:** Added `(retro doc added in PR #37)` parenthetical to make the timeline explicit.
