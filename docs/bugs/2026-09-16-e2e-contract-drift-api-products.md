# Bug: e2e contract-drift — api-products

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-16 by k3dm-hermes
**Status:** OPEN — Hermes rule-based triage; unverified
**Run:** `1789549631-2079`, runner `m2`, tier `vcluster`, 24 passed / 33 failed / 102 total
**Runner commit:** `ec4874fe62cab1ba120729dc5d48454f7d50dcc7`

## Failing tests (1)
- `api/products.spec.ts` — should have valid price format

## Sample errors
- Error: expect(received).toBe(expected) // Object.is equality / Expected: "number" / Received: "string"

## Triage hint
the response shape differs from the test's expectation; compare the substrate image pin with the `shopping-cart-e2e-tests` image and the service's API.

## Next step
A human (or Claude) verifies the root cause, then writes the fix spec here before any code change.
