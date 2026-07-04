# Bug: Hostinger app-cluster ArgoCD apps remain OutOfSync on expected controller drift and stale tracking ownership

**Branch:** `k3d-manager-v1.12.0`
**Files:**
- `scripts/etc/argocd/applicationsets/data-git.yaml` (edit)
- `scripts/lib/providers/k3s-hostinger.sh` (edit)
- `scripts/tests/lib/provider_contract.bats` (edit)
- `scripts/tests/plugins/argocd_app_cluster_generator.bats` (edit)

---

## Problem

On live Hostinger (`ubuntu-hostinger`) two ArgoCD drift issues remained after
the Grafana/Prometheus recovery:

- `data-layer` -> all seven StatefulSets `OutOfSync / Healthy`
- `shopping-cart-product-catalog` and `ubuntu-hostinger-platform` temporarily
  fought over the same `product-catalog` resources during Hostinger refresh

## Root Cause

Two separate drift classes:

1. Kubernetes now defaults
   `.spec.persistentVolumeClaimRetentionPolicy` on StatefulSets, but
   the live `data-git` ApplicationSet on the hub still carries the older,
   incomplete ignore block. Hostinger refresh did not reapply that ApplicationSet,
   so `data-layer` stayed permanently `OutOfSync` even though the repo already had
   the broader `volumeClaimTemplates[]` ignores and now also needs the new
   retention-policy ignore.
2. During the Hostinger app-cluster cutover, the live `product-catalog`
   resource set retained stale `argocd.argoproj.io/tracking-id` annotations for
   `ubuntu-hostinger-platform`, so the platform app continued to claim those
   resources and both apps stayed `OutOfSync`.

## Fix

1. Extend `data-git` StatefulSet `ignoreDifferences` to cover
   `.spec.persistentVolumeClaimRetentionPolicy`.
2. Add a Hostinger refresh self-heal that reapplies the hub `data-git`
   ApplicationSet from the current repo before health checks, so the live
   `data-layer` Application picks up the updated ignore block.
3. Add a Hostinger refresh self-heal that strips stale
   `ubuntu-hostinger-platform` tracking annotations from the `product-catalog`
   resource set and hard-refreshes both affected ArgoCD apps.

## Definition of Done

- [ ] `data-layer` no longer drifts on PVC-retention defaults
- [ ] Hostinger refresh self-heals stale platform ownership on product-catalog
- [ ] Hostinger refresh reapplies `data-git` so the live ApplicationSet does not lag repo fixes
- [ ] Tests updated and passing
