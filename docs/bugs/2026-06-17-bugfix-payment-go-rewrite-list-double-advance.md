# Bugfix: payment Go rewrite — list endpoints double-advance pgx rows

**Spec repo:** k3d-manager (`k3d-manager-v1.7.1`)
**Work repo:** `shopping-cart-payment`
**Branch (all work repos):** `feat/go-rewrite`
**Files:** `go/internal/payment/store.go`

---

## Problem

`Store.GetPaymentsByCustomer` and `Store.GetRefundsByPayment` return wrong results.
With a single matching row they return `pgx.ErrNoRows`; with N rows they silently drop
every other row. The customer payment-list and payment-refund-list endpoints are therefore
broken at runtime.

**Root cause:** double-advance of the pgx result set. Each method already iterates with
`for rows.Next()`, then inside the loop calls a wrapper (`scanPaymentRows` /
`scanRefundRows`) whose first line is **another** `rows.Next()`. The loop's `Next()`
positions on row K; the wrapper's `Next()` consumes row K and lands on K+1, so the wrapper
scans K+1 (or hits `ErrNoRows` when K was the last/only row). `GetPayment` (by id) is
unaffected — it uses `QueryRow` + the singular `scanPaymentRow`.

**Discovered by:** the build-tagged integration test added in `f2e47ff`
(`go/internal/payment/integration_test.go`), which was committed RED — it fails at
`integration_test.go:80: list payments: no rows in result set`. The test is correct; the
store is wrong. The bug pre-dates `f2e47ff` (introduced in `ddc6c82`); `f2e47ff`'s
`store.go` diff only added the `paymentStore` interface and did not touch these methods.

**Live-facing:** reachable via three GET routes in `go/internal/payment/handler.go`
(`/api/v1/payments/customer/:customerId`, `/api/v1/payments/:paymentId/refunds`, and the
`customerId` query-param variant).

---

## Reproduction

```bash
cd shopping-cart-payment/go
# Postgres reachable, schema applied via the real Java Flyway migrations
# (V1__init_schema.sql, V2__add_billing_email_to_payment_methods.sql)
export PAYMENT_INTEGRATION_DSN='postgres://...'
go test -tags integration ./internal/payment/...
```

**Expected:** PASS.
**Actual (current):** FAIL — `integration_test.go:80: list payments: no rows in result set`.

---

## Fix

Each wrapper is called exactly once — only from its own loop — so delete the buggy wrapper
and have the loop call the singular scanner directly. `pgx.Rows` satisfies the `pgx.Row`
interface (both expose `Scan(dest ...any) error`), so `scanPaymentRow(rows)` /
`scanRefundRow(rows)` compile unchanged.

### Change 1 — `go/internal/payment/store.go`: call singular scanner in `GetPaymentsByCustomer` loop

**Exact old block:**

```go
	var payments []*Payment
	for rows.Next() {
		payment, err := scanPaymentRows(rows)
		if err != nil {
			return nil, err
		}
		payments = append(payments, payment)
	}
```

**Exact new block:**

```go
	var payments []*Payment
	for rows.Next() {
		payment, err := scanPaymentRow(rows)
		if err != nil {
			return nil, err
		}
		payments = append(payments, payment)
	}
```

### Change 2 — `go/internal/payment/store.go`: call singular scanner in `GetRefundsByPayment` loop

**Exact old block:**

```go
	var refunds []*Refund
	for rows.Next() {
		refund, err := scanRefundRows(rows)
		if err != nil {
			return nil, err
		}
		refunds = append(refunds, refund)
	}
```

**Exact new block:**

```go
	var refunds []*Refund
	for rows.Next() {
		refund, err := scanRefundRow(rows)
		if err != nil {
			return nil, err
		}
		refunds = append(refunds, refund)
	}
```

### Change 3 — `go/internal/payment/store.go`: delete the now-unused `scanPaymentRows` wrapper

**Exact old block (delete entirely):**

```go
func scanPaymentRows(rows pgx.Rows) (*Payment, error) {
	if !rows.Next() {
		return nil, pgx.ErrNoRows
	}
	payment, err := scanPaymentRow(rows)
	if err != nil {
		return nil, err
	}
	return payment, nil
}
```

### Change 4 — `go/internal/payment/store.go`: delete the now-unused `scanRefundRows` wrapper

**Exact old block (delete entirely):**

```go
func scanRefundRows(rows pgx.Rows) (*Refund, error) {
	if !rows.Next() {
		return nil, pgx.ErrNoRows
	}
	refund, err := scanRefundRow(rows)
	if err != nil {
		return nil, err
	}
	return refund, nil
}
```

> After deleting both wrappers, confirm `scanPaymentRows` / `scanRefundRows` have no
> remaining references: `grep -rn 'scanPaymentRows\|scanRefundRows' go/` must return nothing.

---

## Files Changed

| File | Change |
|------|--------|
| `go/internal/payment/store.go` | Point both list loops at the singular `scanPaymentRow`/`scanRefundRow`; delete the two double-advancing wrapper funcs |

---

## Rules

- Do NOT modify `go/internal/payment/integration_test.go` — it is the correct acceptance
  evidence; it must go green by fixing the store, not by changing the test.
- Do NOT touch any file other than `go/internal/payment/store.go`.
- `gofmt -l go/internal/payment/store.go` — must print nothing.
- `go vet ./...` (from `go/`) — zero new findings.
- `golangci-lint run` (from `go/`, the gate added in `f2e47ff`) — zero new findings,
  including `unused` (this is why the dead wrappers must be deleted, not left in place).
- Run `_agent_audit` before reporting done.

---

## Definition of Done

- [ ] Both list loops call the singular scanner; both wrapper funcs deleted
- [ ] `grep -rn 'scanPaymentRows\|scanRefundRows' go/` returns nothing
- [ ] `go test ./... -race` (from `go/`) — unit suite green
- [ ] `go test -tags integration ./internal/payment/...` — **green** against a Postgres
      seeded with the real Java Flyway migrations (this is the gate that was red; it MUST
      be run and pass before reporting done — do NOT report done on the unit suite alone)
- [ ] `gofmt`, `go vet`, `golangci-lint run` clean
- [ ] `./scripts/k3d-manager _agent_audit` clean
- [ ] Committed and pushed to `feat/go-rewrite` in `shopping-cart-payment`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(payment): stop double-advancing pgx rows in list scanners

GetPaymentsByCustomer and GetRefundsByPayment looped with rows.Next()
then called a wrapper that advanced the cursor again, dropping every
other row (ErrNoRows for a single match). Delete the wrappers and scan
the current row directly. Fixes the integration test added in f2e47ff.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `go/internal/payment/store.go`
- Do NOT modify or weaken `integration_test.go` to make it pass
- Do NOT commit to `main` — work on `feat/go-rewrite`
