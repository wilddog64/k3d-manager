# Bug: `services-git` ApplicationSet generates duplicate Application names — app tier only ever reaches one cluster

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/etc/argocd/applicationsets/services-git.yaml` (ONLY)
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "services-git duplicate Application names" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/etc/argocd/applicationsets/services-git.yaml` — the whole file
  - `scripts/etc/argocd/applicationsets/data-git.yaml` — the already-correct naming pattern
    this change mirrors (`{{.name}}-data-layer`, landed in `f03df202`)
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

The app tier (frontend, basket, order, payment, product-catalog, namespace) is deployed to
`ubuntu-hostinger` only. `ubuntu-k3s` never receives it, so a fresh k3s-aws cluster comes up
with a working data layer and platform but **no applications** — the `shopping-cart-apps`
namespace stays effectively empty.

This is not a silent inference. ArgoCD reports it directly on the ApplicationSet:

```
ErrorOccurred=True:      ApplicationSet services-git contains applications with
                         duplicate name: shopping-cart-product-catalog (and 5 more)
ParametersGenerated=True: Successfully generated parameters for all Applications
ResourcesUpToDate=False:  ApplicationSet services-git contains applications with
                         duplicate name: shopping-cart-product-catalog (and 5 more)
```

Measured on the hub 2026-07-19 — every generated Application resolves to Hostinger:

```
shopping-cart-basket           -> ubuntu-hostinger
shopping-cart-frontend         -> ubuntu-hostinger
shopping-cart-namespace        -> ubuntu-hostinger
shopping-cart-order            -> ubuntu-hostinger
shopping-cart-payment          -> ubuntu-hostinger
shopping-cart-product-catalog  -> ubuntu-hostinger
```

### Root cause

The template names the Application after the **git directory** and omits the cluster:

```yaml
    metadata:
      name: '{{.path.basename}}'
```

The generator is a matrix of 6 git directories × every cluster labelled
`k3d-manager/role: app-cluster`. Both spokes carry that label:

```
cluster-ubuntu-hostinger   clusterName=ubuntu-hostinger   role=app-cluster   env=dev
cluster-ubuntu-k3s         clusterName=ubuntu-k3s         role=app-cluster   env=dev
```

So the matrix produces 12 entries that collapse onto 6 names. `destination.name` is correctly
per-cluster (`{{.name}}`), but the Application *name* is not — two entries claim
`shopping-cart-frontend`, one bound to each cluster. ArgoCD refuses to reconcile ambiguous
names, sets `ErrorOccurred=True`, and keeps only the first-generated entry. Hostinger wins;
`ubuntu-k3s` is dropped.

**`services-git.yaml` is the only cluster-scoped ApplicationSet in the repo that is not keyed
by cluster.** Every sibling already is:

| ApplicationSet | `metadata.name` template | keyed? |
|---|---|---|
| `data-git.yaml` | `{{.name}}-data-layer` | yes |
| `eso.yaml` | `{{.name}}-eso` | yes |
| `platform-helm.yaml` | `{{.name}}-platform` | yes |
| `grafana-dashboards-acg.yaml` | `{{.name}}-grafana-dashboards` | yes |
| **`services-git.yaml`** | **`{{.path.basename}}`** | **no** |

This is the same defect `f03df202` fixed for the data layer, in the one file that migration
did not reach.

---

## Fix

### Change 1 — key the Application name by cluster

**Exact old block:**

```yaml
  template:
    metadata:
      name: '{{.path.basename}}'
      labels:
        app-type: service
        discovered-from: git
```

**Exact new block:**

```yaml
  template:
    metadata:
      name: '{{.name}}-{{.path.basename}}'
      labels:
        app-type: service
        discovered-from: git
```

### Change 2 — preserve running workloads across the rename

Renaming the template causes the controller to delete the 6 existing Applications and create
12 new ones. The template sets `prune: true` + `selfHeal: true`, so deleting an Application
would cascade to its workloads and take the **live Hostinger app tier down**. Prevent that by
setting the ApplicationSet-level sync policy.

**Exact old block (the ApplicationSet's own `spec`, immediately after `goTemplateOptions`):**

```yaml
  goTemplateOptions:
    - missingkey=error
  template:
```

**Exact new block:**

```yaml
  goTemplateOptions:
    - missingkey=error
  syncPolicy:
    preserveResourcesOnDeletion: true
  template:
```

Note this is `spec.syncPolicy` on the **ApplicationSet**, a sibling of `template:` — NOT the
`syncPolicy` inside `template.spec`, which stays exactly as it is. Do not touch the template's
`automated: prune/selfHeal` block.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/applicationsets/services-git.yaml` | name keyed by cluster; `preserveResourcesOnDeletion: true` |

---

## Rules

- **Presence gate:** `grep -c "name: '{{.name}}-{{.path.basename}}'" scripts/etc/argocd/applicationsets/services-git.yaml` → **`1`**
- **Disappearance gate:** `grep -c "name: '{{.path.basename}}'" scripts/etc/argocd/applicationsets/services-git.yaml` → **`0`**
- **Presence gate:** `grep -c 'preserveResourcesOnDeletion: true' scripts/etc/argocd/applicationsets/services-git.yaml` → **`1`**
- **Unchanged gate:** `grep -c 'shopping-cart-identity' scripts/etc/argocd/applicationsets/services-git.yaml`
  must be the SAME before and after — record both numbers. The generator's
  `exclude: true` entry for the identity service must survive untouched.
- **Unchanged gate:** `grep -c 'selfHeal: true' scripts/etc/argocd/applicationsets/services-git.yaml`
  must be the SAME before and after — record both numbers.
- `python3 -c "import yaml,sys; yaml.safe_load(open('scripts/etc/argocd/applicationsets/services-git.yaml').read().replace('\${ARGOCD_NAMESPACE}','cicd').replace('\${K3D_MANAGER_BRANCH}','main'))"` — parses clean
- `./scripts/k3d-manager _agent_audit` — exit 0
- No other files touched

---

## Definition of Done

- [ ] Application name keyed by cluster
- [ ] `preserveResourcesOnDeletion: true` set at ApplicationSet level
- [ ] Template's own `syncPolicy.automated` block unchanged (gate recorded both counts)
- [ ] `shopping-cart-identity` exclusion unchanged (gate recorded both counts)
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] `_agent_audit` exit 0
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(argocd): key services-git Application names by cluster
```

---

## What NOT to Do

- Do NOT remove the `k3d-manager/role: app-cluster` label from either cluster Secret to
  "resolve" the collision. Both spokes are app clusters; the name template is what is wrong.
- Do NOT add `k3d-manager/role: app-cluster` to the hub Secret, and do NOT create a hub
  cluster Secret labelled `environment=infra` — both are blocked pending an owner decision.
- Do NOT set `selfHeal: false` or `prune: false` in the template as a way to avoid the
  rename churn — `preserveResourcesOnDeletion` is the correct mechanism.
- Do NOT change `istio-ambient.yaml`. Its `{{ .name }}-${APP_CLUSTER_NAME}` template is
  keyed but pinned to a single envsubst'd cluster — a **related and separate** defect. File
  it independently if confirmed; it is out of scope here.
- Do NOT touch the `ignoreDifferences` blocks.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the single listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (do NOT delegate)

Live application and verification. Agents do not touch the live cluster. After the commit
lands, Claude applies the rendered ApplicationSet to the hub and confirms:

- `ErrorOccurred` clears on `applicationset/services-git`
- 12 Applications exist, 6 per cluster, each `destination.name` matching its prefix
- the Hostinger app tier stayed up across the rename (pod ages not reset)

---

## Known follow-on work (out of scope — do NOT start)

Once `ubuntu-k3s` starts receiving the app tier, these are expected to surface and are
**not** part of this fix:

- `ghcr-pull-secret` must exist in `shopping-cart-apps` on `ubuntu-k3s` or images will
  `ImagePullBackOff` (see `2026-04-26-shopping-cart-imagepullbackoff-no-ghcr-pull-secret.md`).
- Keycloak issuer reachability from the k3s-aws cluster
  (see `2026-05-17-keycloak-jwt-issuer-mismatch-app-cluster.md`).
- The pre-existing `product-catalog-seed` job on `ubuntu-k3s` failing with
  `configmap "product-catalog-config-8h4dfgdf4k" not found` — present before this change,
  origin not yet established.
