# Bug: `make status` still reports empty Image Updater "Watching" after static enrollment was removed

**Branch:** `k3d-manager-v1.12.0`
**Files:**
- `bin/cluster-status` (edit)
- `scripts/tests/bin/cluster_status_image_updater.bats` (edit)

## Problem

`bin/cluster-status` still renders the ArgoCD Image Updater section as:

```text
Watching:
  (no applications carry an image-list annotation)
```

That output is technically true, but operationally misleading now that the
shopping-cart apps are no longer statically enrolled in ArgoCD Image Updater.
Operators read it as "something is missing" even though the repo intentionally
removed those annotations.

At the same time, the same status block may still show historical controller
activity such as:

```text
Last cycle: applications=0 images_considered=0 images_skipped=0 images_updated=0 errors=0
WARN Flapping: 13 recent cycles wrote an update — an app may not be converging
```

So the status output mixes an old Image Updater mental model ("watching apps via
`image-list` annotations") with the new controller model (CVE-gated patching).

## Root Cause

The status implementation in `bin/cluster-status` still discovers "watched"
apps only by reading:

- `metadata.annotations.argocd-image-updater.argoproj.io/image-list`

But `services-git.yaml` intentionally no longer stamps those annotations onto
the shopping-cart Applications. The repo now uses `app-cve-scan.sh` to patch
ArgoCD Applications directly when a promotion decision is made, so the "Watching"
section no longer reflects the active control plane.

## Fix

Update the Image Updater status section so it reflects the current architecture:

1. Keep the deployment readiness and recent log summary.
2. Replace the old `Watching:` block with an explicit mode-aware summary.
3. When no `image-list` annotations exist, print a message like:

```text
Mode:
  CVE-gated promotion controller active; no applications are statically enrolled via image-list annotations
```

4. If the repo later reintroduces annotation-driven enrollment for some apps,
   show both:
   - the mode summary
   - the concrete annotation-backed watch list
5. Suppress or reword the flapping warning when:
   - `applications=0`
   - `images_considered=0`
   - `images_updated=0`

   In that case, historical log residue should not imply current controller
   instability.

## Definition of Done

- [ ] `bin/cluster-status` no longer implies missing configuration when no
      `image-list` annotations are present by design
- [ ] the status output clearly states that shopping-cart promotion is now
      CVE-gated rather than annotation-driven
- [ ] stale flapping warnings are not shown for an idle controller with
      `applications=0`
- [ ] BATS coverage proves the new status text and idle-controller behavior
