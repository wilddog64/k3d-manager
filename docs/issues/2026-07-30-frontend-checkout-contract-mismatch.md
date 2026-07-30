# Frontend checkout sends no required shipping address and expects the wrong response

## Live evidence

At 2026-07-30 22:22:14 UTC, the logged-in frontend successfully added a product to cart:

```text
POST /api/cart/items     201
POST /api/cart/checkout  400
```

The basket service was Ready and logged the checkout request as a 400 in 1 ms. No order
or payment failure followed.

## Root cause

The deployed frontend (`shopping-cart-frontend` image revision `7b103d4a`) implements
checkout as an empty `POST /api/cart/checkout`. The deployed basket revision
`40155429` calls `ShouldBindJSON` into `CheckoutRequest`, which requires:

```json
{
  "shippingAddress": {
    "street": "…",
    "city": "…",
    "state": "…",
    "postalCode": "…",
    "country": "…"
  }
}
```

An empty POST therefore returns HTTP 400 before checkout event publication, order
creation, or payment processing.

There is a second contract mismatch: the frontend expects `{ "orderId": "…" }`, but
the basket handler returns `{ "message": "Checkout successful", "cart": … }` after
publishing its asynchronous checkout event. A payload-only frontend fix would then route
to `/orders/undefined`.

## Required fix

Align the frontend with the basket checkout contract: collect and validate shipping
address fields, send them in the checkout body, and handle the asynchronous success
response without assuming an immediate order ID. Add a frontend test covering the payload
and success/error behaviour. If product requirements demand immediate order navigation,
change the basket/order API contract deliberately and update both services together.
