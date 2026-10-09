# Bug: Image Updater coverage is partial

**Status:** CLOSED — doc merged to main in PR #102; no open follow-up was found. Not individually re-verified; reopen with a Recurrence section if it is seen again (2026-10-09 status sweep)
**Filed:** 2026-07-01
**Source:** /ask agent observation

## Description

The current `services-git` ApplicationSet only enables ArgoCD Image Updater annotations for `shopping-cart-basket`, `shopping-cart-order`, and `shopping-cart-product-catalog`. `frontend` and `payment` are not in that managed set yet, so they still rely on regular GitOps behavior only.
