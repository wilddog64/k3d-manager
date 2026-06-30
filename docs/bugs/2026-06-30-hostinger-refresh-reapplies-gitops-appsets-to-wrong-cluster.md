# Bug: Hostinger refresh reapplies `services-git` to the wrong cluster, leaving stale Image Updater annotations on the hub

**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

## Problem

The repo removed shopping-cart ArgoCD Image Updater annotations from
`scripts/etc/argocd/applicationsets/services-git.yaml`, but the live hub
`ApplicationSet/services-git` still retained the old annotation block:

- `argocd-image-updater.argoproj.io/image-list`
- `argocd-image-updater.argoproj.io/app.update-strategy`
- `argocd-image-updater.argoproj.io/write-back-method`

As a result, hub ArgoCD kept regenerating watched shopping-cart applications and
Image Updater kept writing image changes every cycle:

- `images_considered=3`
- `images_updated>0`
- repeated `WARN Flapping`

The root cause is in Hostinger refresh. `_hostinger_reapply_gitops_applicationsets`
rendered the right `ApplicationSet` YAML, but applied it through plain
`_kubectl`, which is not guaranteed to target the hub ArgoCD context. After a
reboot/refresh, that allows the hub `services-git` object to remain stale even
though the repo template is already fixed.

## Fix

Update `_hostinger_reapply_gitops_applicationsets` in
`scripts/lib/providers/k3s-hostinger.sh` so it:

1. resolves the hub kubectl command via `_argocd_hub_kubectl_cmd`
2. applies `data-git.yaml`, `services-git.yaml`, and `platform-helm.yaml`
   explicitly to the hub context
3. keeps rendering the current branch via `K3D_MANAGER_BRANCH` and the active
   app-cluster name via `APP_CLUSTER_NAME`

Add a provider contract regression test proving the reapply path now executes as:

```text
kubectl --context k3d-k3d-cluster apply -f -
```

for all three ApplicationSets.

## Files

- `scripts/lib/providers/k3s-hostinger.sh` (edit)
- `scripts/tests/lib/provider_contract.bats` (edit)

## Acceptance

- Hostinger refresh reapplies the GitOps ApplicationSets to the hub ArgoCD
  cluster, not whichever context happens to be current.
- The provider contract test proves the reapply path uses
  `--context k3d-k3d-cluster`.
- After refresh, the hub `ApplicationSet/services-git` can converge to the
  repo version without the stale Image Updater annotation block.
