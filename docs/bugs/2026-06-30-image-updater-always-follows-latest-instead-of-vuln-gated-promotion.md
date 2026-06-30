# Bug: shopping-cart apps continuously follow `:latest` instead of waiting for vulnerability-driven promotion

**Branch:** `k3d-manager-v1.12.0`
**Files:**
- `scripts/etc/argocd/applicationsets/services-git.yaml` (edit)
- `scripts/etc/argocd/platform-ops/app-cve-scan.sh` (edit)
- `scripts/tests/plugins/argocd_image_updater_annotations.bats` (edit)

## Problem

The `services-git` ApplicationSet currently stamps ArgoCD Image Updater
annotations onto `shopping-cart-basket`, `shopping-cart-order`, and
`shopping-cart-product-catalog`:

- `argocd-image-updater.argoproj.io/image-list`
- `argocd-image-updater.argoproj.io/app.update-strategy: digest`
- `argocd-image-updater.argoproj.io/write-back-method: argocd`

That causes the shopping-cart apps to continuously chase `:latest` digests.
This behavior is incompatible with the intended policy:

- detect vulnerabilities via Trivy / CVE scanning
- rebuild a candidate image only when a severe vulnerability is found
- promote the replacement image in a controlled step instead of every registry
  change

## Root Cause

The Image Updater annotations are statically baked into the generated
ApplicationSet template, so every watched app is always enrolled in digest
tracking. The companion CVE scan script also still claims that Image Updater
will automatically adopt the next rebuilt image.

## Fix

1. Remove the static Image Updater annotations from `services-git.yaml` so
   shopping-cart apps are no longer continuously updated from registry drift.
2. Update `app-cve-scan.sh` comments/logging so it reflects the new behavior:
   scan and trigger rebuild/notification, but do not claim automatic rollout.
3. Replace the old annotation-presence test with a source-level assertion that
   the shopping-cart ApplicationSet no longer carries ArgoCD Image Updater
   annotations.

## Definition of Done

- [ ] shopping-cart apps are no longer statically enrolled in ArgoCD Image Updater
- [ ] CVE scan script text no longer claims automatic `:latest` adoption
- [ ] BATS coverage proves the annotations are absent
- [ ] No unrelated ArgoCD app generator behavior changes
