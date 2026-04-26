# Bug: Shopping-cart apps missing from ArgoCD — no services/ directory + wrong destination cluster

**Date:** 2026-04-26
**Severity:** High — shopping-cart workloads cannot be managed via ArgoCD
**Spec type:** bug
**Branch:** `k3d-manager-v1.2.0`

---

## Problem

Shopping-cart applications do not appear in the ArgoCD UI. The `services-git` ApplicationSet
watches `services/*` in k3d-manager for app definitions, but:

1. The `services/` directory does not exist in the repo — the ApplicationSet generates zero applications.
2. The ApplicationSet template hardcodes `server: https://kubernetes.default.svc` (the Hub
   cluster), but shopping-cart apps must deploy to the `ubuntu-k3s` app cluster.

---

## Root Cause

**Missing directory:**
`services/` was never created. The `services-git` ApplicationSet (applied during `deploy_argocd`)
uses a git directory generator scanning `services/*` in the k3d-manager repo. No directories →
no Applications generated.

**Wrong destination:**
```yaml
# Current (wrong)
destination:
  namespace: '{{.path.basename}}'
  server: https://kubernetes.default.svc     # Hub cluster
```

Should target the registered app cluster secret name instead:
```yaml
# Correct
destination:
  namespace: '{{.path.basename}}'
  server: '{{.clusterServer}}'               # from cluster generator or label
```

Or use the registered cluster name `ubuntu-k3s` via a `clusterDecisionResource` or
hardcoded as the registered cluster server URL from `argocd cluster list`.

---

## Fix

### Phase 1 — Create `services/` directory structure

Create one subdirectory per shopping-cart service. Each directory must contain either:
- A `kustomization.yaml` pointing at the service's GitHub repo (preferred — keeps app source in its own repo)
- Or raw manifests

Minimum structure:
```
services/
  shopping-cart-order/
    kustomization.yaml       # or app.yaml / Chart.yaml
  shopping-cart-product-catalog/
    kustomization.yaml
  shopping-cart-basket/
    kustomization.yaml
  shopping-cart-frontend/
    kustomization.yaml
  shopping-cart-payment/
    kustomization.yaml
```

Each `kustomization.yaml` references the upstream repo:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-order//k8s?ref=main
```

### Phase 2 — Fix `services-git` ApplicationSet destination

The ApplicationSet must target `ubuntu-k3s`, not the Hub cluster. Two options:

**Option A — hardcode the registered cluster server URL** (simplest):
Add a cluster generator or use the registered cluster secret name. The ApplicationSet
should use a `clusters` generator filtered by label, or reference the
`cluster-ubuntu-k3s` secret name directly:

```yaml
spec:
  generators:
    - matrix:
        generators:
          - git:
              repoURL: https://github.com/wilddog64/k3d-manager
              revision: HEAD
              directories:
                - path: services/*
          - clusters:
              selector:
                matchLabels:
                  argocd.argoproj.io/secret-type: cluster
                  environment: app
```

**Option B — pass cluster server from a list generator** (more flexible):
Use a `list` generator with the ubuntu-k3s server URL as a parameter.

The `services-git` ApplicationSet template (`scripts/etc/argocd/applicationsets/services-git.yaml.tmpl`
or equivalent) must be updated so destination server resolves to `ubuntu-k3s`.

### Phase 3 — Add `environment: app` label to cluster secret

Label the `cluster-ubuntu-k3s` secret so the ApplicationSet cluster generator can select it:
```bash
kubectl label secret cluster-ubuntu-k3s -n cicd --context k3d-k3d-cluster \
  environment=app --overwrite
```

Add this label to the `register_app_cluster` function in `scripts/plugins/argocd.sh`
so it persists across rebuilds.

---

## Files to Change

| File | Change |
|------|--------|
| `services/shopping-cart-*/kustomization.yaml` | Create (5 files, one per service) |
| ApplicationSet template for `services-git` | Fix destination to target ubuntu-k3s via cluster generator |
| `scripts/plugins/argocd.sh` `register_app_cluster` | Add `environment=app` label to cluster secret |

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
- `git pull origin k3d-manager-v1.2.0`
- Check current ApplicationSet: `kubectl get applicationset services-git -n cicd --context k3d-k3d-cluster -o yaml`
- Check registered cluster server URL: `kubectl get secret cluster-ubuntu-k3s -n cicd --context k3d-k3d-cluster -o jsonpath='{.data.server}' | base64 -d`
- Branch: all work on `k3d-manager-v1.2.0`

---

## Definition of Done

- [ ] `services/` directory exists with at least one shopping-cart service subdirectory
- [ ] `services-git` ApplicationSet generates Applications targeting `ubuntu-k3s`
- [ ] At least one shopping-cart Application appears in ArgoCD UI targeting the app cluster
- [ ] `register_app_cluster` labels the cluster secret with `environment=app`
- [ ] shellcheck passes on any modified `.sh` files
- [ ] Committed on `k3d-manager-v1.2.0` with message:
      `fix(argocd): create services/ directory structure; fix services-git destination to target ubuntu-k3s`
- [ ] Pushed to origin and SHA reported
- [ ] `memory-bank/activeContext.md` updated with commit SHA

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.2.0`
- Do NOT deploy shopping-cart services to the Hub cluster (k3d-k3d-cluster)
