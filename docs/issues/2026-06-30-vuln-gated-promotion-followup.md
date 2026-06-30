# Issue: auto-follow disabled, but vulnerability-gated image promotion is still a follow-up

**Date:** 2026-06-30
**Related bugfix:** `docs/bugs/2026-06-30-image-updater-always-follows-latest-instead-of-vuln-gated-promotion.md`

## What was fixed

- Removed static ArgoCD Image Updater annotations from `services-git.yaml`, so
  shopping-cart apps no longer continuously adopt `:latest` digests.
- Updated `app-cve-scan.sh` text so it no longer claims automatic rollout of a
  rebuilt image.

## Current limitation

The repo now enforces the important safety property: it does **not** auto-update
shopping-cart images all the time.

However, the remaining desired behavior is not yet implemented in this task:

- consume Trivy Operator `VulnerabilityReport` objects directly
- decide promotion based on severity/CVE policy
- record the exact `from image` / `to image` / `CVE` set for the applied update

The current `app-cve-scan.sh` path still performs its own `trivy image` scan of
`:latest` and only dispatches rebuild notifications. It is no longer a rollout
path.

## Recommended follow-up

1. Add a dedicated vulnerability-gated promotion script/controller for the
   shopping-cart apps.
2. Read Trivy Operator `VulnerabilityReport` resources for the deployed image,
   not just an ad-hoc registry scan.
3. Persist structured promotion logs that include:
   - app name
   - severity
   - CVE IDs
   - previous image
   - applied image
