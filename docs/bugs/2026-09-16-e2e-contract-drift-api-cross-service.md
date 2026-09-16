# Bug: e2e contract-drift — api-cross-service

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-16 by k3dm-hermes
**Status:** OPEN — Hermes rule-based triage; unverified
**Run:** `1789549631-2079`, runner `m2`, tier `vcluster`, 24 passed / 33 failed / 102 total
**Runner commit:** `ec4874fe62cab1ba120729dc5d48454f7d50dcc7`

## Failing tests (10)
- `api/cross-service.spec.ts` — should maintain price when adding product to cart
- `api/cross-service.spec.ts` — should preserve product details in cart
- `api/cross-service.spec.ts` — should maintain cart total in order
- `api/cross-service.spec.ts` — should transfer all cart items to order
- `api/cross-service.spec.ts` — should preserve item quantities in order
- `api/cross-service.spec.ts` — should maintain consistency through complete flow
- `api/cross-service.spec.ts` — should handle customer ID consistently across services
- `api/cross-service.spec.ts` — should handle empty cart checkout gracefully
- `api/cross-service.spec.ts` — should handle invalid product ID in cart
- `api/cross-service.spec.ts` — should maintain currency through flow

## Sample errors
- TypeError: Cannot read properties of undefined (reading '0')
- TypeError: Cannot read properties of undefined (reading 'find')
- TypeError: Cannot read properties of undefined (reading 'map')

## Triage hint
the response shape differs from the test's expectation; compare the substrate image pin with the `shopping-cart-e2e-tests` image and the service's API.

## Next step
A human (or Claude) verifies the root cause, then writes the fix spec here before any code change.
