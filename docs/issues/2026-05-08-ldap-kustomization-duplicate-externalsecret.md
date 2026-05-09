# Issue: Duplicate ldap-secrets-externalsecret.yaml in kustomization breaks ArgoCD identity sync

**Date:** 2026-05-08
**Severity:** High — blocks Keycloak deployment, breaks ArgoCD SSO
**Repo:** shopping-cart-infra
**Branch affected:** main

---

## Symptom

`kustomize build identity/ldap` fails locally, and the ArgoCD `shopping-cart-identity` Application fails to sync with:

```
Failed to load target state: failed to generate manifest for source 1 of 1:
kustomize build failed exit status 1: Error: accumulating resources:
merging resources from 'ldap-secrets-externalsecret.yaml':
may not add resource with an already registered id:
ExternalSecret.v1.external-secrets.io/ldap-secrets.identity
```

Keycloak pod never starts. ArgoCD SSO login is unavailable.

---

## Root Cause

`identity/ldap/kustomization.yaml` on `main` lists `ldap-secrets-externalsecret.yaml` twice:

```yaml
resources:
- bootstrap.yaml
- ldap-secrets-externalsecret.yaml
- deployment.yaml
- ldap-secrets-externalsecret.yaml   # ← duplicate
```

Kustomize disallows two resources with the same Group/Version/Kind/Namespace/Name.
The ArgoCD Application (`argocd/applications/identity.yaml` in this repo) sources
`identity/ldap` at `targetRevision: HEAD`, so it inherits the broken manifest.

---

## Impact

- `shopping-cart-identity` ArgoCD Application: `Sync Status: Unknown`
- Keycloak: never deployed
- OpenLDAP: deployed but LDAP ExternalSecret stuck in sync error
- ArgoCD SSO: unavailable (depends on Keycloak)

---

## Fix

Remove the duplicate entry from `identity/ldap/kustomization.yaml`.
See `docs/bugs/2026-05-08-ldap-kustomization-duplicate-externalsecret.md`.
