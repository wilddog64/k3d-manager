# Bugfix: Go rewrite PR1 — Copilot round-4 hardening (payment #23)

**Work repo:** `shopping-cart-payment` — branch `feat/go-rewrite` (continue the existing branch; do
NOT branch anew, do NOT open a PR — #23 is already open against this branch).
**Spec lives in:** `k3d-manager` (`k3d-manager-v1.7.1`) — this file only.
**Type:** Follow-up to `docs/bugs/2026-06-18-bugfix-copilot-pr-round2-hardening.md`. Closes the
round-4 Copilot findings on payment #23.

---

## Problem

Copilot posted a 4th review on payment #23 (2026-06-19T11:33, HEAD `0fda755`) with 7 inline findings.
Five are real code/config issues fixed by this spec; one is outdated; one is a style split deferred
to PR2.

| # | File:line | Finding | Disposition |
|---|-----------|---------|-------------|
| 1 | `service.go:79` | `strings.ToUpper(req.Currency)` stored/forwarded without `TrimSpace`; `" usd"` passes validation but is stored/sent as `" USD"` | **FIX (R1)** |
| 2 | `store.go:73` | `RunInTx` returns only the rollback error and drops the original business failure cause | **FIX (R2)** |
| 3 | `refund.go:114` | `gatewayRequest` built from the non-locked read; gateway IDs should come from the `FOR UPDATE` row | **FIX (R3)** |
| 4 | `service.go:99` | Raw card fields (esp. `CardCVC`) held in `request` past the gateway call, during DB writes | **FIX (R4)** |
| 5 | `deployment.yaml:97` | DB_SSLMODE not wired into the Deployment (description mismatch) | **FIX (R5)** — wired by R5/R6; Claude resolves (outdated anchor) |
| 6 | `configmap.yaml:20` | add a `db.sslmode` key so the Deployment can source `DB_SSLMODE` | **FIX (R6)** |
| 7 | `mock.go:185` | Mock/Stripe/PayPal in one file; split per provider | **DEFER to PR2** — Stripe/PayPal are PR1 stubs; Claude replies + resolves with rationale (split when real gateway logic lands) |

---

## Before You Start

1. `git pull origin k3d-manager-v1.7.1` in k3d-manager and read this spec in full.
2. In `shopping-cart-payment`: `git fetch origin && git checkout feat/go-rewrite && git pull origin
   feat/go-rewrite` (you are extending HEAD `0fda755`, not starting over).
3. Read these files before editing: `go/internal/payment/service.go`,
   `go/internal/payment/refund.go`, `go/internal/payment/store.go`,
   `go/internal/gateway/dto.go`, `k8s/base/configmap.yaml`, `k8s/base/deployment.yaml`.
4. Use the exact old/new blocks below — no interpretation. Run all gates in `## Rules` before commit.

---

## R1 — `service.go`: trim currency once, use a single normalized value (Copilot K0b0N)

`req.Currency` is validated with `TrimSpace` but stored/forwarded as `strings.ToUpper(req.Currency)`
in **two** places, so `" usd"` is persisted/sent as `" USD"`. Normalize once and reuse.

**Exact old block (payment struct):**

```go
	now := time.Now().UTC()
	payment := &Payment{
		ID:              uuid.New(),
		OrderID:         req.OrderID,
		CustomerID:      req.CustomerID,
		Amount:          req.Amount,
		Currency:        strings.ToUpper(req.Currency),
		Status:          PaymentStatusPending,
```

**Exact new block:**

```go
	now := time.Now().UTC()
	currency := strings.ToUpper(strings.TrimSpace(req.Currency))
	payment := &Payment{
		ID:              uuid.New(),
		OrderID:         req.OrderID,
		CustomerID:      req.CustomerID,
		Amount:          req.Amount,
		Currency:        currency,
		Status:          PaymentStatusPending,
```

**Exact old block (gateway request struct):**

```go
		Amount:              req.Amount,
		Currency:            strings.ToUpper(req.Currency),
		PaymentMethodToken:  req.PaymentMethodID,
```

**Exact new block:**

```go
		Amount:              req.Amount,
		Currency:            currency,
		PaymentMethodToken:  req.PaymentMethodID,
```

---

## R2 — `store.go`: preserve the original cause when rollback also fails (Copilot K0b1J)

`fmt` is already imported in `store.go`.

**Exact old block:**

```go
	if err := fn(txStore); err != nil {
		if rbErr := tx.Rollback(ctx); rbErr != nil {
			return rbErr
		}
		return err
	}
```

**Exact new block:**

```go
	if err := fn(txStore); err != nil {
		if rbErr := tx.Rollback(ctx); rbErr != nil {
			return fmt.Errorf("%w (additionally, rollback failed: %v)", err, rbErr)
		}
		return err
	}
```

---

## R3 — `refund.go`: source gateway identifiers from the locked row (Copilot K0b0r)

Build `gatewayRequest` **inside** the tx from `locked` (the `FOR UPDATE` row), immediately before the
gateway call — not from the earlier non-locked `payment` read.

**Exact old block — DELETE the pre-tx construction:**

```go
	gatewayRequest := gateway.RefundRequest{
		PaymentTransactionID: payment.GatewayTransactionID.String,
		PaymentIntentID:      payment.GatewayPaymentIntentID.String,
		Amount:               amount,
		Currency:             payment.Currency,
		Reason:               reason,
		CorrelationID:        correlationID,
	}

	persist := func(store paymentStore) error {
```

**Exact new block (the `gatewayRequest` block is removed; `persist` now follows the `refund` struct directly):**

```go
	persist := func(store paymentStore) error {
```

**Exact old block — the gateway call inside `persist`:**

```go
		refund.Status = RefundStatusProcessing
		refund.ProcessedAt = sql.NullTime{Time: time.Now().UTC(), Valid: true}
		if err := store.UpdateRefund(ctx, refund); err != nil {
			return err
		}

		result := gatewayImpl.ProcessRefund(gatewayRequest)
```

**Exact new block (construct `gatewayRequest` from `locked`):**

```go
		refund.Status = RefundStatusProcessing
		refund.ProcessedAt = sql.NullTime{Time: time.Now().UTC(), Valid: true}
		if err := store.UpdateRefund(ctx, refund); err != nil {
			return err
		}

		gatewayRequest := gateway.RefundRequest{
			PaymentTransactionID: locked.GatewayTransactionID.String,
			PaymentIntentID:      locked.GatewayPaymentIntentID.String,
			Amount:               amount,
			Currency:             locked.Currency,
			Reason:               reason,
			CorrelationID:        correlationID,
		}
		result := gatewayImpl.ProcessRefund(gatewayRequest)
```

> Note: `locked` is already in scope inside `persist` (`locked, err := store.GetPaymentForUpdate(...)`).
> After this change the outer `payment` read is still used for the pre-tx status guard and for
> building the `refund` struct — leave those as-is.

---

## R4 — `service.go`: zero raw card fields after the gateway call (Copilot K0bzw, PCI)

All card fields on `gateway.PaymentRequest` are `string` (confirmed in `dto.go`). Nothing reads
`request` after the gateway call (the `persist` closure uses `result`/`payment`/`correlationID`/`now`,
not `request`), so zeroing is safe and minimizes retention during DB/audit writes.

**Exact old block:**

```go
	result := gatewayImpl.ProcessPayment(request)
	persist := func(store paymentStore) error {
```

**Exact new block:**

```go
	result := gatewayImpl.ProcessPayment(request)
	request.CardNumber = ""
	request.CardCVC = ""
	request.CardExpMonth = ""
	request.CardExpYear = ""
	persist := func(store paymentStore) error {
```

---

## R6 — `k8s/base/configmap.yaml`: add a `db.sslmode` key (Copilot K0b1v)

**Exact old block:**

```yaml
  # Payment Gateway Configuration
  payment.gateway.default: "mock"
  mock.gateway.enabled: "true"
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

  # Database
  # in-cluster Postgres has no native TLS; transport is secured by Istio mTLS (dev)
  db.sslmode: "disable"
```

---

## R5 — `k8s/base/deployment.yaml`: wire `DB_SSLMODE` from the ConfigMap (Copilot K0b1g)

Source `DB_SSLMODE` from the new `db.sslmode` ConfigMap key, alongside the other DB env vars.

**Exact old block:**

```yaml
        - name: DB_NAME
          value: "payments"
        - name: DB_USERNAME
```

**Exact new block:**

```yaml
        - name: DB_NAME
          value: "payments"
        - name: DB_SSLMODE
          valueFrom:
            configMapKeyRef:
              name: payment-service-config
              key: db.sslmode
        - name: DB_USERNAME
```

---

## Out of scope (do NOT touch)

- Finding #7 (`mock.go` per-provider file split) — **deferred to PR2**; Claude handles the thread
  reply + resolve. Do NOT split `mock.go` in this round.
- Java tree (`src/**`, `pom.xml`, root `Dockerfile`, `db/migration/**`, Java `ci.yml`); all other
  services; the e2e suite; k3d-manager.
- No DB schema / Flyway changes. No new dependencies.

---

## Rules / Gates

- `gofmt -l go/` — empty (clean).
- `go vet ./...` (in `go/`) — clean.
- `golangci-lint run` (in `go/`) — clean.
- `go test ./... -race -cover` (in `go/`) — green (existing suite must still pass; add/adjust a unit
  assertion that `ProcessPayment` normalizes a leading-space currency to a trimmed 3-letter code if a
  currency test already exists — otherwise no new test is required for R1–R6).
- `docker build -f go/Dockerfile go` — succeeds.
- `kubectl apply --dry-run=client -k k8s/base` (or `kubectl apply --dry-run=client -f k8s/base/`) —
  manifests still valid.
- No files changed outside: `go/internal/payment/service.go`, `go/internal/payment/refund.go`,
  `go/internal/payment/store.go`, `k8s/base/configmap.yaml`, `k8s/base/deployment.yaml`.
- Run `./scripts/k3d-manager _agent_audit` if available in the work repo; otherwise self-audit for
  bare `sudo`, inline creds, hardcoded IPs.

---

## Definition of Done

- [ ] R1: currency normalized once via `strings.ToUpper(strings.TrimSpace(req.Currency))`; both the
      payment struct and the gateway request use the single `currency` value.
- [ ] R2: `RunInTx` wraps the original error with the rollback error via `fmt.Errorf("%w ...", err, rbErr)`.
- [ ] R3: `gatewayRequest` built inside `persist` from `locked`; pre-tx construction removed.
- [ ] R4: `request.CardNumber/CardCVC/CardExpMonth/CardExpYear` zeroed immediately after
      `gatewayImpl.ProcessPayment(request)`.
- [ ] R6: `db.sslmode: "disable"` key added to the base ConfigMap with the Istio-mTLS rationale comment.
- [ ] R5: `DB_SSLMODE` env wired from `configMapKeyRef` → `db.sslmode` in the Deployment.
- [ ] `gofmt`/`go vet`/`golangci-lint`/`go test -race`/`docker build`/manifest dry-run all green.
- [ ] Committed and pushed to `origin/feat/go-rewrite`; report the SHA.
- [ ] memory-bank (`activeContext.md` + `progress.md` in k3d-manager) updated with the SHA + status.

**Commit message (exact):**

```
fix(payment): Copilot round-4 hardening — currency trim, tx error cause, locked-row gateway IDs, card zeroing, DB_SSLMODE wiring
```

---

## What NOT to Do

- Do NOT open a PR; do NOT merge; do NOT skip hooks (`--no-verify`); do NOT commit to `main` — commit
  on `feat/go-rewrite`.
- Do NOT split `mock.go` (finding #7 — PR2).
- Do NOT modify the Java tree, other services, the e2e suite, or k3d-manager.
- Do NOT implement Keycloak JWT, the role matrix, or real Stripe/PayPal — still PR2.
- Do NOT change the refund/payment status-machine logic beyond the exact blocks above.
