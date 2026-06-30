# Bug: Hostinger refresh leaves `services-git` and `platform-helm` stale, so product-catalog and platform stay OutOfSync

**Branch:** `k3d-manager-v1.12.0`
**Files:**
- `scripts/lib/providers/k3s-hostinger.sh` (edit)
- `scripts/tests/lib/provider_contract.bats` (edit)

## Problem

After `make refresh CLUSTER_PROVIDER=k3s-hostinger`, the live app cluster can
still show:

- `cicd/shopping-cart-product-catalog` -> `OutOfSync / Progressing`
- `cicd/ubuntu-hostinger-platform` -> `OutOfSync / Healthy`

even though the repo already contains the code-level fixes for:

- product-catalog Image Updater flapping (`services-git` `jqPathExpressions` +
  local kustomize `images:` anchor)
- stale platform tracking-id cleanup on product-catalog resources

## Root Cause

`_provider_k3s_hostinger_refresh_cluster` only reapplies `data-git.yaml` during
refresh. It does **not** reapply the other authoritative ApplicationSets that
generate the drifting applications:

- `services-git.yaml`
- `platform-helm.yaml`

That leaves the live hub ArgoCD control plane free to keep using stale,
previously-rendered ApplicationSets, including old branch revisions such as
`feat/v1.8.0-acg-absorb-phase2-agy`. As a result:

1. `shopping-cart-product-catalog` keeps the old generated spec and continues to
   flap or drift even though the repo fix exists.
2. `ubuntu-hostinger-platform` can continue claiming stale product-catalog
   resources until the stale generator is refreshed from the current branch.

## Fix

1. Replace the narrow `data-git` refresh helper with a generic Hostinger GitOps
   ApplicationSet reapply helper.
2. During Hostinger refresh, reapply these three ApplicationSets from the
   current branch before the stale tracking-id cleanup:
   - `data-git.yaml`
   - `services-git.yaml`
   - `platform-helm.yaml`
3. Keep the existing stale tracking-id cleanup and hard-refresh of the two
   affected Applications after the reapply.

## Definition of Done

- [ ] Hostinger refresh reapplies `data-git`, `services-git`, and `platform-helm`
- [ ] Product-catalog and platform apps consume current-branch appset templates
- [ ] Provider contract coverage proves all three appsets are rendered/applied
- [ ] No unrelated provider behavior changes
