# Bug: e2e contract-drift — api-cart

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-16 by k3dm-hermes
**Status:** OPEN — Hermes rule-based triage; unverified
**Run:** `1789549631-2079`, runner `m2`, tier `vcluster`, 24 passed / 33 failed / 102 total
**Runner commit:** `ec4874fe62cab1ba120729dc5d48454f7d50dcc7`

## Failing tests (11)
- `api/cart.spec.ts` — should return empty cart for new user
- `api/cart.spec.ts` — should return cart with customer ID
- `api/cart.spec.ts` — should add item to cart
- `api/cart.spec.ts` — should calculate subtotal correctly
- `api/cart.spec.ts` — should update total amount
- `api/cart.spec.ts` — should add multiple different items
- `api/cart.spec.ts` — should update item quantity
- `api/cart.spec.ts` — should remove item when quantity set to 0
- `api/cart.spec.ts` — should remove item from cart
- `api/cart.spec.ts` — should clear all items from cart
- …and 1 more

## Sample errors
- Error: expect(received).toHaveProperty(path) / Expected path: "id" / Received path: []
- Error: expect(received).toBe(expected) // Object.is equality / Expected: "e2e-1789549770380-63ssd8" / Received: undefined
- TypeError: expect(received).toHaveLength(expected) / Matcher error: received value must have a length property whose value must be a number / Received has value: undefined

## Triage hint
the response shape differs from the test's expectation; compare the substrate image pin with the `shopping-cart-e2e-tests` image and the service's API.

## Next step
A human (or Claude) verifies the root cause, then writes the fix spec here before any code change.
