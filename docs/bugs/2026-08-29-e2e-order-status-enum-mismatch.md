# E2E test fix: orders status tests use a status value the service doesn't have

**Repo:** `shopping-cart-e2e-tests` (spec-not-direct → Codex, branch + PR, then rebuild
the `:latest` / SHA image the Tier-1 gate pulls).

## Problem

Two `tests/api/orders.spec.ts` tests fail against the deployed order service (image
`sha-56033880` = commit `5603388`, the Go rewrite):

- `orders.spec.ts:149` "should update order status to CONFIRMED"
- `orders.spec.ts:163` "should track status history"

Both send status **`CONFIRMED`** via `updateOrderStatus`. The service's `OrderStatus`
enum has **no `CONFIRMED`** value — valid values are `PENDING`, `PAID`, `PROCESSING`,
`SHIPPED`, `COMPLETED`, `CANCELLED` (`go/internal/order/model.go`). The PATCH is rejected
`400 BAD_REQUEST` (`status is required` from `IsValid()`), so `updatedOrder.status` is
`undefined` and the assertions fail.

The service also enforces a state machine (`CanTransitionTo`):

```
PENDING    → PAID | CANCELLED
PAID       → PROCESSING | CANCELLED
PROCESSING → SHIPPED | CANCELLED
SHIPPED    → COMPLETED
COMPLETED/CANCELLED → (terminal)
```

`updateOrderStatus` requires only a valid status + a legal transition; `paymentId` is
optional. So the tests must both use real enum values **and** follow a legal path.

## Fix (in the e2e tests, not the service)

1. `orders.spec.ts:149` — rename to "should update order status to PAID"; call
   `updateOrderStatus(order.id, 'PAID')`; assert `status` `'PAID'` and `updatedAt` defined.
   (`PAID` is the only non-cancel transition out of `PENDING`.)
2. `orders.spec.ts:163` "should track status history" — walk a legal chain:
   `PENDING → PAID → PROCESSING → SHIPPED`, asserting the final status is `'SHIPPED'`
   (and, if the test means to verify intermediate history, assert each step's returned
   status in turn).

Do **not** introduce `CONFIRMED` anywhere. If the product intent truly requires a
`CONFIRMED` state, that is a separate order-service change — out of scope here; align the
tests to the shipping contract.

## Acceptance

Against the Tier-1 vCluster substrate (`E2E_IMAGE_TAG=<new-e2e-sha>
./scripts/k3d-manager e2e_verify_vcluster`), `orders.spec.ts:149` and `:163` pass. No other
orders test regresses. (Payment specs remain Tier-2/ACG scope; the cart `quantity:0` test is
a **basket-service** bug tracked separately in
`docs/issues/2026-08-29-basket-update-quantity-zero-required.md`.)

## Recurrence — `flows/order-management.spec.ts` (2026-10-04)

**Status:** SPEC — dispatched to Codex 2026-10-04 (branch created by Claude from `origin/main` `35098ac`).

`make e2e` run `1791168841-15959` (k3d-manager `02aeeed0`, e2e-tests `origin/main` `35098ac`):
91 passed, 8 failed. All 8 are in `tests/flows/order-management.spec.ts`, each with
`HTTP 400 .../status: {"code":"BAD_REQUEST","message":"status is required"}`. The fix above
covered only `tests/api/orders.spec.ts`. The flow suite still sends `CONFIRMED` and
`DELIVERED`, neither of which exists in the Go `OrderStatus` enum. The previous run
(`1790970000-22917`) did not show this because only 57 of 102 tests ran.

Failing tests: "should follow standard order lifecycle", "should track status update
timestamps", "should preserve order details through status changes", "should cancel
confirmed order", "should not cancel shipped order", "should not cancel delivered order",
"should show mixed order statuses", "should handle rapid status updates".

### Fix spec (shopping-cart-e2e-tests, branch `fix/order-flow-status-enum`)

Edit only `tests/flows/order-management.spec.ts`. Map every status call onto a legal path
of the state machine above:

| Old call | New call(s) |
|---|---|
| `updateOrderStatus(id, 'CONFIRMED')` | `updateOrderStatus(id, 'PAID')` |
| `'CONFIRMED'` then `'SHIPPED'` | `'PAID'`, `'PROCESSING'`, `'SHIPPED'` |
| `'DELIVERED'` (after `SHIPPED`) | `'COMPLETED'` |

- Change every assertion to match: `toBe('CONFIRMED')` becomes `toBe('PAID')`,
  `toBe('DELIVERED')` becomes `toBe('COMPLETED')`, and `toContain('CONFIRMED')` (around :309)
  becomes `toContain('PAID')`.
- "should not cancel shipped order" and "should not cancel delivered order" must still
  assert that the cancel is rejected and the status is unchanged (`SHIPPED` / `COMPLETED`).
- Rename titles that name a missing status: "should cancel confirmed order" becomes "should
  cancel paid order", and "should not cancel delivered order" becomes "should not cancel
  completed order".
- Variable names such as `confirmedOrder` may stay.
- Done when: `grep -nE "'(CONFIRMED|DELIVERED)'" tests/flows/order-management.spec.ts`
  returns nothing, `npx tsc --noEmit` reports no more errors than `origin/main` (11 at
  `35098ac`, 3 of them already in this file; fixing those is out of scope), a PR is open, and after the merge the image is
  rebuilt and `make e2e` shows 0 `order-management` failures.
