# Bug: e2e assertion — api-payments

**Branch:** `k3d-manager-v1.34.0`
**Filed:** 2026-09-16 by k3dm-hermes
**Status:** OPEN — Hermes rule-based triage; unverified
**Run:** `1789549631-2079`, runner `m2`, tier `vcluster`, 24 passed / 33 failed / 102 total
**Runner commit:** `ec4874fe62cab1ba120729dc5d48454f7d50dcc7`

## Failing tests (9)
- `api/payments.spec.ts` — should return healthy status
- `api/payments.spec.ts` — should process payment successfully with mock gateway
- `api/payments.spec.ts` — should handle idempotent payment requests
- `api/payments.spec.ts` — should reject duplicate payment for same order
- `api/payments.spec.ts` — should retrieve payment by ID
- `api/payments.spec.ts` — should retrieve payment by order ID
- `api/payments.spec.ts` — should retrieve payments by customer ID
- `api/payments.spec.ts` — should process full refund
- `api/payments.spec.ts` — should process partial refund

## Sample errors
- Error: expect(received).toBe(expected) // Object.is equality / Expected: "UP" / Received: "DOWN"
- SyntaxError: Unexpected end of JSON input

## Triage hint
a behaviour change; read the failing test.

## Next step
A human (or Claude) verifies the root cause, then writes the fix spec here before any code change.
