# Bug: Shopping-cart apps missing from ArgoCD — no services/ directory + wrong destination cluster

**Date:** 2026-04-26
**Severity:** High — shopping-cart workloads cannot be managed via ArgoCD
**Spec type:** bug
**Branch:** `k3d-manager-v1.2.0`
**Status:** FIXED — see commit on `k3d-manager-v1.2.0`

---

## Problem

Shopping-cart applications do not appear in the ArgoCD UI. The `services-git` ApplicationSet
watches `services/*` in k3d-manager for app definitions, but:

1. The `services/` directory did not exist — the ApplicationSet generated zero Applications.
2. The ApplicationSet template hardcoded `server: https://kubernetes.default.svc` (Hub
   cluster), but shopping-cart apps must deploy to the `ubuntu-k3s` app cluster.
3. The `platform` AppProject had no destinations allowing the `ubuntu-k3s` cluster or
   shopping-cart namespaces.

---

## Root Cause

**Missing directory:** `services/` was never created. No directories → no Applications.

**Wrong destination server:**
```yaml
# Before (wrong)
destination:
  namespace: '{{.path.basename}}'
  server: https://kubernetes.default.svc     # Hub cluster — wrong
```

**AppProject missing destinations:** `platform.yaml.tmpl` listed only Hub cluster
namespaces (secrets, cicd, identity, istio-system, default). No entry for ubuntu-k3s
or shopping-cart namespaces.

---

## Fix Applied

### 1. `services/` directory — kustomize remote references

Created one directory per shopping-cart service. Each `kustomization.yaml` references
the upstream repo's `k8s/base` directly — no manifest duplication in k3d-manager:

```
services/
  shopping-cart-order/kustomization.yaml
  shopping-cart-basket/kustomization.yaml
  shopping-cart-frontend/kustomization.yaml
  shopping-cart-product-catalog/kustomization.yaml
  shopping-cart-payment/kustomization.yaml
```

### 2. `services-git.yaml` — destination fixed to `name: ubuntu-k3s`

Using cluster name (stable) instead of IP-based server URL (changes each sandbox):
```yaml
destination:
  name: ubuntu-k3s          # registered cluster name — stable across sandbox rebuilds
  namespace: shopping-cart-apps  # default; kustomize overrides per resource
```

### 3. `platform.yaml.tmpl` — added ubuntu-k3s + shopping-cart destinations

Added entries for `shopping-cart-apps`, `shopping-cart-payment`, `shopping-cart-data`,
and `staging` targeting `ubuntu-k3s` by name. Also added `staging` on Hub cluster for
`rollout-demo-staging`.

---

## Files Changed

| File | Change |
|------|--------|
| `services/shopping-cart-*/kustomization.yaml` | Created (5 files) |
| `scripts/etc/argocd/applicationsets/services-git.yaml` | Fixed destination cluster + namespace |
| `scripts/etc/argocd/projects/platform.yaml.tmpl` | Added ubuntu-k3s + shopping-cart destinations |
