# Issue: Argo CD marks `shopping-cart-order` and `shopping-cart-product-catalog` OutOfSync on expected ESO / generated drift

**Date:** 2026-05-26
**Repository:** `k3d-manager`
**Status:** Open

## Symptoms

The shopping-cart Argo CD apps are healthy but still show drift:

- `shopping-cart-order` is `OutOfSync / Healthy`
- `shopping-cart-product-catalog` is `OutOfSync / Healthy`
- `shopping-cart-payment` is already `Synced / Healthy`

The drift is isolated to:

- `Secret/order-service-secrets` in `shopping-cart-order`
- `ConfigMap/product-catalog-seed-script` in `shopping-cart-product-catalog`

## Root Cause

These are not runtime failures. They are expected ownership boundaries that Argo CD is still comparing as if they were ordinary Git-managed objects.

- `order-service-secrets` is ESO-managed, so its live secret data is expected to change outside Git.
- `product-catalog-seed-script` is a bootstrap artifact and should not keep the app in an OutOfSync state when the workload itself is healthy.

The current `services-git` ApplicationSet only ignores the ESO-managed `payment-db-credentials` secret. It does not yet ignore these two drift-only resources.

## Recommended Fix

Update `scripts/etc/argocd/applicationsets/services-git.yaml` so the generated shopping-cart Applications ignore the expected drift for:

- `Secret/order-service-secrets` in namespace `shopping-cart-apps`
- `ConfigMap/product-catalog-seed-script` in namespace `shopping-cart-apps`

The policy should remain narrow:

- keep syncing the service workloads
- ignore only the drift-only data objects that are expected to vary outside Git

## Verification

After the fix lands, Argo CD should report:

- `shopping-cart-order` as `Synced / Healthy`
- `shopping-cart-product-catalog` as `Synced / Healthy`

The live workload pods should remain healthy throughout.
