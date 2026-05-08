# Bug: keycloak ExternalSecret files missing from shopping-cart-infra

**Branch (shopping-cart-infra):** `docs/next-improvements`
**Discovered:** 2026-05-08 during Gemini verify pass after v1.4.4-identity-sso-fixes work

---

## Problem

`identity/keycloak/kustomization.yaml` references two ExternalSecret files that were never created:
- `keycloak-secrets-externalsecret.yaml`
- `keycloak-client-secrets-externalsecret.yaml`

ArgoCD cannot sync the identity Application because kustomize fails with "no such file". The
`identity/ldap/ldap-secrets-externalsecret.yaml` exists and is correct. Only the keycloak files
are missing.

Additionally, `KEYCLOAK_ADMIN` and `KC_DB_USERNAME` were static values in the now-deleted
`secret.yaml`. The ExternalSecret only covers password fields, so these two static env vars
must move to the `keycloak-config` ConfigMap or Keycloak will fail to start.

---

## Vault KV Paths (seeded by bin/acg-up)

| Vault path | Keys |
|-----------|------|
| `secret/data/keycloak/admin` | `admin_password`, `db_password` |
| `secret/data/keycloak/clients` | `argocd_client_secret`, `order_service_client_secret`, `product_catalog_client_secret`, `grafana_client_secret` |
| `secret/data/ldap/admin` | `admin_password` (for `LDAP_BIND_CREDENTIAL`) |

---

## Changes

### Change 1 — CREATE `identity/keycloak/keycloak-secrets-externalsecret.yaml`

```yaml
---
# ExternalSecret: keycloak-secrets
# Syncs Keycloak admin password, DB password, and LDAP bind credential from Vault KV.
# Seeded by bin/acg-up at provision time.
# The keycloak Deployment mounts this Secret via envFrom secretRef: keycloak-secrets.
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: keycloak-secrets
  namespace: identity
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  labels:
    app.kubernetes.io/name: external-secret
    app.kubernetes.io/instance: keycloak-secrets
    app.kubernetes.io/component: identity-credentials
    app.kubernetes.io/part-of: shopping-cart
spec:
  refreshInterval: 24h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: keycloak-secrets
    creationPolicy: Owner
  data:
    - secretKey: KEYCLOAK_ADMIN_PASSWORD
      remoteRef:
        key: secret/data/keycloak/admin
        property: admin_password
    - secretKey: KC_DB_PASSWORD
      remoteRef:
        key: secret/data/keycloak/admin
        property: db_password
    - secretKey: LDAP_BIND_CREDENTIAL
      remoteRef:
        key: secret/data/ldap/admin
        property: admin_password
```

### Change 2 — CREATE `identity/keycloak/keycloak-client-secrets-externalsecret.yaml`

```yaml
---
# ExternalSecret: keycloak-client-secrets
# Syncs OIDC client secrets for ArgoCD, order-service, product-catalog, and Grafana from Vault KV.
# Seeded by bin/acg-up at provision time.
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: keycloak-client-secrets
  namespace: identity
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  labels:
    app.kubernetes.io/name: external-secret
    app.kubernetes.io/instance: keycloak-client-secrets
    app.kubernetes.io/component: identity-credentials
    app.kubernetes.io/part-of: shopping-cart
spec:
  refreshInterval: 24h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: keycloak-client-secrets
    creationPolicy: Owner
  data:
    - secretKey: argocd-client-secret
      remoteRef:
        key: secret/data/keycloak/clients
        property: argocd_client_secret
    - secretKey: order-service-client-secret
      remoteRef:
        key: secret/data/keycloak/clients
        property: order_service_client_secret
    - secretKey: product-catalog-client-secret
      remoteRef:
        key: secret/data/keycloak/clients
        property: product_catalog_client_secret
    - secretKey: grafana-client-secret
      remoteRef:
        key: secret/data/keycloak/clients
        property: grafana_client_secret
```

### Change 3 — PATCH `identity/keycloak/configmap.yaml`: add static env vars

`KEYCLOAK_ADMIN` and `KC_DB_USERNAME` were in the deleted `secret.yaml` as static values.
They are not secrets and belong in the ConfigMap. Add them to `keycloak-config`:

**Old** (end of the data block):
```yaml
  LDAP_UUID_ATTRIBUTE: entryUUID
  LDAP_USERNAME_ATTRIBUTE: uid
  LDAP_RDN_ATTRIBUTE: uid
  LDAP_FULL_SYNC_PERIOD: "604800"
  LDAP_CHANGED_SYNC_PERIOD: "86400"
```

**New:**
```yaml
  LDAP_UUID_ATTRIBUTE: entryUUID
  LDAP_USERNAME_ATTRIBUTE: uid
  LDAP_RDN_ATTRIBUTE: uid
  LDAP_FULL_SYNC_PERIOD: "604800"
  LDAP_CHANGED_SYNC_PERIOD: "86400"

  # Static identity values (moved from secret.yaml — not secret)
  KEYCLOAK_ADMIN: admin
  KC_DB_USERNAME: keycloak
```

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| shopping-cart-infra | `identity/keycloak/keycloak-secrets-externalsecret.yaml` | CREATE |
| shopping-cart-infra | `identity/keycloak/keycloak-client-secrets-externalsecret.yaml` | CREATE |
| shopping-cart-infra | `identity/keycloak/configmap.yaml` | add `KEYCLOAK_ADMIN` + `KC_DB_USERNAME` |

---

## Rules

- Work only on branch `docs/next-improvements` in shopping-cart-infra
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed above
- Do NOT commit to `main`

---

## Definition of Done

- [ ] `identity/keycloak/keycloak-secrets-externalsecret.yaml` exists with `keycloak/admin` and `ldap/admin` remoteRef paths
- [ ] `identity/keycloak/keycloak-client-secrets-externalsecret.yaml` exists with `keycloak/clients` remoteRef paths
- [ ] `identity/keycloak/configmap.yaml` contains `KEYCLOAK_ADMIN: admin` and `KC_DB_USERNAME: keycloak`
- [ ] `kustomize build identity/keycloak` exits 0 (no missing resource errors)
- [ ] Committed and pushed to `docs/next-improvements` on shopping-cart-infra

**Commit message — shopping-cart-infra:**
```
fix(identity): create missing keycloak ExternalSecret files; move static vars to configmap
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify `kustomization.yaml` — it already references the correct filenames
- Do NOT modify deployment.yaml or any other file
- Do NOT commit to `main`
