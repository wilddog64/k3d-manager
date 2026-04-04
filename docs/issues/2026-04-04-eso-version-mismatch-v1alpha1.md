# Issue: ESO v0.9.20 serves `v1alpha1` only — manifests require `v1`

**Date:** 2026-04-04
**File:** `bin/acg-up` line 194
**Severity:** Critical — blocks all ArgoCD data-layer syncs on fresh sandbox

## Symptom

After `make up`, ArgoCD data-layer sync fails with:

```
The Kubernetes API could not find version "v1" of external-secrets.io/ExternalSecret
for requested resource. Version "v1alpha1" of external-secrets.io/ExternalSecret
is installed on the destination cluster.
```

All app pods remain in `CrashLoopBackOff` due to missing database ExternalSecrets.

## Root Cause

`bin/acg-up` installs ESO with `_eso_version="${ESO_VERSION:-0.9.20}"` (line 194).
ESO v0.9.20 only serves `v1alpha1` and `v1beta1`. The `shopping-cart-infra` manifests
were updated in PR #23 to use `external-secrets.io/v1`, which requires ESO v0.14.0+.

## Fix

Bump the default `ESO_VERSION` in `bin/acg-up` from `0.9.20` to `0.14.0`.

Spec: `docs/plans/v1.0.3-fix-eso-version.md`
