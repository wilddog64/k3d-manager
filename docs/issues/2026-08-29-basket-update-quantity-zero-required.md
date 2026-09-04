# Basket: `PUT /cart/items/:id` with quantity 0 rejected — `required` blocks the remove path

**Repo:** `shopping-cart-basket` (spec-not-direct → Codex, branch + PR, rebuild image).
Deployed Tier-1 image `sha-f70d5801`.

## Finding

`tests/api/cart.spec.ts:98` ("should remove item when quantity set to 0") fails: after
`updateItem(itemId, { quantity: 0 })` the response has no `items` field
(`cart.items` is `undefined` → `toHaveLength(0)` throws). **The test is correct**; the
service is buggy.

Root cause (`internal/model/cart.go` at `f70d5801`):

```go
type UpdateItemRequest struct {
    Quantity int `json:"quantity" binding:"required,min=0"`
}
```

gin/validator treats a Go `int` zero value (`0`) as "missing" for `binding:"required"`,
so `{"quantity":0}` fails binding and the handler returns `400 BAD_REQUEST` **before**
`UpdateItemQuantity`'s own `if quantity <= 0 { remove item }` logic can run. The
`required` tag directly contradicts the intended feature (quantity 0 = remove item).

## Fix

Drop `required` from `UpdateItemRequest.Quantity` — use `binding:"min=0"` (or `gte=0`)
so `0` is an accepted, meaningful value. Confirm `UpdateItemQuantity` (already handles
`quantity <= 0`) then returns the cart with `items: []` (the removal leaves a non-nil
empty slice; `CartResponse.Items` has no `omitempty`, so it serializes `[]`).

## Acceptance

`cart.spec.ts:98` passes against the Tier-1 substrate with the rebuilt basket image; the
`PUT …/items/:id {quantity:0}` response is `200` with `items: []` and `totalAmount: 0`.
No regression to the `quantity: 5` update test.

## Note

This was initially mis-triaged as an e2e-test contract bug during the 2026-08-29 Tier-1
root-cause pass; grounding the assertion against the deployed basket source showed the
test is right and the service enforces an impossible `required` on a min-0 field.
