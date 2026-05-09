# Bugfix: Duplicate ldap-secrets-externalsecret.yaml in identity/ldap/kustomization.yaml

**Branch:** `fix/ldap-duplicate-externalsecret`
**Files:** `identity/ldap/kustomization.yaml`

---

## Problem

The ArgoCD `shopping-cart-identity` Application fails to sync because `kustomize build` aborts
with a duplicate resource registration error. Keycloak never deploys, blocking ArgoCD SSO.

**Root cause:** `identity/ldap/kustomization.yaml` on `main` lists `ldap-secrets-externalsecret.yaml`
twice in its `resources` list. Kustomize rejects manifests where two entries share the same
Group/Version/Kind/Namespace/Name.

---

## Reproduction

```bash
# On a cluster with ArgoCD running and shopping-cart-identity Application applied:
kubectl get app shopping-cart-identity -n cicd -o jsonpath='{.status.conditions[0].message}'
# Actual: "merging resources from 'ldap-secrets-externalsecret.yaml': may not add resource
#          with an already registered id: ExternalSecret.v1.external-secrets.io/ldap-secrets.identity"
# Expected: Application syncs and Keycloak pod reaches Running
```

---

## Fix

### Change 1 — `identity/ldap/kustomization.yaml`: remove duplicate resource entry

**Exact old block (lines 10–14):**

```yaml
resources:
- bootstrap.yaml
- ldap-secrets-externalsecret.yaml
- deployment.yaml
- ldap-secrets-externalsecret.yaml
```

**Exact new block:**

```yaml
resources:
- bootstrap.yaml
- ldap-secrets-externalsecret.yaml
- deployment.yaml
```

---

## Files Changed

| File | Change |
|------|--------|
| `identity/ldap/kustomization.yaml` | Remove duplicate `ldap-secrets-externalsecret.yaml` entry |

---

## Rules

- No other manifest changes required beyond `identity/ldap/kustomization.yaml`
- `kustomize build identity/ldap` must succeed with zero errors after the change

---

## Definition of Done

- [ ] `identity/ldap/kustomization.yaml` has exactly one `ldap-secrets-externalsecret.yaml` entry
- [ ] `kustomize build identity/ldap` exits 0 (run locally or confirm via CI)
- [ ] Committed and pushed to `fix/ldap-duplicate-externalsecret`
- [ ] No other files modified

**Commit message (exact):**
```
fix(ldap): remove duplicate ldap-secrets-externalsecret.yaml from kustomization
```

---

## What NOT to Do

- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any manifest file other than `identity/ldap/kustomization.yaml`
- Do NOT commit to `main`
