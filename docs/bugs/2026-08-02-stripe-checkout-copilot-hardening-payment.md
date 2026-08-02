# Bugfix: Stripe checkout Copilot hardening — payment service

**Repo:** `shopping-cart-payment` (work here; this spec lives in k3d-manager)
**Branch:** `feat/stripe-checkout-gateway` (Phase B)
**File:** `go/internal/gateway/mock.go`

Copilot review findings on PR #48. CI is already green; the Stripe path is gated off until
enablement (mock stays active while `STRIPE_API_KEY` is empty), so neither is live yet — fix
before the enablement flip.

---

## Problem

1. **Data race on the package-global `stripe.Key`.** `StripeGateway.ProcessPayment` sets
   `stripe.Key = g.apiKey` (a package-level global) on every call. Under concurrent requests
   this races, and another gateway/config could overwrite it mid-flight. The stripe-go client
   is meant to be constructed per key, not via the global.
2. **Internal error text leaked to the client and DB.** The non-`*stripe.Error` branch returns
   `err.Error()` as the failure message, which the API exposes as `failureReason` and persists
   to the DB — it can leak internal/transport detail.

**Root cause:** use of the stripe-go global key + returning a raw error string in the new
Phase B gateway.

---

## Fix

### Change 1 — imports: swap the paymentintent package for the client package

**Exact old block:**

```go
	"github.com/google/uuid"
	"github.com/stripe/stripe-go/v79"
	stripeintent "github.com/stripe/stripe-go/v79/paymentintent"
)
```

**Exact new block:**

```go
	"github.com/google/uuid"
	"github.com/stripe/stripe-go/v79"
	stripeclient "github.com/stripe/stripe-go/v79/client"
)
```

> The `stripe` package itself stays imported (used for `stripe.Int64`, `stripe.String`,
> `stripe.Error`, `stripe.PaymentIntentParams`, `stripe.PaymentIntentStatusSucceeded`, …).

### Change 2 — drop the global key assignment

**Exact old block:**

```go
	stripe.Key = g.apiKey

	params := &stripe.PaymentIntentParams{
```

**Exact new block:**

```go
	params := &stripe.PaymentIntentParams{
```

### Change 3 — create a per-request client instead of `stripeintent.New`

**Exact old block:**

```go
	pi, err := stripeintent.New(params)
```

**Exact new block:**

```go
	sc := stripeclient.New(g.apiKey, nil)
	pi, err := sc.PaymentIntents.New(params)
```

> `stripeclient.New(key, nil)` returns a `*client.API` bound to this gateway's key with the
> default backends — no global mutation, safe under concurrency.

### Change 4 — do not leak the raw error string

**Exact old block:**

```go
		return PaymentResultFailure("stripe_error", err.Error())
```

**Exact new block:**

```go
		return PaymentResultFailure("stripe_error", "payment processing failed")
```

> `StripeGateway` has no logger field, so we simply return a generic message (this string
> becomes `failureReason`, persisted + returned). Adding structured logging of the internal
> error is a separate follow-up, not part of this fix. The `*stripe.Error` branch above is
> unchanged — `serr.Msg` is Stripe's own user-facing message and is safe to surface.

---

## Files Changed

| File | Change |
|------|--------|
| `go/internal/gateway/mock.go` | per-request Stripe client (no global key), generic failure message |

---

## Rules

- `cd go && gofmt -l internal/gateway/mock.go` → no output; `go build ./...` clean;
  `go vet ./...` clean.
- `cd go && go test -count=1 ./internal/gateway/...` must pass.
- Keep golangci-lint clean (the `go` CI job runs golangci-lint v2.7.2).
- Do not touch any other file. Do not change `go.mod`/`go.sum` (the `client` package is part of
  the already-required `github.com/stripe/stripe-go/v79` module).

---

## Definition of Done

- [ ] Changes 1–4 committed on `feat/stripe-checkout-gateway`
- [ ] `gofmt`/`go build`/`go vet`/`go test ./internal/gateway/...` green uncached
- [ ] `go` CI job (golangci-lint) stays green
- [ ] Branch pushed to origin
- [ ] memory-bank updated (repo-local) as a separate commit with the SHA

**Commit message (exact):**
```
fix(gateway): use per-request Stripe client and stop leaking error detail
```

---

## What NOT to Do

- Do NOT create a PR (PR #48 already exists — pushing updates it)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `go/internal/gateway/mock.go`
- Do NOT commit to `main` — work on `feat/stripe-checkout-gateway`
- Do NOT change `go.mod`/`go.sum`
