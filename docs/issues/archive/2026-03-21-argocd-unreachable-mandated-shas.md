# Issue: ArgoCD Failed to Fetch Mandated SHAs

**Date:** 2026-03-21
**Status:** OPEN
**Component:** `ArgoCD`, `shopping-cart-apps`

## Symptoms

When pinning ArgoCD applications to mandated commit SHAs, the server returns a `ComparisonError`:
```
Failed to load target state: failed to generate manifest for source 1 of 1: rpc error: code = Unknown desc = failed to initialize repository resources: rpc error: code = Internal desc = Failed to checkout revision <SHA>: `git fetch origin <SHA> --tags --force --prune` failed exit status 128: fatal: remote error: upload-pack: not our ref <SHA>
```

Affected SHAs:
- `shopping-cart-order`: `007d80a64749151f48be6b2e5cddf01ca428e7c3`
- `shopping-cart-product-catalog`: `f9a738119841cf89ae8b00c8ffeefd95b1dbdc2b`
- `shopping-cart-infra`: `aaa08c14e2be761a75f4c2ce63c4dbd64d3131c2`

## Root Cause

The mandated SHAs are not present in the remote repository's history or are not reachable from the branches ArgoCD is configured to track.

## Mitigation

- Reverted applications to track `HEAD` to restore GitOps sync functionality.
- Verified that `HEAD` contains most recent fixes (PostgreSQL auth, schema fixes).
