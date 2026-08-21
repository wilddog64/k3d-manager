# Bug: product-catalog-secrets unprovisioned on fresh cluster — no ExternalSecret

**Date:** 2026-05-24
**Repo:** `shopping-cart-product-catalog`
**Branch:** `docs/next-improvements`
**Copilot finding:** PR #27, thread `PRRT_kwDORUajJs6EZroS` (resolved — addressed here)

---

## Problem

After PR #27 removed `secret.yaml` from `k8s/base/kustomization.yaml`, the
`product-catalog-secrets` Secret is no longer created on a fresh cluster.
No ExternalSecret exists to provision it. The Deployment, seed job, and fts-index
job all reference it via `envFrom.secretRef` → pods fail with `CreateContainerConfigError`.

**Why the right fix is ExternalSecret (not adding secret.yaml back):**
Adding `secret.yaml` back reintroduces the perpetual ESO-ArgoCD OutOfSync loop:
ArgoCD applies CHANGE_ME → ESO overwrites with Vault values → ArgoCD sees diff → loop.
An ExternalSecret in the base manifest provisions the real secret directly from Vault,
with no placeholder conflict.

---

## Fix

### Change 1 — create `k8s/base/externalsecret.yaml`

Create this file:

```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: product-catalog-secrets
  namespace: shopping-cart-apps
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  labels:
    app.kubernetes.io/name: external-secret
    app.kubernetes.io/instance: product-catalog-secrets
    app.kubernetes.io/component: credentials
    app.kubernetes.io/part-of: shopping-cart
spec:
  refreshInterval: 24h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: product-catalog-secrets
    creationPolicy: Owner
  data:
    - secretKey: DB_USERNAME
      remoteRef:
        key: secret/data/postgres/products
        property: username
    - secretKey: DB_PASSWORD
      remoteRef:
        key: secret/data/postgres/products
        property: password
    - secretKey: RABBITMQ_USERNAME
      remoteRef:
        key: secret/data/rabbitmq/default
        property: username
    - secretKey: RABBITMQ_PASSWORD
      remoteRef:
        key: secret/data/rabbitmq/default
        property: password
```

### Change 2 — `k8s/base/kustomization.yaml`: add `externalsecret.yaml` to resources

**Exact old resources block:**

```yaml
resources:
- serviceaccount.yaml
- deployment.yaml
- service.yaml
- seed-job-configmap.yaml
- seed-job.yaml
- fts-index-job.yaml
```

**Exact new resources block:**

```yaml
resources:
- serviceaccount.yaml
- externalsecret.yaml
- deployment.yaml
- service.yaml
- seed-job-configmap.yaml
- seed-job.yaml
- fts-index-job.yaml
```

---

## Files Changed

| File | Change |
|------|--------|
| `k8s/base/externalsecret.yaml` | Create — ExternalSecret provisioning `product-catalog-secrets` from Vault |
| `k8s/base/kustomization.yaml` | Add `- externalsecret.yaml` to resources list |

---

## Rules

- `kubectl kustomize k8s/base/` must produce zero warnings after change
- No other files touched

---

## Definition of Done

- [ ] `k8s/base/externalsecret.yaml` created with exact content above
- [ ] `k8s/base/kustomization.yaml` updated — `- externalsecret.yaml` added to resources
- [ ] `kubectl kustomize k8s/base/` produces no warnings
- [ ] Committed with message: `fix(k8s): add ExternalSecret for product-catalog-secrets — provision from Vault on fresh cluster`
- [ ] Pushed to `origin docs/next-improvements`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(k8s): add ExternalSecret for product-catalog-secrets — provision from Vault on fresh cluster
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT add `secret.yaml` back to resources — that reintroduces the OutOfSync loop
- Do NOT modify any file other than the two listed above
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT use `creationPolicy: Merge` — use `Owner` so ESO fully manages the secret lifecycle
