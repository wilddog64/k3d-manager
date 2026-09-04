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
