# Bug: kustomize `commonLabels` deprecation warning in product-catalog

**Date:** 2026-05-24
**File:** `shopping-cart-product-catalog/k8s/base/kustomization.yaml`
**Branch:** `docs/next-improvements` (shopping-cart-product-catalog)

---

## Problem

`kubectl kustomize` (invoked from `bin/acg-up` Step 11b) prints:

```
Warning: 'commonLabels' is deprecated. Please use 'labels' instead.
Run 'kustomize edit fix' to update your Kustomization automatically.
```

**Root cause:** `k8s/base/kustomization.yaml` uses the deprecated `commonLabels` field.
The equivalent modern syntax is a `labels` entry with `includeSelectors: true`.

---

## Fix

### Change 1 — `k8s/base/kustomization.yaml`: migrate `commonLabels` to `labels`

**Exact old block (lines 10–34):**

```yaml
labels:
- pairs:
    app.kubernetes.io/managed-by: kustomize
  includeSelectors: false

...

commonLabels:
  app.kubernetes.io/name: product-catalog
  app.kubernetes.io/part-of: shopping-cart
```

**Exact new block (merge into existing `labels` list, remove `commonLabels`):**

```yaml
labels:
- pairs:
    app.kubernetes.io/managed-by: kustomize
  includeSelectors: false
- pairs:
    app.kubernetes.io/name: product-catalog
    app.kubernetes.io/part-of: shopping-cart
  includeSelectors: true
```

Full file after change:

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

metadata:
  name: product-catalog

namespace: shopping-cart-apps

labels:
- pairs:
    app.kubernetes.io/managed-by: kustomize
  includeSelectors: false
- pairs:
    app.kubernetes.io/name: product-catalog
    app.kubernetes.io/part-of: shopping-cart
  includeSelectors: true

resources:
- serviceaccount.yaml
- secret.yaml
- deployment.yaml
- service.yaml
- seed-job-configmap.yaml
- seed-job.yaml
- fts-index-job.yaml

configMapGenerator:
- name: product-catalog-config
  options:
    labels:
      app.kubernetes.io/component: backend
  envs:
  - configmap.env

images:
  - name: shopping-cart-product-catalog
    newName: ghcr.io/wilddog64/shopping-cart-product-catalog
    newTag: sha-28955c89245d82111f2e0801723b49fe32cee730
```

---

## Files Changed

| File | Change |
|------|--------|
| `k8s/base/kustomization.yaml` | Replace `commonLabels` with second `labels` entry (`includeSelectors: true`) |

---

## Rules

- `kubectl kustomize k8s/base/` must produce zero warnings
- No other files touched

---

## Definition of Done

- [ ] `k8s/base/kustomization.yaml` updated — `commonLabels` removed, merged into `labels`
- [ ] `kubectl kustomize k8s/base/` produces no deprecation warning
- [ ] Committed with message: `fix(kustomize): migrate commonLabels to labels — deprecation warning`
- [ ] Pushed to `origin docs/next-improvements`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(kustomize): migrate commonLabels to labels — deprecation warning
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `k8s/base/kustomization.yaml`
- Do NOT commit to `main` — work on `docs/next-improvements`
