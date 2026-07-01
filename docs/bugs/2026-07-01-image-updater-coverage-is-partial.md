# Bug: Image Updater coverage is partial

**Filed:** 2026-07-01
**Source:** /ask agent observation

## Description

The current `services-git` ApplicationSet only enables ArgoCD Image Updater annotations for `shopping-cart-basket`, `shopping-cart-order`, and `shopping-cart-product-catalog`. `frontend` and `payment` are not in that managed set yet, so they still rely on regular GitOps behavior only.
