# `CPUThrottlingHigh` on `argocd-application-controller`: orphaned-resource monitoring turns Istio leader renewals into a refresh storm

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** medium. The hub's ArgoCD controller is CFS-throttled in 31% of periods (firing since 2026-10-02T10:15Z).
Throttling slows every sync and health update on the hub, including the 31 apps it manages for itself and
`ubuntu-hostinger`.
**Status:** OPEN
**Related:** `docs/bugs/2026-07-19-missing-shopping-cart-appproject.md`; the `orphanedResources` block dates from
the AppProject bootstrap (`7912adc7`).

## Evidence (hub `k3d-k3d-cluster`, namespace `cicd`, ArgoCD `v3.5.3`, 2026-10-02)

| Measure | Value |
|---|---|
| `application-controller` limits / requests | `cpu: 1` / `250m` |
| CPU now (`kubectl top`) | `546m`; 24h average `0.29` cores, 24h max of 5m rates `0.59` |
| Throttled periods, last 1h | **31%** (`istio-proxy` sidecar: 0.02%) |
| `argocd_app_reconcile_count`, last 1h | ~9,400 for 31 apps; a 180s reconciliation timeout alone gives ~620 |

Controller log, 10 minutes: 416 `Reconciliation completed`, of which **385** are four apps:
`ztunnel-ubuntu-hostinger` (102), `istio-cni-ubuntu-hostinger` (99), `istiod-ubuntu-hostinger` (94),
`istio-base-ubuntu-hostinger` (90). 395 of the refreshes are `controller refresh requested`, and 667 lines read
`Requesting app refresh caused by object update`. Those objects are istiod's leader-election ConfigMaps on
`ubuntu-hostinger` (`istio-leader`, `istio-namespace-controller-election`, `istio-status-leader`,
`istio-gateway-status-leader`, `istio-ip-autoallocate`) and the `istio-ingressgateway` HPA.

The leader ConfigMaps have no labels and no owner, and only their
`control-plane.alpha.kubernetes.io/leader` annotation changes (`renewTime`, every few seconds).

## Cause

Both AppProject templates set:

```yaml
  orphanedResources:
    warn: false
```

`warn: false` only hides the warning condition; the block's **presence** turns orphaned-resource monitoring on. In
ArgoCD v3.5.3 `controller/appcontroller.go:2642`, the application informer indexes an app under its destination
namespace only when `proj.Spec.OrphanedResources != nil`. Then every update to any **untracked** object in that
namespace refreshes the app. All four Istio apps target `istio-system`, so each leader-lease renewal refreshes all
four.

The existing `resource.customizations.ignoreResourceUpdates.ConfigMap` rule for that annotation does not help:
ArgoCD hashes, and so can skip, only resources it tracks. These ConfigMaps are untracked.

Nothing reads the orphaned-resource list: `warn` is false, and no doc, test or dashboard uses it.

## Fix

1. `scripts/etc/argocd/projects/platform.yaml.tmpl`: delete the two lines `orphanedResources:` and `warn: false`.
2. `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl`: the same.
3. Change nothing else in either file. Do not touch the CPU limit: the throttling is a symptom, and raising the limit
   would hide the storm.

## Tests (new `scripts/tests/plugins/argocd_appproject_orphaned_resources.bats`; no cluster)

1. For each of the two templates, render with `envsubst '$ARGOCD_NAMESPACE'` (`ARGOCD_NAMESPACE=cicd`), select the
   `AppProject` document with `yq`, and assert `.spec.orphanedResources` is null.
2. Assert each rendered `AppProject` still has its `sourceRepos`, `destinations` and `roles` (non-empty), so the
   deletion removed only the intended block.
3. Mutation, `cp`-restored and `cmp`-proved: add `orphanedResources: {warn: false}` back to `platform.yaml.tmpl` →
   test 1 is red.

## Rules

- `bats scripts/tests/plugins/argocd_appproject_orphaned_resources.bats` and
  `bats scripts/tests/plugins/argocd_vectordb.bats` (which reads `platform.yaml.tmpl`) are green.
- No cluster, network or git commits. Leave the changes uncommitted. Do not touch `CHANGELOG.md` or memory-bank.
- Update this doc: Status FIXED (pending rollout), plus a short Resolution section.

## Rollout (operator)

`_argocd_deploy_appproject` runs only during the full ArgoCD deploy. To apply just the projects (the same
server-side apply it uses):

```bash
for p in platform shopping-cart; do
  ARGOCD_NAMESPACE=cicd envsubst '$ARGOCD_NAMESPACE' < "scripts/etc/argocd/projects/$p.yaml.tmpl" \
    | kubectl --context k3d-k3d-cluster apply --server-side -f -
done
kubectl --context k3d-k3d-cluster -n cicd get appproject -o custom-columns='N:.metadata.name,O:.spec.orphanedResources'
```

`O` must read `<none>` for both. Within about 15 minutes the four Istio apps should reconcile about once per
180s, and `CPUThrottlingHigh` should resolve. Confirm the throttled ratio is under 25%.
