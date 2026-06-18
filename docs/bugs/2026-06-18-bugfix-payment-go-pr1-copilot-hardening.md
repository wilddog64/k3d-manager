# Bugfix: payment Go PR1 — Copilot review hardening (PR #23)

**Spec repo:** k3d-manager (`k3d-manager-v1.7.1`)
**Work repo:** `shopping-cart-payment`
**Branch (work repo):** `feat/go-rewrite` (the existing PR #23 — do NOT create a new branch)
**Files:** `go/internal/config/config.go`, `go/internal/crypto/encryption.go`,
`go/internal/gateway/gateway.go`, `go/internal/gateway/mock.go`, `go/cmd/server/main.go`,
`go/internal/health/health.go`, `go/internal/payment/store.go`, `go/internal/payment/service.go`,
`go/internal/payment/handler.go`, `go/internal/httpx/middleware.go`,
`go/internal/payment/service_test.go`, `go/internal/payment/integration_test.go`,
`go/internal/gateway/mock_test.go`, `go/internal/crypto/encryption_test.go`

---

## Problem

Copilot's review of PR #23 returned **"⚠️ Not ready to approve"** with 28 inline findings.
Several are genuine security/correctness issues (gateway stubs report success without charging,
encryption silently generates an unrecoverable key, hardcoded credential defaults, no DB
transaction around the multi-write payment flow, full PANs in test source). This spec hardens
PR1 to clear the blocking findings while keeping the Go service contract-compatible with the
Java service (the shared Playwright e2e suite is the acceptance contract).

**Root cause:** PR1 landed a functional core with dev-convenience defaults and stub gateways
that prioritized "looks done" over fail-safe behavior.

---

## Before You Start

- `git pull origin feat/go-rewrite` in `shopping-cart-payment` (PR #23 head).
- Read all 14 target files before editing. Implement exactly what is written.
- Run everything from `shopping-cart-payment/go`.
- **This is a single multi-fix commit.** Partial completion (some files unchanged) = NOT done.

---

## Two findings we are deliberately NOT changing (contract-preserving — do NOT "fix")

1. **`handler.go:56–59` — 201/202 split.** Copilot suggested always 201. **Keep as-is.** The
   Java service returns `201` for a COMPLETED payment and `202` otherwise; the e2e acceptance
   contract depends on this. Changing it diverges the contract. Leave lines 56–59 untouched.
2. **Requiring an idempotency key on every request** (Copilot on `handler.go:49`). **Do NOT make
   it mandatory.** The Java contract treats the idempotency key as optional and already guards
   double-charge by `orderId` (`service.go:40–46`). We close the real gap via the **unique-key
   race fix in Change 8** instead. Do not add a 400-on-missing-key.

---

## Fix

### Change 1 — `config.go`: remove hardcoded credential/secret defaults, disable external gateways by default, make sslmode configurable

**Exact old block (lines 59–96):**

```go
		DBHost:     stringEnv("DB_HOST", "localhost"),
		DBPort:     intEnv("DB_PORT", 5432),
		DBName:     stringEnv("DB_NAME", "payments"),
		DBUsername: stringEnv("DB_USERNAME", "postgres"),
		DBPassword: stringEnv("DB_PASSWORD", "changeme123"),

		RabbitMQHost:         stringEnv("RABBITMQ_HOST", "rabbitmq.shopping-cart-data.svc.cluster.local"),
		RabbitMQPort:         intEnv("RABBITMQ_PORT", 5672),
		RabbitMQVHost:        stringEnv("RABBITMQ_VHOST", "/"),
		RabbitMQUsername:     stringEnv("RABBITMQ_USERNAME", "guest"),
		RabbitMQPassword:     stringEnv("RABBITMQ_PASSWORD", "guest"),
		RabbitMQVaultEnabled: boolEnv("RABBITMQ_VAULT_ENABLED", false),

		PaymentGatewayDefault: stringEnv("PAYMENT_GATEWAY_DEFAULT", "mock"),

		StripeEnabled:       boolEnv("STRIPE_ENABLED", true),
		StripeAPIKey:        stringEnv("STRIPE_API_KEY", "sk_test_xxx"),
		StripeWebhookSecret: stringEnv("STRIPE_WEBHOOK_SECRET", "whsec_xxx"),

		PayPalEnabled:      boolEnv("PAYPAL_ENABLED", true),
		PayPalClientID:     stringEnv("PAYPAL_CLIENT_ID", "xxx"),
		PayPalClientSecret: stringEnv("PAYPAL_CLIENT_SECRET", "xxx"),
		PayPalMode:         stringEnv("PAYPAL_MODE", "sandbox"),

		MockGatewayDelayMS:     intEnv("MOCK_GATEWAY_DELAY_MS", 500),
		MockGatewayFailureRate: floatEnv("MOCK_GATEWAY_FAILURE_RATE", 0.0),
```

**Exact new block:**

```go
		DBHost:     stringEnv("DB_HOST", "localhost"),
		DBPort:     intEnv("DB_PORT", 5432),
		DBName:     stringEnv("DB_NAME", "payments"),
		DBUsername: stringEnv("DB_USERNAME", "postgres"),
		DBPassword: stringEnv("DB_PASSWORD", ""),
		DBSSLMode:  stringEnv("DB_SSLMODE", "disable"),

		RabbitMQHost:         stringEnv("RABBITMQ_HOST", "rabbitmq.shopping-cart-data.svc.cluster.local"),
		RabbitMQPort:         intEnv("RABBITMQ_PORT", 5672),
		RabbitMQVHost:        stringEnv("RABBITMQ_VHOST", "/"),
		RabbitMQUsername:     stringEnv("RABBITMQ_USERNAME", ""),
		RabbitMQPassword:     stringEnv("RABBITMQ_PASSWORD", ""),
		RabbitMQVaultEnabled: boolEnv("RABBITMQ_VAULT_ENABLED", false),

		PaymentGatewayDefault: stringEnv("PAYMENT_GATEWAY_DEFAULT", "mock"),

		MockGatewayEnabled:  boolEnv("MOCK_GATEWAY_ENABLED", true),

		StripeEnabled:       boolEnv("STRIPE_ENABLED", false),
		StripeAPIKey:        stringEnv("STRIPE_API_KEY", ""),
		StripeWebhookSecret: stringEnv("STRIPE_WEBHOOK_SECRET", ""),

		PayPalEnabled:      boolEnv("PAYPAL_ENABLED", false),
		PayPalClientID:     stringEnv("PAYPAL_CLIENT_ID", ""),
		PayPalClientSecret: stringEnv("PAYPAL_CLIENT_SECRET", ""),
		PayPalMode:         stringEnv("PAYPAL_MODE", "sandbox"),

		MockGatewayDelayMS:     intEnv("MOCK_GATEWAY_DELAY_MS", 500),
		MockGatewayFailureRate: floatEnv("MOCK_GATEWAY_FAILURE_RATE", 0.0),
```

Add the two new struct fields. **Exact old block (lines 13–38):**

```go
	DBHost     string
	DBPort     int
	DBName     string
	DBUsername string
	DBPassword string

	RabbitMQHost         string
	RabbitMQPort         int
	RabbitMQVHost        string
	RabbitMQUsername     string
	RabbitMQPassword     string
	RabbitMQVaultEnabled bool

	PaymentGatewayDefault string

	StripeEnabled       bool
```

**Exact new block:**

```go
	DBHost     string
	DBPort     int
	DBName     string
	DBUsername string
	DBPassword string
	DBSSLMode  string

	RabbitMQHost         string
	RabbitMQPort         int
	RabbitMQVHost        string
	RabbitMQUsername     string
	RabbitMQPassword     string
	RabbitMQVaultEnabled bool

	PaymentGatewayDefault string

	MockGatewayEnabled bool

	StripeEnabled       bool
```

### Change 2 — `config.go`: `DatabaseURI()` uses the configurable sslmode

**Exact old block (lines 102–110):**

```go
func (c Config) DatabaseURI() string {
	return fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=disable",
		url.QueryEscape(c.DBUsername),
		url.QueryEscape(c.DBPassword),
		c.DBHost,
		c.DBPort,
		c.DBName,
	)
}
```

**Exact new block:**

```go
func (c Config) DatabaseURI() string {
	sslMode := c.DBSSLMode
	if sslMode == "" {
		sslMode = "disable"
	}
	return fmt.Sprintf("postgres://%s:%s@%s:%d/%s?sslmode=%s",
		url.QueryEscape(c.DBUsername),
		url.QueryEscape(c.DBPassword),
		c.DBHost,
		c.DBPort,
		c.DBName,
		url.QueryEscape(sslMode),
	)
}
```

> Rationale: `sslmode` is no longer hardcoded — it defaults to `disable` (required for local dev
> and in-cluster Postgres without TLS) but can be set to `require`/`verify-full` in production via
> `DB_SSLMODE`. This addresses Copilot's "easy to run without TLS" while keeping dev working.

### Change 3 — `encryption.go`: fail fast on empty/invalid key instead of generating a random one

**Exact old block (lines 25–44):**

```go
func NewEncryptionService(enabled bool, keyMaterial string) (*EncryptionService, error) {
	svc := &EncryptionService{enabled: enabled}
	if !enabled {
		return svc, nil
	}
	if keyMaterial == "" {
		key := make([]byte, 32)
		if _, err := io.ReadFull(rand.Reader, key); err != nil {
			return nil, err
		}
		svc.key = key
		return svc, nil
	}
	key, err := decodeKey(keyMaterial)
	if err != nil {
		return nil, err
	}
	svc.key = key
	return svc, nil
}
```

**Exact new block:**

```go
func NewEncryptionService(enabled bool, keyMaterial string) (*EncryptionService, error) {
	svc := &EncryptionService{enabled: enabled}
	if !enabled {
		return svc, nil
	}
	if keyMaterial == "" {
		return nil, errors.New("encryption enabled but ENCRYPTION_KEY is empty")
	}
	key, err := decodeKey(keyMaterial)
	if err != nil {
		return nil, err
	}
	if len(key) != 32 {
		return nil, errors.New("encryption key must be 32 bytes (AES-256)")
	}
	svc.key = key
	return svc, nil
}
```

The `io` import is now unused — remove `"io"` from the import block **only if** no other use
remains (it is still used by `Encrypt` for the nonce, so KEEP `"io"`). Verify with `goimports`/
`go build`. `rand` is still used by `Encrypt`. Do not remove imports that are still referenced.

### Change 4 — `encryption.go`: gate `Encrypt`/`Decrypt` on `IsEnabled()` not `enabled`

**Exact old block (line 61):**

```go
	if !s.enabled || plaintext == "" {
```

**Exact new block:**

```go
	if !s.IsEnabled() || plaintext == "" {
```

**Exact old block (line 84):**

```go
	if !s.enabled || ciphertext == "" {
```

**Exact new block:**

```go
	if !s.IsEnabled() || ciphertext == "" {
```

### Change 5 — `gateway.go`: remove the silent fallback to `mock`

**Exact old block (lines 35–38):**

```go
	if _, ok := router.gateways[strings.ToLower(router.defaultGatewayName)]; !ok {
		router.defaultGatewayName = "mock"
	}
	return router
```

**Exact new block:**

```go
	return router
```

> With the silent reassignment gone, `GetDefaultGateway()` → `GetGateway()` already returns an
> explicit `unknown gateway: <name>` / `gateway is not enabled: <name>` error when the configured
> default is absent or disabled, instead of routing real traffic to the mock.

### Change 6 — `mock.go`: Stripe and PayPal stubs fail fast (deferred to PR2, must not report success)

**Exact old block (lines 125–136 — `StripeGateway.ProcessPayment`):**

```go
func (g *StripeGateway) ProcessPayment(request PaymentRequest) PaymentResult {
	if !g.IsEnabled() {
		return PaymentResultFailure("gateway_disabled", "Stripe gateway is not enabled")
	}
	return PaymentResult{
		Success:         true,
		TransactionID:   "stripe_txn_" + uuid.NewString()[:16],
		PaymentIntentID: "stripe_pi_" + uuid.NewString()[:16],
		Status:          "completed",
		RawResponse:     "",
	}
}
```

**Exact new block:**

```go
func (g *StripeGateway) ProcessPayment(request PaymentRequest) PaymentResult {
	if !g.IsEnabled() {
		return PaymentResultFailure("gateway_disabled", "Stripe gateway is not enabled")
	}
	return PaymentResultFailure("not_implemented", "Stripe gateway is not implemented yet (deferred to PR2)")
}
```

**Exact old block (lines 138–143 — `StripeGateway.ProcessRefund`):**

```go
func (g *StripeGateway) ProcessRefund(request RefundRequest) RefundResult {
	if !g.IsEnabled() {
		return RefundResultFailure("gateway_disabled", "Stripe gateway is not enabled")
	}
	return RefundResult{Success: true, RefundID: "stripe_re_" + uuid.NewString()[:16], Status: "completed"}
}
```

**Exact new block:**

```go
func (g *StripeGateway) ProcessRefund(request RefundRequest) RefundResult {
	if !g.IsEnabled() {
		return RefundResultFailure("gateway_disabled", "Stripe gateway is not enabled")
	}
	return RefundResultFailure("not_implemented", "Stripe gateway is not implemented yet (deferred to PR2)")
}
```

**Exact old block (lines 164–175 — `PayPalGateway.ProcessPayment`):**

```go
func (g *PayPalGateway) ProcessPayment(request PaymentRequest) PaymentResult {
	if !g.IsEnabled() {
		return PaymentResultFailure("gateway_disabled", "PayPal gateway is not enabled")
	}
	return PaymentResult{
		Success:         true,
		TransactionID:   "paypal_txn_" + uuid.NewString()[:16],
		PaymentIntentID: "paypal_order_" + uuid.NewString()[:16],
		Status:          "completed",
		RawResponse:     "",
	}
}
```

**Exact new block:**

```go
func (g *PayPalGateway) ProcessPayment(request PaymentRequest) PaymentResult {
	if !g.IsEnabled() {
		return PaymentResultFailure("gateway_disabled", "PayPal gateway is not enabled")
	}
	return PaymentResultFailure("not_implemented", "PayPal gateway is not implemented yet (deferred to PR2)")
}
```

**Exact old block (lines 177–182 — `PayPalGateway.ProcessRefund`):**

```go
func (g *PayPalGateway) ProcessRefund(request RefundRequest) RefundResult {
	if !g.IsEnabled() {
		return RefundResultFailure("gateway_disabled", "PayPal gateway is not enabled")
	}
	return RefundResult{Success: true, RefundID: "paypal_re_" + uuid.NewString()[:16], Status: "completed"}
}
```

**Exact new block:**

```go
func (g *PayPalGateway) ProcessRefund(request RefundRequest) RefundResult {
	if !g.IsEnabled() {
		return RefundResultFailure("gateway_disabled", "PayPal gateway is not enabled")
	}
	return RefundResultFailure("not_implemented", "PayPal gateway is not implemented yet (deferred to PR2)")
}
```

> Leave `Tokenize`/`DeleteToken` for Stripe/PayPal as-is (not exercised by PR1 flow). If `uuid`
> becomes unused in `mock.go` after these edits, the `Tokenize` methods still reference it — keep
> the import. Verify with `go build`.

### Change 7 — `main.go`: gate the mock gateway behind config

**Exact old block (line 46):**

```go
	mockGateway := gateway.NewMockGateway(true, cfg.MockGatewayDelayMS, cfg.MockGatewayFailureRate)
```

**Exact new block:**

```go
	mockGateway := gateway.NewMockGateway(cfg.MockGatewayEnabled, cfg.MockGatewayDelayMS, cfg.MockGatewayFailureRate)
```

### Change 8 — `service.go`: handle the idempotency-key unique-violation race

When two concurrent requests share an idempotency key, both can pass the pre-check at lines
32–38 and one hits the `payments.idempotency_key` unique constraint. Return the existing row
instead of a generic error.

**Exact old block (lines 69–71):**

```go
	if err := s.store.CreatePayment(ctx, payment); err != nil {
		return nil, err
	}
```

**Exact new block:**

```go
	if err := s.store.CreatePayment(ctx, payment); err != nil {
		if isUniqueViolation(err) && strings.TrimSpace(idempotencyKey) != "" {
			if existing, getErr := s.store.GetPaymentByIdempotencyKey(ctx, idempotencyKey); getErr == nil {
				return existing, nil
			}
		}
		return nil, err
	}
```

Add the helper at the end of `service.go` (after `decimalCmpPositive`):

```go
func isUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "23505"
	}
	return false
}
```

Add `"github.com/jackc/pgx/v5/pgconn"` to the `service.go` import block. `errors` is already
imported. Confirm `github.com/jackc/pgx/v5` is already a dependency (it is — `go.mod` has it).

### Change 9 — `health.go`: readiness probe uses the request context

**Exact old block (line 37):**

```go
	if err := h.DB.Ping(context.Background()); err != nil {
```

**Exact new block:**

```go
	if err := h.DB.Ping(c.Request.Context()); err != nil {
```

If `context` becomes unused after this edit, remove `"context"` from the `health.go` import
block (verify with `go build`).

### Change 10 — `store.go`: return an error on invalid `payment_method_id` instead of dropping it

**Exact old block (the `scanPaymentRow` block around lines 453–458):**

```go
	paymentMethodID := uuid.NullUUID{}
	if paymentMethodIDText.Valid {
		if parsed, err := uuid.Parse(paymentMethodIDText.String); err == nil {
			paymentMethodID = uuid.NullUUID{UUID: parsed, Valid: true}
		}
	}
```

**Exact new block:**

```go
	paymentMethodID := uuid.NullUUID{}
	if paymentMethodIDText.Valid {
		parsed, err := uuid.Parse(paymentMethodIDText.String)
		if err != nil {
			return nil, fmt.Errorf("parse payment_method_id: %w", err)
		}
		paymentMethodID = uuid.NullUUID{UUID: parsed, Valid: true}
	}
```

`fmt` is already imported in `store.go` (used by the amount-parse error just above). Do not
touch the input-side parse in `service.go:48–51` (optional request field — Copilot only flagged
the DB read path).

### Change 11 — `middleware.go`: bound the rate-limiter map with last-seen eviction

Replace the unbounded `map[string]*rate.Limiter` with per-IP entries that carry a `lastSeen`
timestamp, and run a background janitor that evicts entries idle longer than a TTL.

**Exact old block (lines 39–81):**

```go
type limiter struct {
	mu       sync.Mutex
	enabled  bool
	limiters map[string]*rate.Limiter
	limit    rate.Limit
	burst    int
}

func NewRateLimiter(enabled bool, perSecond, burst int) gin.HandlerFunc {
	l := &limiter{
		enabled:  enabled,
		limiters: map[string]*rate.Limiter{},
		limit:    rate.Limit(perSecond),
		burst:    burst,
	}
	return func(c *gin.Context) {
		if !l.enabled || strings.HasPrefix(c.FullPath(), "/actuator/") {
			c.Next()
			return
		}
		ip := c.ClientIP()
		rl := l.getLimiter(ip)
		if !rl.Allow() {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"code":    "RATE_LIMIT_EXCEEDED",
				"message": fmt.Sprintf("rate limit exceeded for %s", ip),
			})
			return
		}
		c.Next()
	}
}

func (l *limiter) getLimiter(ip string) *rate.Limiter {
	l.mu.Lock()
	defer l.mu.Unlock()
	rl, ok := l.limiters[ip]
	if !ok {
		rl = rate.NewLimiter(l.limit, l.burst)
		l.limiters[ip] = rl
	}
	return rl
}
```

**Exact new block:**

```go
const (
	rateLimiterEntryTTL     = 10 * time.Minute
	rateLimiterSweepEvery   = 1 * time.Minute
)

type limiterEntry struct {
	limiter  *rate.Limiter
	lastSeen time.Time
}

type limiter struct {
	mu       sync.Mutex
	enabled  bool
	limiters map[string]*limiterEntry
	limit    rate.Limit
	burst    int
}

func NewRateLimiter(enabled bool, perSecond, burst int) gin.HandlerFunc {
	l := &limiter{
		enabled:  enabled,
		limiters: map[string]*limiterEntry{},
		limit:    rate.Limit(perSecond),
		burst:    burst,
	}
	if enabled {
		go l.sweep()
	}
	return func(c *gin.Context) {
		if !l.enabled || strings.HasPrefix(c.FullPath(), "/actuator/") {
			c.Next()
			return
		}
		ip := c.ClientIP()
		rl := l.getLimiter(ip)
		if !rl.Allow() {
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"code":    "RATE_LIMIT_EXCEEDED",
				"message": fmt.Sprintf("rate limit exceeded for %s", ip),
			})
			return
		}
		c.Next()
	}
}

func (l *limiter) getLimiter(ip string) *rate.Limiter {
	l.mu.Lock()
	defer l.mu.Unlock()
	entry, ok := l.limiters[ip]
	if !ok {
		entry = &limiterEntry{limiter: rate.NewLimiter(l.limit, l.burst)}
		l.limiters[ip] = entry
	}
	entry.lastSeen = time.Now()
	return entry.limiter
}

func (l *limiter) sweep() {
	ticker := time.NewTicker(rateLimiterSweepEvery)
	defer ticker.Stop()
	for range ticker.C {
		cutoff := time.Now().Add(-rateLimiterEntryTTL)
		l.mu.Lock()
		for ip, entry := range l.limiters {
			if entry.lastSeen.Before(cutoff) {
				delete(l.limiters, ip)
			}
		}
		l.mu.Unlock()
	}
}
```

`time` is already imported in `middleware.go` (used by `RequestLogger`). Run `gofmt` —
the const block alignment will be normalized.

### Change 12 — `handler.go`: validate the 4-decimal amount scale at the API boundary

**Exact old block (lines 194–214):**

```go
func validateProcessPaymentRequest(req ProcessPaymentRequest) *APIError {
	switch {
	case strings.TrimSpace(req.OrderID) == "":
		return BadRequest("ORDER_ID_REQUIRED", "Order ID is required")
	case strings.TrimSpace(req.CustomerID) == "":
		return BadRequest("CUSTOMER_ID_REQUIRED", "Customer ID is required")
	case !decimalCmpPositive(req.Amount):
		return BadRequest("AMOUNT_INVALID", "Amount must be greater than 0")
	case len(strings.TrimSpace(req.Currency)) != 3:
		return BadRequest("CURRENCY_INVALID", "Currency must be 3 characters")
	default:
		return nil
	}
}

func validateRefundRequest(req RefundRequest) *APIError {
	if !decimalCmpPositive(req.Amount) {
		return BadRequest("AMOUNT_INVALID", "Amount must be greater than 0")
	}
	return nil
}
```

**Exact new block:**

```go
func validateProcessPaymentRequest(req ProcessPaymentRequest) *APIError {
	switch {
	case strings.TrimSpace(req.OrderID) == "":
		return BadRequest("ORDER_ID_REQUIRED", "Order ID is required")
	case strings.TrimSpace(req.CustomerID) == "":
		return BadRequest("CUSTOMER_ID_REQUIRED", "Customer ID is required")
	case !decimalCmpPositive(req.Amount):
		return BadRequest("AMOUNT_INVALID", "Amount must be greater than 0")
	case req.Amount.Exponent() < -4:
		return BadRequest("AMOUNT_SCALE_INVALID", "Amount supports at most 4 decimal places")
	case len(strings.TrimSpace(req.Currency)) != 3:
		return BadRequest("CURRENCY_INVALID", "Currency must be 3 characters")
	default:
		return nil
	}
}

func validateRefundRequest(req RefundRequest) *APIError {
	if !decimalCmpPositive(req.Amount) {
		return BadRequest("AMOUNT_INVALID", "Amount must be greater than 0")
	}
	if req.Amount.Exponent() < -4 {
		return BadRequest("AMOUNT_SCALE_INVALID", "Amount supports at most 4 decimal places")
	}
	return nil
}
```

> `decimal.Decimal.Exponent()` returns the base-10 exponent; a value with 5+ decimal places has
> exponent `< -4`. This rejects over-scale input before Postgres silently rounds it.

### Change 13 — wrap the payment state changes + audit insert in a single DB transaction

This is the one structural change. Today `ProcessPayment` (`service.go:69–136`) performs
`CreatePayment` → `UpdatePayment` (processing) → `CreateTransaction` → `UpdatePayment`
(terminal) as four independent writes on the pool; a crash mid-flight leaves inconsistent state.

**Required behavior:** the create + status updates + audit `CreateTransaction` for a single
`ProcessPayment` call must commit atomically (all-or-nothing).

**Recommended approach (do not over-engineer):**

- Add a transaction-capable path on the store. The store already holds a `*pgxpool.Pool`
  (`payment.NewStore(db)`); `pgxpool.Pool`, `pgx.Tx`, and `pgx.Conn` all satisfy the small
  `pgx` querier interface (`Exec`/`Query`/`QueryRow`). Refactor the store's write methods
  (`CreatePayment`, `UpdatePayment`, `CreateTransaction`) to run against a
  `DBTX` interface (`Exec(ctx, sql, args...) (pgconn.CommandTag, error)` etc.) rather than the
  concrete pool, and add a `RunInTx(ctx, func(tx) error) error` helper that `Begin`s on the pool,
  passes a tx-bound store/querier to the callback, and commits or rolls back.
- In `ProcessPayment`, wrap the create→update→audit→update sequence in `store.RunInTx`. The
  gateway call (`gatewayImpl.ProcessPayment`) is a network/CPU op with no DB handle — call it
  **before** `BEGIN` or capture its result and keep the tx span tight; do NOT hold the
  transaction open across a slow external gateway call. Recommended ordering: create+mark
  processing in tx 1 (or before), call the gateway outside any tx, then commit the audit row +
  terminal status update in a single tx.

**Acceptance for Change 13:** a new or updated integration test must prove atomicity — e.g.
inject a failing `CreateTransaction` (or terminal `UpdatePayment`) and assert the payment row
is NOT left in `PROCESSING` without its audit/terminal state (the prior writes roll back). If a
faithful failure-injection is impractical against the live schema, at minimum assert the happy
path still persists exactly one payment + the expected transactions inside one committed tx, and
document in the commit body that full rollback-injection coverage is deferred.

> If the transactional store refactor balloons beyond a focused change, STOP and report back
> rather than half-applying it — a partially-transactional store is worse than the current state.

### Change 14 — strip full PAN/CVV literals from test source (PCI hygiene)

Replace every full-PAN test literal `"4242424242424242"` with a non-PAN token that still ends in
`4242` so `last4` assertions keep working: use **`"tok_test_4242"`**. Replace CVV literals
(`"123"`) with a non-CVV placeholder: use **`"test-cvc"`**.

Apply in all four files:

- `go/internal/payment/service_test.go` — line 23 `CardNumber: "4242424242424242"` →
  `CardNumber: "tok_test_4242"`; line 26 `CardCvc: "123"` → `CardCvc: "test-cvc"`; line 84
  `CardNumber: "4242424242424242"` → `CardNumber: "tok_test_4242"`.
- `go/internal/payment/integration_test.go` — line 59 `CardNumber: "4242424242424242"` →
  `CardNumber: "tok_test_4242"`.
- `go/internal/gateway/mock_test.go` — line 17 `CardNumber: "4242424242424242"` →
  `CardNumber: "tok_test_4242"`.
- `go/internal/crypto/encryption_test.go` — line 19 `pan := "4242424242424242"` →
  `pan := "tok_test_4242"`; line 20 `cvv := "123"` → `cvv := "test-cvc"`.

After replacing, confirm any test asserting `CardLast4 == "4242"` still passes (the new value
ends in `4242`). Do NOT touch the decline-trigger constants inside `mock.go` (`4000000000000002`,
`4000000000009995`) — those are behavior sentinels, not stored card data, and were not flagged.

---

## Files Changed

| File | Change |
|------|--------|
| `config.go` | 1, 2 — drop hardcoded secret defaults; disable Stripe/PayPal by default; `MockGatewayEnabled` + configurable `DB_SSLMODE` |
| `crypto/encryption.go` | 3, 4 — fail fast on empty/invalid key; gate on `IsEnabled()` |
| `gateway/gateway.go` | 5 — remove silent mock fallback |
| `gateway/mock.go` | 6 — Stripe/PayPal stubs fail fast (`not_implemented`) |
| `cmd/server/main.go` | 7 — mock gateway gated behind config |
| `payment/service.go` | 8, 13 — idempotency unique-violation race; transactional payment flow |
| `health/health.go` | 9 — readiness uses request context |
| `payment/store.go` | 10, 13 — error on bad `payment_method_id`; tx-capable writes |
| `httpx/middleware.go` | 11 — bounded rate-limiter map with eviction |
| `payment/handler.go` | 12 — 4-decimal scale validation |
| `payment/service_test.go`, `integration_test.go`, `gateway/mock_test.go`, `crypto/encryption_test.go` | 14 — remove full PAN/CVV literals |

Also create, in the **work repo**, `docs/issues/2026-06-18-copilot-pr23-review-findings.md`
documenting which findings were fixed and the two deliberately-not-changed (201/202 split,
optional idempotency key) with the contract rationale.

---

## Rules

- Edit ONLY the files listed above (+ the work-repo `docs/issues/` findings doc). Do NOT touch
  the Java tree (`src/**`, `pom.xml`, root `Dockerfile`, `db/migration/**`) or `go-ci.yml`.
- Preserve the Java contract: do NOT change the 201/202 split or make idempotency mandatory.
- `gofmt -l .` clean; `go vet ./...` clean; `golangci-lint run` clean (no new findings; remove
  any imports left unused by your edits, keep ones still referenced).
- `go test ./... -race -cover` green (unit) AND `go test -tags integration -count=1 ./internal/payment/...`
  green against a real Postgres with the Flyway schema. Update any unit/integration test that the
  new fail-fast gateway behavior or scale validation legitimately changes.
- New env vars (`DB_SSLMODE`, `MOCK_GATEWAY_ENABLED`) need no secret handling — they are not
  sensitive flags.
- Run `./scripts/k3d-manager _agent_audit` before reporting done.

---

## Definition of Done

- [ ] All 14 changes applied; no file outside the target list (+ work-repo issues doc) touched
- [ ] Stripe/PayPal `ProcessPayment`/`ProcessRefund` return `not_implemented` failure when enabled
- [ ] Encryption constructor returns an error (no random key) when enabled with empty/!=32-byte key
- [ ] No hardcoded credential/secret defaults remain in `config.go`; Stripe/PayPal default disabled
- [ ] Idempotency unique-violation returns the existing payment; payment flow is transactional
- [ ] `gofmt`/`go vet`/`golangci-lint` clean; unit + integration tests green
- [ ] `./scripts/k3d-manager _agent_audit` clean
- [ ] Work-repo `docs/issues/2026-06-18-copilot-pr23-review-findings.md` created
- [ ] Committed and pushed to `feat/go-rewrite`; the PR #23 `go` + `integration` CI jobs are green
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(payment): harden Go PR1 per Copilot review (gateways, crypto, config, tx)

Address the blocking PR #23 review findings: Stripe/PayPal stubs fail fast
instead of reporting success, encryption fails fast on a missing/invalid
key, remove hardcoded credential defaults and disable external gateways by
default, handle the idempotency-key unique-violation race, run the payment
state changes + audit insert in a single transaction, bound the rate-limiter
map, validate 4-decimal amount scale, and remove full PAN/CVV literals from
tests. The 201/202 status split and optional idempotency key are preserved
to keep the Java/e2e contract.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

---

## What NOT to Do

- Do NOT create a new PR (PR #23 already exists) or a new branch
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file outside the listed targets (+ work-repo issues doc)
- Do NOT change the 201/202 split or make the idempotency key mandatory
- Do NOT touch the Java tree, `go-ci.yml`, or `db/migration/**`
- Do NOT commit to `main` — work on `feat/go-rewrite`
- If Change 13 (transactional refactor) grows beyond a focused change, STOP and report rather
  than half-applying it
