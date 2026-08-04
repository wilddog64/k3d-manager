# Bugfix: Stripe checkout Copilot hardening — order service

**Repo:** `shopping-cart-order` (work here; this spec lives in k3d-manager)
**Branches (two — apply each change to the branch named for it):**
- `feat/stripe-checkout-auth` (Phase A) — Change 1
- `feat/stripe-checkout-orchestrator` (Phase C) — Changes 2a–2e

These are Copilot review findings on PR #52 (A) and PR #53 (C). CI is already green;
these are correctness/security hardening, not build breaks. The Stripe path is gated off
until enablement, so none are live yet — fix them before the enablement flip.

---

## Problem

1. **(A) Empty-subject token accepted.** `AuthMiddleware` calls `SetCustomerID(c, claims.Subject)`
   without checking that `claims.Subject` is non-empty. A token that validates
   cryptographically but carries an empty `sub` lets downstream handlers proceed with an
   empty customer id.
2. **(C) `order.paid` event ships with no `paymentId`.** The orchestrator marks the order PAID
   with `UpdateOrderStatusRequest{Status, PaymentMethod}` but omits `PaymentID`. `order/service.go`
   uses `req.PaymentID` when publishing `order.paid`, so the event carries an empty payment id
   even though the payment succeeded and returned an `id`.
3. **(C) Basket `success:false` treated as success.** `BasketClient.GetCart` decodes the
   envelope but never checks `env.Success`. A basket 200 response with `success:false` is
   treated as a valid (empty) cart.

**Root cause:** missing validation/plumbing in the new Phase A/C code.

---

## Fix

### Branch `feat/stripe-checkout-auth`

#### Change 1 — `go/internal/httpx/auth.go`: reject empty subject

**Exact old block:**

```go
		claims, err := validator.ValidateToken(c.Request.Context(), parts[1])
		if err != nil {
			logger.Warn("token validation failed", zap.Error(err), zap.String("ip", clientIP(c.Request)))
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": "UNAUTHORIZED", "message": "Invalid or expired token"})
			return
		}
		SetCustomerID(c, claims.Subject)
```

**Exact new block:**

```go
		claims, err := validator.ValidateToken(c.Request.Context(), parts[1])
		if err != nil {
			logger.Warn("token validation failed", zap.Error(err), zap.String("ip", clientIP(c.Request)))
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": "UNAUTHORIZED", "message": "Invalid or expired token"})
			return
		}
		if strings.TrimSpace(claims.Subject) == "" {
			logger.Warn("token has empty subject", zap.String("ip", clientIP(c.Request)))
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"code": "UNAUTHORIZED", "message": "Invalid token: missing subject"})
			return
		}
		SetCustomerID(c, claims.Subject)
```

> `strings` is already imported in this file — no import change.

### Branch `feat/stripe-checkout-orchestrator`

#### Change 2a — `go/internal/checkout/client.go`: decode the payment id

**Exact old block:**

```go
type paymentResponse struct {
	Status        string  `json:"status"`
	FailureReason *string `json:"failureReason"`
}
```

**Exact new block:**

```go
type paymentResponse struct {
	ID            string  `json:"id"`
	Status        string  `json:"status"`
	FailureReason *string `json:"failureReason"`
}
```

> The payment service returns `PaymentResponse.ID` as `json:"id"` (payment `go/internal/payment/dto.go:39`).

#### Change 2b — `go/internal/checkout/client.go`: carry the payment id on the outcome

**Exact old block:**

```go
type PaymentOutcome struct {
	Paid          bool
	Status        string
	FailureReason string
}
```

**Exact new block:**

```go
type PaymentOutcome struct {
	Paid          bool
	Status        string
	FailureReason string
	PaymentID     string
}
```

#### Change 2c — `go/internal/checkout/client.go`: populate `PaymentID` in `ProcessPayment`

**Exact old block:**

```go
	out := PaymentOutcome{Status: pres.Status}
```

**Exact new block:**

```go
	out := PaymentOutcome{Status: pres.Status, PaymentID: pres.ID}
```

#### Change 2d — `go/internal/checkout/handler.go`: pass `PaymentID` when marking PAID

**Exact old block:**

```go
	if _, err := h.orders.UpdateOrderStatus(ctx, entity.ID, order.UpdateOrderStatusRequest{Status: order.OrderStatusPaid, PaymentMethod: h.gateway}, correlationID); err != nil {
```

**Exact new block:**

```go
	if _, err := h.orders.UpdateOrderStatus(ctx, entity.ID, order.UpdateOrderStatusRequest{Status: order.OrderStatusPaid, PaymentMethod: h.gateway, PaymentID: outcome.PaymentID}, correlationID); err != nil {
```

#### Change 2e — `go/internal/checkout/client.go`: reject basket `success:false`

**Exact old block:**

```go
	var env basketEnvelope
	if err := json.NewDecoder(resp.Body).Decode(&env); err != nil {
		return nil, fmt.Errorf("decode cart: %w", err)
	}
	return &env.Data, nil
```

**Exact new block:**

```go
	var env basketEnvelope
	if err := json.NewDecoder(resp.Body).Decode(&env); err != nil {
		return nil, fmt.Errorf("decode cart: %w", err)
	}
	if !env.Success {
		return nil, fmt.Errorf("basket GET /api/v1/cart: success=false")
	}
	return &env.Data, nil
```

---

## Files Changed

| Branch | File | Change |
|--------|------|--------|
| `feat/stripe-checkout-auth` | `go/internal/httpx/auth.go` | reject empty `sub` |
| `feat/stripe-checkout-orchestrator` | `go/internal/checkout/client.go` | `id` field, `PaymentID` on outcome, populate it, `env.Success` check |
| `feat/stripe-checkout-orchestrator` | `go/internal/checkout/handler.go` | pass `PaymentID` to `UpdateOrderStatus` |

---

## Rules

- `cd go && gofmt -l .` → no output; `go build ./...` clean; `go vet ./...` clean.
- `cd go && go test -count=1 ./internal/checkout/... ./internal/httpx/... ./internal/auth/...` must pass.
- If `checkout/handler_test.go`'s fake basket server returns a cart envelope, ensure it sets
  `"success": true` (or the fake's `basketEnvelope`) so Change 2e does not break existing tests.
  Update fakes/fixtures as needed — do not change production behaviour to accommodate a test.
- Do not touch any file outside the three listed. Do not touch `go.mod`/`go.sum`.
- Keep the existing golangci-lint clean (errcheck etc.).

---

## Definition of Done

- [ ] Change 1 committed on `feat/stripe-checkout-auth`
- [ ] Changes 2a–2e committed on `feat/stripe-checkout-orchestrator`
- [ ] `gofmt`/`go build`/`go vet`/`go test` all green uncached on each branch
- [ ] Both branches pushed to origin
- [ ] memory-bank updated (repo-local) as a separate commit with both SHAs

**Commit message — `feat/stripe-checkout-auth` (exact):**
```
fix(auth): reject tokens with empty subject
```

**Commit message — `feat/stripe-checkout-orchestrator` (exact):**
```
fix(checkout): thread payment id to order.paid and reject basket success=false
```

---

## What NOT to Do

- Do NOT create a PR (PRs #52 and #53 already exist — pushing updates them)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed
- Do NOT commit to `main` — work on the two named feature branches
- Do NOT change `go.mod`/`go.sum`
