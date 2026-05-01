# Issue: k3d-manager tightly coupled to shopping-cart services

**Date:** 2026-04-27
**Severity:** Medium — architectural debt, no immediate functional impact
**Target release:** v1.3.0
**Status:** Open

---

## Problem

`k3d-manager` is a generic cluster infrastructure tool (Vault, LDAP, ArgoCD, ESO).
During v1.2.0 work, app-specific shopping-cart concerns were added directly to the repo:

| What was added | Where | Why it's wrong |
|---------------|-------|----------------|
| `services/shopping-cart-*/kustomization.yaml` | k3d-manager repo | App-level overlays belong in an app or infra repo, not a cluster tool |
| `scripts/plugins/shopping_cart.sh` | k3d-manager repo | Data layer bootstrap is app-specific; k3d-manager should be app-agnostic |
| `deploy_shopping_cart_data()` call in `bin/acg-up` Step 10b | k3d-manager repo | `acg-up` now hardwires shopping-cart — deploying a different app set requires modifying k3d-manager |
| `${K3D_MANAGER_BRANCH}` ApplicationSet template | k3d-manager repo | Branch variable was introduced as a workaround because `services/` is in this repo |

**Consequence:** k3d-manager now "knows" about shopping-cart. It cannot be reused for a
different project without removing shopping-cart knowledge from the repo.

---

## Root Cause

`services/` was added to k3d-manager as the fastest path to get ArgoCD ApplicationSet
discovery working during v1.2.0. The ApplicationSet git generator scans `services/*` in
whatever repo it points at — and that repo happened to be k3d-manager.

---

## Correct Architecture

`shopping-cart-infra` already exists and is the right home for all shopping-cart deployment concerns:

```
shopping-cart-infra/
  data-layer/           ← already here (PostgreSQL, Redis, RabbitMQ manifests)
  k8s-overlays/         ← should be created here
    shopping-cart-order/kustomization.yaml
    shopping-cart-basket/kustomization.yaml
    shopping-cart-frontend/kustomization.yaml
    shopping-cart-payment/kustomization.yaml
    shopping-cart-product-catalog/kustomization.yaml
    shopping-cart-namespace/kustomization.yaml
```

The ApplicationSet generator in k3d-manager would point to `shopping-cart-infra` instead
of k3d-manager itself:

```yaml
generators:
  - git:
      repoURL: https://github.com/wilddog64/shopping-cart-infra
      revision: main
      directories:
        - path: k8s-overlays/*
```

k3d-manager would expose a configurable `GITOPS_REPO_URL` / `GITOPS_REPO_BRANCH` so it
remains app-agnostic and reusable across projects.

---

## Migration Plan

### Step 1 — Move overlays to shopping-cart-infra
- Create `shopping-cart-infra/k8s-overlays/` directory
- Move all `services/shopping-cart-*/kustomization.yaml` from k3d-manager into it
- Adjust paths as needed

### Step 2 — Move data layer bootstrap
- Extract `deploy_shopping_cart_data()` out of `scripts/plugins/shopping_cart.sh`
  into a bootstrap script inside `shopping-cart-infra` (e.g. `bin/bootstrap-data-layer.sh`)
- Remove `shopping_cart.sh` plugin from k3d-manager entirely
- Remove Step 10b from `bin/acg-up`; replace with a documented manual step or
  a generic `BOOTSTRAP_SCRIPT` hook that callers can set per project

### Step 3 — Make ApplicationSet configurable
- Replace hardcoded `services/*` path and `k3d-manager` repoURL in `services-git.yaml.tmpl`
  with env vars: `GITOPS_REPO_URL`, `GITOPS_REPO_BRANCH`, `GITOPS_SERVICES_PATH`
- Remove `${K3D_MANAGER_BRANCH}` workaround from `acg-up` and template

### Step 4 — Clean up k3d-manager
- Delete `services/` directory from k3d-manager
- Delete `scripts/plugins/shopping_cart.sh`
- Remove Step 10b from `bin/acg-up`

---

## What NOT to Do

- Do NOT remove the current `services/` setup before `shopping-cart-infra` overlays
  are deployed and verified — the shopping-cart pods must remain Running throughout
- Do NOT block v1.2.0 on this — the current coupling is functional, just not clean

---

## Definition of Done

- [ ] `shopping-cart-infra/k8s-overlays/` contains all 5 service kustomizations + namespace
- [ ] `shopping-cart-infra` bootstrap script handles data layer setup
- [ ] `services-git.yaml.tmpl` uses `GITOPS_REPO_URL` / `GITOPS_REPO_BRANCH` variables
- [ ] `services/` directory removed from k3d-manager
- [ ] `scripts/plugins/shopping_cart.sh` removed from k3d-manager
- [ ] Step 10b removed from `bin/acg-up`
- [ ] `make down` → `make up` → `make sync-apps` still produces all 5 pods Running + all apps Synced
