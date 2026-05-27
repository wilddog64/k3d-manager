# Bug: Frontend Checkout Contract Mismatch (Missing Shipping Address)

**Date:** 2026-05-27
**Severity:** High — prevents completion of order flow in the UI
**Status:** Investigated / RCA Documented
**Assignee:** Gemini CLI

## Symptom
In the Frontend UI, clicking "Proceed to Checkout" results in a red error message:
`Checkout failed. Please try again.`

## Root Cause Analysis
There is a contractual mismatch between the **Frontend** (React) and the **Basket Service** (Go):

1.  **Backend Requirement:** The `shopping-cart-basket` service defines a `CheckoutRequest` model that requires a non-empty `shippingAddress` object. The Go backend uses Gin's `ShouldBindJSON` with `binding:"required"` tags.
2.  **Frontend Implementation:** The `CartPage.tsx` component calls `cartService.checkout()`, which sends an empty POST body (`{}`) to `/api/v1/cart/checkout`.
3.  **Result:** The Backend rejects the request with `400 Bad Request` because the mandatory address fields (`street`, `city`, `state`, etc.) are missing.

## Architectural Context (Event-Driven Checkout)
The system uses an asynchronous, event-driven flow:
1.  **Sync:** `Basket Service` accepts the checkout request and validates the address.
2.  **Async:** `Basket Service` publishes a `cart.checkout` event to RabbitMQ.
3.  **Downstream:** `Order Service` creates the order; `Payment Service` processes payment based on the event data.

The failure occurs at **Step 1**, meaning the event chain never starts.

## Proposed Resolution (For Future Action)
1.  **Frontend Update:**
    *   Implement a Checkout Form or Modal to collect Name and Shipping Address.
    *   Update `cartService.ts` to accept and pass the address object in the POST body.
2.  **API Hardening (Optional):**
    *   Update `CheckoutRequest` in the Basket Service to also accept Payment Tokens or placeholders to ensure the `Payment Service` has the necessary data once the event reaches it.

## Manual Verification (CLI Workaround)
You can verify the backend is healthy by sending a manual request with the required data:
```bash
# Example manual checkout via curl
curl -X POST http://localhost:8080/api/cart/checkout \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "shippingAddress": {
      "street": "123 Dev Lane",
      "city": "Cloud City",
      "state": "K8s",
      "postalCode": "10101",
      "country": "US"
    }
  }'
```
