# Bugfix: Go rewrite PR1 — Copilot round-2 hardening (payment #23 + order #33)

**Repos / branches (all work repos):**
- `shopping-cart-payment` — branch `feat/go-rewrite`
- `shopping-cart-order` — branch `feat/go-rewrite`

**Spec lives in:** `k3d-manager` (this file). Do the work in the two shopping-cart repos above.

---

## Problem

Copilot posted a second review on both Go-rewrite PRs (2026-06-19):
- payment #23 review `4529362992` — 11 new inline findings against HEAD `e2adc72`
- order #33 review `4529487112` — 6 new inline findings

This spec implements **all 17 findings** (no deferrals — addressed now to avoid carrying tech
debt). The three that were initially candidates for decline/defer are handled as follows:

| Repo | File:line | Finding | Disposition |
|------|-----------|---------|-------------|
| payment | config.go:78 | MockGatewayEnabled default true | **FIX (A7)** — flip code default to `false`; the deployment explicitly enables the mock via configmap so the stack/e2e still work (mock is reachable only by opt-in). |
| order | store.go:150 | `ListByCustomer` N+1 | **FIX (B6)** — single batched `WHERE order_id = ANY(...)` query + in-memory grouping. |
| order | config.go:48 | DB_SSLMODE default `disable` | **FIX (B5) — documented, not flipped.** The in-cluster Postgres is stock `postgres:15-alpine` (NO native TLS), so `sslmode=require` cannot connect; transport is secured by Istio mTLS. The debt-free fix is to make the value **explicit** in the order configmap (`DB_SSLMODE: "disable"`) with a rationale comment, so it is a reviewed config decision, not a silent code default. Claude replies on the thread with this rationale. |

---

## Before You Start

1. `git pull origin k3d-manager-v1.7.1` in k3d-manager and read this spec in full.
2. In each work repo: `git checkout feat/go-rewrite && git pull origin feat/go-rewrite`.
3. Read the target files before editing. Use exact old/new blocks below — no interpretation.

---

# PART A — `shopping-cart-payment` (branch `feat/go-rewrite`)

### A1 — `go/internal/gateway/mock.go`: replace PAN-like trigger literals with non-PAN sentinels (Copilot 3439639724)

**Exact old block (lines 36–43):**

```go
	if request.CardNumber != "" {
		switch request.CardNumber {
		case "4000000000000002":
			return PaymentResultFailure("card_declined", "Your card was declined")
		case "4000000000009995":
			return PaymentResultFailure("insufficient_funds", "Insufficient funds")
		}
	}
```

**Exact new block:**

```go
	if request.CardNumber != "" {
		switch request.CardNumber {
		case mockDeclineToken:
			return PaymentResultFailure("card_declined", "Your card was declined")
		case mockInsufficientFundsToken:
			return PaymentResultFailure("insufficient_funds", "Insufficient funds")
		}
	}
```

**Also add these constants** immediately after the `import (...)` block (after line 10):

```go
const (
	mockDeclineToken           = "tok_mock_decline"
	mockInsufficientFundsToken = "tok_mock_insufficient_funds"
)
```

> No repo code or the e2e suite references the old 16-digit literals (verified), so this only
> changes the in-mock failure-trigger tokens.

---

### A2 — `go/internal/payment/service.go`: short-circuit idempotency/order BEFORE gateway selection (Copilot 3439639735)

**Exact old block (lines 31–56):**

```go
func (s *PaymentService) ProcessPayment(ctx context.Context, req ProcessPaymentRequest, correlationID, idempotencyKey string) (*Payment, error) {
	gatewayImpl, err := s.router.GetGatewayOrDefault(req.Gateway)
	if err != nil {
		return nil, err
	}

	if strings.TrimSpace(idempotencyKey) != "" {
		if existing, err := s.store.GetPaymentByIdempotencyKey(ctx, idempotencyKey); err == nil {
			return existing, nil
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
	}

	if existing, err := s.store.GetPaymentByOrderID(ctx, req.OrderID); err == nil {
		if existing.Status == PaymentStatusCompleted {
			return existing, nil
		}
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	paymentMethodID := uuid.NullUUID{}
	if parsed, err := uuid.Parse(strings.TrimSpace(req.PaymentMethodID)); err == nil {
		paymentMethodID = uuid.NullUUID{UUID: parsed, Valid: true}
	}
```

**Exact new block:**

```go
func (s *PaymentService) ProcessPayment(ctx context.Context, req ProcessPaymentRequest, correlationID, idempotencyKey string) (*Payment, error) {
	if strings.TrimSpace(idempotencyKey) != "" {
		if existing, err := s.store.GetPaymentByIdempotencyKey(ctx, idempotencyKey); err == nil {
			return existing, nil
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
	}

	if existing, err := s.store.GetPaymentByOrderID(ctx, req.OrderID); err == nil {
		if existing.Status == PaymentStatusCompleted {
			return existing, nil
		}
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return nil, err
	}

	gatewayImpl, err := s.router.GetGatewayOrDefault(req.Gateway)
	if err != nil {
		return nil, err
	}

	paymentMethodID := uuid.NullUUID{}
	if parsed, err := uuid.Parse(strings.TrimSpace(req.PaymentMethodID)); err == nil {
		paymentMethodID = uuid.NullUUID{UUID: parsed, Valid: true}
	}
```

---

### A3 — `go/internal/payment/service.go`: drop sensitive `req` from the persistence path (Copilot 3439639738)

**Exact old block (lines 97–99):**

```go
	persist := func(store paymentStore) error {
		return persistProcessedPayment(ctx, store, payment, req, correlationID, result, now)
	}
```

**Exact new block:**

```go
	persist := func(store paymentStore) error {
		return persistProcessedPayment(ctx, store, payment, correlationID, result, now)
	}
```

**Exact old block (line 164, function signature):**

```go
func persistProcessedPayment(ctx context.Context, store paymentStore, payment *Payment, req ProcessPaymentRequest, correlationID string, result gateway.PaymentResult, now time.Time) error {
```

**Exact new block:**

```go
func persistProcessedPayment(ctx context.Context, store paymentStore, payment *Payment, correlationID string, result gateway.PaymentResult, now time.Time) error {
```

**Exact old block (lines 179–180, inside `CreateTransaction`):**

```go
		Amount:               req.Amount,
		Currency:             strings.ToUpper(req.Currency),
```

**Exact new block** (the `payment` struct already holds the parsed amount and upper-cased currency):

```go
		Amount:               payment.Amount,
		Currency:             payment.Currency,
```

> `persistProcessedPayment` no longer references `req`, so `CardNumber`/`CardCVC` are not
> carried into the persistence/transaction path.

---

### A4 — `go/internal/payment/errors.go` + `handler.go` + `httpx/middleware.go`: 4xx-map router errors, stop leaking internals on 500 (Copilot 3439639753, 3439639762, 3439639779)

**A4a — `go/internal/payment/errors.go`. Exact old block (lines 1–12):**

```go
package payment

import (
	"errors"
	"fmt"
)

type APIError struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
}
```

**Exact new block:**

```go
package payment

import (
	"errors"
	"fmt"
	"strings"
)

type APIError struct {
	Status  int    `json:"-"`
	Code    string `json:"code"`
	Message string `json:"message"`
	cause   error  `json:"-"`
}
```

**A4b — `go/internal/payment/errors.go`. Exact old block (lines 37–52):**

```go
func APIErrorFromErr(err error) *APIError {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, ErrPaymentNotFound):
		return NotFound("PAYMENT_NOT_FOUND", err.Error())
	case errors.Is(err, ErrRefundNotFound):
		return NotFound("REFUND_NOT_FOUND", err.Error())
	case errors.Is(err, ErrRefundNotAllowed):
		return BadRequest("REFUND_NOT_ALLOWED", err.Error())
	case errors.Is(err, ErrRefundExceedsRemaining):
		return BadRequest("REFUND_AMOUNT_TOO_LARGE", err.Error())
	default:
		return &APIError{Status: 500, Code: "INTERNAL_SERVER_ERROR", Message: err.Error()}
	}
}
```

**Exact new block:**

```go
func APIErrorFromErr(err error) *APIError {
	switch {
	case err == nil:
		return nil
	case errors.Is(err, ErrPaymentNotFound):
		return NotFound("PAYMENT_NOT_FOUND", err.Error())
	case errors.Is(err, ErrRefundNotFound):
		return NotFound("REFUND_NOT_FOUND", err.Error())
	case errors.Is(err, ErrRefundNotAllowed):
		return BadRequest("REFUND_NOT_ALLOWED", err.Error())
	case errors.Is(err, ErrRefundExceedsRemaining):
		return BadRequest("REFUND_AMOUNT_TOO_LARGE", err.Error())
	case strings.Contains(err.Error(), "unknown gateway"):
		return BadRequest("GATEWAY_UNKNOWN", err.Error())
	case strings.Contains(err.Error(), "gateway is not enabled"):
		return BadRequest("GATEWAY_NOT_ENABLED", err.Error())
	default:
		return &APIError{Status: 500, Code: "INTERNAL_SERVER_ERROR", Message: "An internal error occurred", cause: err}
	}
}
```

**A4c — `go/internal/payment/handler.go`: log the underlying cause server-side. Exact old block (lines 184–192):**

```go
func (h *Handler) abortWithError(c *gin.Context, apiErr *APIError) {
	if apiErr == nil {
		apiErr = &APIError{Status: http.StatusInternalServerError, Code: "INTERNAL_SERVER_ERROR", Message: "unknown error"}
	}
	c.AbortWithStatusJSON(apiErr.Status, gin.H{
		"code":    apiErr.Code,
		"message": apiErr.Message,
	})
}
```

**Exact new block:**

```go
func (h *Handler) abortWithError(c *gin.Context, apiErr *APIError) {
	if apiErr == nil {
		apiErr = &APIError{Status: http.StatusInternalServerError, Code: "INTERNAL_SERVER_ERROR", Message: "unknown error"}
	}
	if apiErr.cause != nil {
		_ = c.Error(apiErr.cause)
	}
	c.AbortWithStatusJSON(apiErr.Status, gin.H{
		"code":    apiErr.Code,
		"message": apiErr.Message,
	})
}
```

**A4d — `go/internal/httpx/middleware.go`: surface `c.Errors` in the request log. Exact old block (lines 116–122):**

```go
		logger.Info("request",
			zap.String("method", c.Request.Method),
			zap.String("path", c.Request.URL.Path),
			zap.Int("status", c.Writer.Status()),
			zap.Duration("duration", time.Since(start)),
			zap.String("client_ip", c.ClientIP()),
		)
```

**Exact new block:**

```go
		fields := []zap.Field{
			zap.String("method", c.Request.Method),
			zap.String("path", c.Request.URL.Path),
			zap.Int("status", c.Writer.Status()),
			zap.Duration("duration", time.Since(start)),
			zap.String("client_ip", c.ClientIP()),
		}
		if len(c.Errors) > 0 {
			fields = append(fields, zap.String("error", c.Errors.String()))
		}
		logger.Info("request", fields...)
```

---

### A5 — `go/internal/config/config.go`: remove unused `RateLimitPerMinute` (Copilot 3439639770, 3439639774)

**Exact old block (lines 46–49):**

```go
	RateLimitEnabled   bool
	RateLimitPerMinute int
	RateLimitPerSecond int
	RateLimitBurst     int
```

**Exact new block:**

```go
	RateLimitEnabled   bool
	RateLimitPerSecond int
	RateLimitBurst     int
```

**Exact old block (lines 95–98):**

```go
		RateLimitEnabled:   boolEnv("RATE_LIMIT_ENABLED", true),
		RateLimitPerMinute: intEnv("RATE_LIMIT_PER_MINUTE", 60),
		RateLimitPerSecond: intEnv("RATE_LIMIT_PER_SECOND", 10),
		RateLimitBurst:     intEnv("RATE_LIMIT_BURST", 20),
```

**Exact new block:**

```go
		RateLimitEnabled:   boolEnv("RATE_LIMIT_ENABLED", true),
		RateLimitPerSecond: intEnv("RATE_LIMIT_PER_SECOND", 10),
		RateLimitBurst:     intEnv("RATE_LIMIT_BURST", 20),
```

> After editing, grep the repo for `RateLimitPerMinute` / `RATE_LIMIT_PER_MINUTE` and remove
> any remaining references (config tests, docs) so the build stays green.

---

### A6 — `go/internal/payment/store.go` + `refund.go`: wrap refund in a transaction with a locking re-check (Copilot 3439639744, 3439639746)

**A6a — `go/internal/payment/store.go`: add `GetPaymentForUpdate` to the interface.
Exact old block (line 20):**

```go
	GetPayment(ctx context.Context, id uuid.UUID) (*Payment, error)
```

**Exact new block:**

```go
	GetPayment(ctx context.Context, id uuid.UUID) (*Payment, error)
	GetPaymentForUpdate(ctx context.Context, id uuid.UUID) (*Payment, error)
```

**A6b — `go/internal/payment/store.go`: add the impl immediately after `GetPayment`
(after line 196, before `GetPaymentByOrderID`):**

```go
func (s *Store) GetPaymentForUpdate(ctx context.Context, id uuid.UUID) (*Payment, error) {
	row := s.db.QueryRow(ctx, `
SELECT
    id, order_id, customer_id, amount::text, currency, status, gateway,
    gateway_transaction_id, gateway_payment_intent_id, payment_method_id::text,
    card_last4, card_brand, metadata, failure_reason, failure_code,
    created_at, processed_at, completed_at, updated_at, correlation_id, idempotency_key
FROM payments
WHERE id = $1
FOR UPDATE`, id)
	return scanPaymentRow(row)
}
```

**A6c — `go/internal/payment/refund.go`: wrap the DB mutations in `RunInTx` and re-validate the
remaining balance under a row lock. Replace the whole `ProcessRefund` function.
Exact old block (lines 26–144):**

```go
func (s *RefundService) ProcessRefund(ctx context.Context, paymentID uuid.UUID, amount decimal.Decimal, reason, initiatedBy, correlationID string) (*Refund, error) {
	if strings.TrimSpace(correlationID) != "" {
		if existing, err := s.store.GetRefundByCorrelationID(ctx, correlationID); err == nil {
			return existing, nil
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
	}

	payment, err := s.store.GetPayment(ctx, paymentID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrPaymentNotFound
	}
	if err != nil {
		return nil, err
	}

	if payment.Status != PaymentStatusCompleted && payment.Status != PaymentStatusRefundPending {
		return nil, ErrRefundNotAllowed
	}

	totalRefunded, err := s.GetTotalRefunded(ctx, paymentID)
	if err != nil {
		return nil, err
	}
	remaining := payment.Amount.Sub(totalRefunded)
	if amount.Cmp(remaining) > 0 {
		return nil, ErrRefundExceedsRemaining
	}

	gatewayImpl, err := s.router.GetGateway(payment.Gateway)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	refund := &Refund{
		ID:            uuid.New(),
		PaymentID:     paymentID,
		Amount:        amount,
		Currency:      payment.Currency,
		Status:        RefundStatusPending,
		Reason:        nullString(reason),
		InitiatedBy:   nullString(initiatedBy),
		CorrelationID: nullString(correlationID),
		CreatedAt:     now,
	}
	if err := s.store.CreateRefund(ctx, refund); err != nil {
		return nil, err
	}

	payment.Status = PaymentStatusRefundPending
	if err := s.store.UpdatePayment(ctx, payment); err != nil {
		return nil, err
	}

	refund.Status = RefundStatusProcessing
	refund.ProcessedAt = sql.NullTime{Time: time.Now().UTC(), Valid: true}
	if err := s.store.UpdateRefund(ctx, refund); err != nil {
		return nil, err
	}

	gatewayRequest := gateway.RefundRequest{
		PaymentTransactionID: payment.GatewayTransactionID.String,
		PaymentIntentID:      payment.GatewayPaymentIntentID.String,
		Amount:               amount,
		Currency:             payment.Currency,
		Reason:               reason,
		CorrelationID:        correlationID,
	}
	result := gatewayImpl.ProcessRefund(gatewayRequest)

	if err := s.store.CreateTransaction(ctx, &Transaction{
		ID:                   uuid.New(),
		PaymentID:            paymentID,
		RefundID:             uuid.NullUUID{UUID: refund.ID, Valid: true},
		Type:                 TransactionTypeRefund,
		Amount:               amount,
		Currency:             payment.Currency,
		Success:              result.Success,
		GatewayTransactionID: nullString(result.RefundID),
		GatewayResponse:      nullString(result.RawResponse),
		GatewayErrorCode:     nullString(result.ErrorCode),
		GatewayErrorMessage:  nullString(result.ErrorMessage),
		CreatedAt:            time.Now().UTC(),
		CorrelationID:        nullString(correlationID),
	}); err != nil {
		return nil, err
	}

	if result.Success {
		refund.Status = RefundStatusCompleted
		refund.GatewayRefundID = nullString(result.RefundID)
		refund.CompletedAt = sql.NullTime{Time: time.Now().UTC(), Valid: true}
		refund.FailureReason = sql.NullString{}
		refund.FailureCode = sql.NullString{}
		if amount.Cmp(remaining) >= 0 {
			payment.Status = PaymentStatusRefunded
		} else {
			payment.Status = PaymentStatusCompleted
		}
		if err := s.store.UpdatePayment(ctx, payment); err != nil {
			return nil, err
		}
	} else {
		refund.Status = RefundStatusFailed
		refund.FailureCode = nullString(result.ErrorCode)
		refund.FailureReason = nullString(result.ErrorMessage)
		payment.Status = PaymentStatusRefundFailed
		if err := s.store.UpdatePayment(ctx, payment); err != nil {
			return nil, err
		}
	}

	if err := s.store.UpdateRefund(ctx, refund); err != nil {
		return nil, err
	}
	return refund, nil
}
```

**Exact new block:**

```go
func (s *RefundService) ProcessRefund(ctx context.Context, paymentID uuid.UUID, amount decimal.Decimal, reason, initiatedBy, correlationID string) (*Refund, error) {
	if strings.TrimSpace(correlationID) != "" {
		if existing, err := s.store.GetRefundByCorrelationID(ctx, correlationID); err == nil {
			return existing, nil
		} else if !errors.Is(err, pgx.ErrNoRows) {
			return nil, err
		}
	}

	payment, err := s.store.GetPayment(ctx, paymentID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrPaymentNotFound
	}
	if err != nil {
		return nil, err
	}

	if payment.Status != PaymentStatusCompleted && payment.Status != PaymentStatusRefundPending {
		return nil, ErrRefundNotAllowed
	}

	gatewayImpl, err := s.router.GetGateway(payment.Gateway)
	if err != nil {
		return nil, err
	}

	now := time.Now().UTC()
	refund := &Refund{
		ID:            uuid.New(),
		PaymentID:     paymentID,
		Amount:        amount,
		Currency:      payment.Currency,
		Status:        RefundStatusPending,
		Reason:        nullString(reason),
		InitiatedBy:   nullString(initiatedBy),
		CorrelationID: nullString(correlationID),
		CreatedAt:     now,
	}

	gatewayRequest := gateway.RefundRequest{
		PaymentTransactionID: payment.GatewayTransactionID.String,
		PaymentIntentID:      payment.GatewayPaymentIntentID.String,
		Amount:               amount,
		Currency:             payment.Currency,
		Reason:               reason,
		CorrelationID:        correlationID,
	}

	persist := func(store paymentStore) error {
		locked, err := store.GetPaymentForUpdate(ctx, paymentID)
		if err != nil {
			return err
		}
		if locked.Status != PaymentStatusCompleted && locked.Status != PaymentStatusRefundPending {
			return ErrRefundNotAllowed
		}

		existingRefunds, err := store.GetRefundsByPayment(ctx, paymentID)
		if err != nil {
			return err
		}
		totalRefunded := decimal.Zero
		for _, r := range existingRefunds {
			if r.Status == RefundStatusCompleted {
				totalRefunded = totalRefunded.Add(r.Amount)
			}
		}
		remaining := locked.Amount.Sub(totalRefunded)
		if amount.Cmp(remaining) > 0 {
			return ErrRefundExceedsRemaining
		}

		if err := store.CreateRefund(ctx, refund); err != nil {
			return err
		}

		locked.Status = PaymentStatusRefundPending
		if err := store.UpdatePayment(ctx, locked); err != nil {
			return err
		}

		refund.Status = RefundStatusProcessing
		refund.ProcessedAt = sql.NullTime{Time: time.Now().UTC(), Valid: true}
		if err := store.UpdateRefund(ctx, refund); err != nil {
			return err
		}

		result := gatewayImpl.ProcessRefund(gatewayRequest)

		if err := store.CreateTransaction(ctx, &Transaction{
			ID:                   uuid.New(),
			PaymentID:            paymentID,
			RefundID:             uuid.NullUUID{UUID: refund.ID, Valid: true},
			Type:                 TransactionTypeRefund,
			Amount:               amount,
			Currency:             payment.Currency,
			Success:              result.Success,
			GatewayTransactionID: nullString(result.RefundID),
			GatewayResponse:      nullString(result.RawResponse),
			GatewayErrorCode:     nullString(result.ErrorCode),
			GatewayErrorMessage:  nullString(result.ErrorMessage),
			CreatedAt:            time.Now().UTC(),
			CorrelationID:        nullString(correlationID),
		}); err != nil {
			return err
		}

		if result.Success {
			refund.Status = RefundStatusCompleted
			refund.GatewayRefundID = nullString(result.RefundID)
			refund.CompletedAt = sql.NullTime{Time: time.Now().UTC(), Valid: true}
			refund.FailureReason = sql.NullString{}
			refund.FailureCode = sql.NullString{}
			if amount.Cmp(remaining) >= 0 {
				locked.Status = PaymentStatusRefunded
			} else {
				locked.Status = PaymentStatusCompleted
			}
		} else {
			refund.Status = RefundStatusFailed
			refund.FailureCode = nullString(result.ErrorCode)
			refund.FailureReason = nullString(result.ErrorMessage)
			locked.Status = PaymentStatusRefundFailed
		}

		if err := store.UpdatePayment(ctx, locked); err != nil {
			return err
		}
		if err := store.UpdateRefund(ctx, refund); err != nil {
			return err
		}
		return nil
	}

	if runner, ok := s.store.(paymentTransactionRunner); ok {
		if err := runner.RunInTx(ctx, persist); err != nil {
			return nil, err
		}
	} else {
		if err := persist(s.store); err != nil {
			return nil, err
		}
	}
	return refund, nil
}
```

> The mock gateway is the only enabled gateway in PR1 (Stripe/PayPal deferred), so calling it
> inside the tx is safe — it performs no external network I/O. The `FOR UPDATE` lock plus the
> in-tx recompute of `remaining` closes the concurrent over-refund race (3439639744) and the
> single tx makes the multi-write flow atomic (3439639746).
>
> Any mock-only fake-success unit test for refund that asserted intermediate `RefundStatusProcessing`
> via a non-transactional store must still pass — `paymentStore` fakes that don't implement
> `paymentTransactionRunner` fall through to the direct `persist(s.store)` path. If a fake store
> implements the interface, add the new `GetPaymentForUpdate` method to it (delegate to `GetPayment`).

---

### A7 — disable the mock gateway by default; enable it explicitly in the deployment (Copilot 3439639768)

Flip the code default to `false` so the mock is reachable only by explicit opt-in, then have the
deployed stack opt in via configmap (the e2e suite drives payments through the mock).

**A7a — `go/internal/config/config.go`. Exact old block (line 78):**

```go
		MockGatewayEnabled: boolEnv("MOCK_GATEWAY_ENABLED", true),
```

**Exact new block:**

```go
		MockGatewayEnabled: boolEnv("MOCK_GATEWAY_ENABLED", false),
```

**A7b — `k8s/base/configmap.yaml`: add the opt-in key. Exact old block (lines 16–19):**

```yaml
  # Payment Gateway Configuration
  payment.gateway.default: "mock"
  stripe.enabled: "false"
  paypal.enabled: "false"
```

**Exact new block:**

```yaml
  # Payment Gateway Configuration
  payment.gateway.default: "mock"
  mock.gateway.enabled: "true"
  stripe.enabled: "false"
  paypal.enabled: "false"
```

**A7c — `k8s/base/deployment.yaml`: wire the env var. Exact old block (lines 87–92):**

```yaml
        - name: PAYMENT_GATEWAY_DEFAULT
          valueFrom:
            configMapKeyRef:
              name: payment-service-config
              key: payment.gateway.default
        - name: STRIPE_ENABLED
```

**Exact new block:**

```yaml
        - name: PAYMENT_GATEWAY_DEFAULT
          valueFrom:
            configMapKeyRef:
              name: payment-service-config
              key: payment.gateway.default
        - name: MOCK_GATEWAY_ENABLED
          valueFrom:
            configMapKeyRef:
              name: payment-service-config
              key: mock.gateway.enabled
        - name: STRIPE_ENABLED
```

> If a config test asserts `MockGatewayEnabled == true` as the default, update it to `false`.
> Go unit tests that construct `NewMockGateway(true, …)` directly are unaffected.

---

# PART B — `shopping-cart-order` (branch `feat/go-rewrite`)

### B1 — `go/internal/config/config.go`: drop default RabbitMQ credentials (Copilot 3439740585)

**Exact old block (lines 52–53):**

```go
		RabbitMQUsername: getEnv("RABBITMQ_USERNAME", "guest"),
		RabbitMQPassword: getEnv("RABBITMQ_PASSWORD", "guest"),
```

**Exact new block:**

```go
		RabbitMQUsername: getEnv("RABBITMQ_USERNAME", ""),
		RabbitMQPassword: getEnv("RABBITMQ_PASSWORD", ""),
```

> Matches the payment service (both default `""`). The Go publisher dials lazily, so empty
> defaults don't break startup or the Postgres-only integration test; deployment env supplies creds.

---

### B2 — `go/internal/events/publisher.go`: serialize concurrent publishes on the shared channel (Copilot 3439740602)

**Exact old block (lines 252–259):**

```go
type RabbitPublisher struct {
	uri      string
	logger   *zap.Logger
	mu       sync.Mutex
	conn     *amqp.Connection
	channel  *amqp.Channel
	declared bool
}
```

**Exact new block:**

```go
type RabbitPublisher struct {
	uri      string
	logger   *zap.Logger
	mu       sync.Mutex
	pubMu    sync.Mutex
	conn     *amqp.Connection
	channel  *amqp.Channel
	declared bool
}
```

**Exact old block (lines 265–286):**

```go
func (p *RabbitPublisher) Publish(ctx context.Context, envelope Envelope) error {
	payload, err := json.Marshal(envelope)
	if err != nil {
		return fmt.Errorf("marshal envelope: %w", err)
	}

	channel, err := p.ensureChannel(ctx)
	if err != nil {
		return err
	}

	if err := channel.PublishWithContext(ctx, ExchangeName, envelope.Type, false, false, amqp.Publishing{
		ContentType:  "application/json",
		DeliveryMode: amqp.Persistent,
		Body:         payload,
	}); err != nil {
		_ = p.reset()
		return fmt.Errorf("publish %s: %w", envelope.Type, err)
	}

	return nil
}
```

**Exact new block:**

```go
func (p *RabbitPublisher) Publish(ctx context.Context, envelope Envelope) error {
	payload, err := json.Marshal(envelope)
	if err != nil {
		return fmt.Errorf("marshal envelope: %w", err)
	}

	channel, err := p.ensureChannel(ctx)
	if err != nil {
		return err
	}

	p.pubMu.Lock()
	pubErr := channel.PublishWithContext(ctx, ExchangeName, envelope.Type, false, false, amqp.Publishing{
		ContentType:  "application/json",
		DeliveryMode: amqp.Persistent,
		Body:         payload,
	})
	p.pubMu.Unlock()

	if pubErr != nil {
		_ = p.reset()
		return fmt.Errorf("publish %s: %w", envelope.Type, pubErr)
	}

	return nil
}
```

> `pubMu` serializes the non-thread-safe `*amqp.Channel` publish call. `reset()` (which takes
> `p.mu`) is called only after `pubMu` is released, so there is no nested-lock deadlock.

---

### B3 — `CHANGELOG.md`: merge the two consecutive `### Added` sections (Copilot 3439740630)

**Exact old block (lines 5–12):**

```markdown
### Added
- Go rewrite PR1 for `shopping-cart-order`: add the functional Go core under `go/` (HTTP, Postgres, RabbitMQ events, status machine, actuator endpoints, rate limiting, and side-by-side Java/Go CI)

### Added
- `docs/guides/configuration.md` — full env var reference, actuator endpoints, Spring Cloud Bus config auto-refresh how-to, and three broker-free alternatives (ConfigMap mount, Spring Cloud Kubernetes, Kafka)
- `docs/issues/2026-03-25-rabbitmq-connection-refused.md` — root cause analysis for RabbitMQ CrashLoopBackOff (fixed in shopping-cart-infra PR #22)
- `docs/issues/2026-04-11-copilot-pr25-review-findings.md` — stale status date in activeContext.md, inaccurate CHANGELOG entry for README Issue Logs
- README: update Issue Logs to 5 most recent entries — Copilot PR #25 findings, Copilot PR #24 findings, RabbitMQ connection refused, Rate limiting distributed state, Multi-arch workflow pin
```

**Exact new block:**

```markdown
### Added
- Go rewrite PR1 for `shopping-cart-order`: add the functional Go core under `go/` (HTTP, Postgres, RabbitMQ events, status machine, actuator endpoints, rate limiting, and side-by-side Java/Go CI)
- `docs/guides/configuration.md` — full env var reference, actuator endpoints, Spring Cloud Bus config auto-refresh how-to, and three broker-free alternatives (ConfigMap mount, Spring Cloud Kubernetes, Kafka)
- `docs/issues/2026-03-25-rabbitmq-connection-refused.md` — root cause analysis for RabbitMQ CrashLoopBackOff (fixed in shopping-cart-infra PR #22)
- `docs/issues/2026-04-11-copilot-pr25-review-findings.md` — stale status date in activeContext.md, inaccurate CHANGELOG entry for README Issue Logs
- README: update Issue Logs to 5 most recent entries — Copilot PR #25 findings, Copilot PR #24 findings, RabbitMQ connection refused, Rate limiting distributed state, Multi-arch workflow pin
```

---

### B4 — relocate the Go-only migration out of the Java tree (Copilot 3439740644)

The migration `src/main/resources/db/migration/V1__init_schema.sql` is net-new in this PR
(commit `ac85ad5`), the Java app does **not** use Flyway, and only the Go integration test reads
it. Move it into the Go test tree so the Java artifact is truly unchanged.

**Step 1 — move the file (preserve history):**

```bash
git mv src/main/resources/db/migration/V1__init_schema.sql go/internal/order/testdata/V1__init_schema.sql
```

If `src/main/resources/db/migration/` (and parent `db/`) is now empty, remove the empty dirs.

**Step 2 — `go/internal/order/store_integration_test.go`: update the path.
Exact old block (line 31):**

```go
		filepath.Join("..", "..", "..", "src", "main", "resources", "db", "migration", "V1__init_schema.sql"),
```

**Exact new block:**

```go
		filepath.Join("testdata", "V1__init_schema.sql"),
```

> `store_integration_test.go` lives in `go/internal/order/`, so `testdata/V1__init_schema.sql`
> resolves to the moved file. `testdata` is ignored by the Go toolchain — correct home for a
> test fixture.

---

### B5 — make `DB_SSLMODE` an explicit, documented config value (Copilot 3439740560)

Do **not** change the code default. The in-cluster Postgres is stock `postgres:15-alpine` with no
native TLS, so `sslmode=require` would fail to connect; transport is secured by Istio mTLS. Make
the value explicit in the configmap so it is a reviewed decision, not a silent default.

**`k8s/base/configmap.yaml`: Exact old block (lines 15–19):**

```yaml
  # Database connection (host only, credentials from secret)
  DB_HOST: "postgresql-orders.shopping-cart-data.svc.cluster.local"
  DB_PORT: "5432"
  DB_NAME: "orders"
```

**Exact new block:**

```yaml
  # Database connection (host only, credentials from secret)
  DB_HOST: "postgresql-orders.shopping-cart-data.svc.cluster.local"
  DB_PORT: "5432"
  DB_NAME: "orders"
  # In-cluster Postgres is non-TLS (stock image); transport is secured by Istio mTLS.
  # Production overrides this to "require".
  DB_SSLMODE: "disable"
```

> Do NOT touch `go/internal/config/config.go:47` — the code default already reads `DB_SSLMODE`
> from env and `disable` is correct for the non-TLS in-cluster DB.

---

### B6 — `go/internal/order/store.go`: eliminate the `ListByCustomer` N+1 (Copilot 3439740615)

**B6a — replace the `ListByCustomer` body. Exact old block (lines 133–158):**

```go
func (s *PostgresStore) ListByCustomer(ctx context.Context, customerID string) ([]*Order, error) {
	rows, err := s.pool.Query(ctx, listOrdersByCustomerSQL, customerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	orders := make([]*Order, 0)
	for rows.Next() {
		order, err := scanOrderRow(rows)
		if err != nil {
			return nil, err
		}
		items, err := s.listItems(ctx, order.ID)
		if err != nil {
			return nil, err
		}
		order.Items = items
		order.RecalculateTotals()
		orders = append(orders, order)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return orders, nil
}
```

**Exact new block:**

```go
func (s *PostgresStore) ListByCustomer(ctx context.Context, customerID string) ([]*Order, error) {
	rows, err := s.pool.Query(ctx, listOrdersByCustomerSQL, customerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	orders := make([]*Order, 0)
	orderIDs := make([]uuid.UUID, 0)
	for rows.Next() {
		order, err := scanOrderRow(rows)
		if err != nil {
			return nil, err
		}
		orders = append(orders, order)
		orderIDs = append(orderIDs, order.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}

	itemsByOrder, err := s.listItemsByOrderIDs(ctx, orderIDs)
	if err != nil {
		return nil, err
	}
	for _, order := range orders {
		order.Items = itemsByOrder[order.ID]
		order.RecalculateTotals()
	}
	return orders, nil
}

func (s *PostgresStore) listItemsByOrderIDs(ctx context.Context, orderIDs []uuid.UUID) (map[uuid.UUID][]OrderItem, error) {
	itemsByOrder := make(map[uuid.UUID][]OrderItem)
	if len(orderIDs) == 0 {
		return itemsByOrder, nil
	}
	ids := make([]string, len(orderIDs))
	for i, id := range orderIDs {
		ids[i] = id.String()
	}
	rows, err := s.pool.Query(ctx, listItemsByOrderIDsSQL, ids)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var item OrderItem
		var unitPrice string
		if err := rows.Scan(&item.ID, &item.OrderID, &item.ProductID, &item.ProductName, &item.Quantity, &unitPrice); err != nil {
			return nil, err
		}
		item.UnitPrice, err = decimal.NewFromString(unitPrice)
		if err != nil {
			return nil, err
		}
		item.RecalculateSubtotal()
		itemsByOrder[item.OrderID] = append(itemsByOrder[item.OrderID], item)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return itemsByOrder, nil
}
```

**B6b — add the batched query constant next to `listItemsSQL`. Exact old block (lines 386–391):**

```go
const listItemsSQL = `
SELECT id, order_id, product_id, product_name, quantity, unit_price
FROM order_items
WHERE order_id = $1
ORDER BY id ASC
`
```

**Exact new block:**

```go
const listItemsSQL = `
SELECT id, order_id, product_id, product_name, quantity, unit_price
FROM order_items
WHERE order_id = $1
ORDER BY id ASC
`

const listItemsByOrderIDsSQL = `
SELECT id, order_id, product_id, product_name, quantity, unit_price
FROM order_items
WHERE order_id = ANY($1::uuid[])
ORDER BY id ASC
`
```

> `listItems` (single-order) is still used by `GetByID` — keep it. The `::uuid[]` cast lets us
> pass `[]string` (robust regardless of uuid array codec registration). `GetByID` already returns
> items in `id ASC` order; the batched path preserves that per order.

---

## Rules

- Format: `gofmt -l` must report no files (run `gofmt -w` on changed `.go` files).
- Build: `cd go && go build ./...` and `go vet ./...` clean in BOTH repos.
- Tests: `cd go && go test ./...` green in both repos (unit; the Postgres-gated integration test
  runs in CI). Update any test that referenced removed/renamed symbols
  (`RateLimitPerMinute`, the old mock card literals, the old migration path).
- For k8s manifest edits (A7b/A7c, B5): `kustomize build k8s/base` (or `kubectl kustomize k8s/base`)
  must still render without error.
- `./scripts/k3d-manager _agent_audit` clean (run from k3d-manager) before reporting done.
- Touch ONLY the files listed below. Do NOT change `go/internal/config/config.go:47`
  (order DB_SSLMODE code default — addressed via configmap in B5).

**Payment target files:** `go/internal/gateway/mock.go`, `go/internal/payment/service.go`,
`go/internal/payment/errors.go`, `go/internal/payment/handler.go`, `go/internal/httpx/middleware.go`,
`go/internal/config/config.go`, `go/internal/payment/store.go`, `go/internal/payment/refund.go`,
`k8s/base/configmap.yaml`, `k8s/base/deployment.yaml` (+ any test files referencing changed symbols).

**Order target files:** `go/internal/config/config.go`, `go/internal/events/publisher.go`,
`go/internal/order/store.go`, `CHANGELOG.md`, `go/internal/order/store_integration_test.go`,
`go/internal/order/testdata/V1__init_schema.sql` (moved), `k8s/base/configmap.yaml`.

## Definition of Done

- [ ] Payment: A1–A7 applied; `go build ./...`, `go vet ./...`, `go test ./...` green; `kustomize build k8s/base` renders.
- [ ] Order: B1–B6 applied; `go build ./...`, `go vet ./...`, `go test ./...` green; `kustomize build k8s/base` renders.
- [ ] `git diff --stat` per repo shows only the files listed above.
- [ ] Committed and pushed to `feat/go-rewrite` in BOTH repos.
- [ ] memory-bank (`activeContext.md` + `progress.md`) updated with both commit SHAs and status.

**Commit message (exact, both repos):**
```
fix(go): address Copilot round-2 review findings (PR1 hardening)
```

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside the per-repo target lists.
- Do NOT commit to `main` — work on `feat/go-rewrite`.
- Do NOT change `order go/internal/config/config.go:47` (DB_SSLMODE code default — B5 is configmap-only).
