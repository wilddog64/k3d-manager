# Bug: Go payment service drops `gatewayTransactionId` from the payment response

**Filed:** 2026-10-02
**Status:** FIXED `4a2503d` (Codex wrote; sandbox blocked git, Claude verified + committed: gofmt/vet clean, go test all ok, unmapped-field mutation red). PR wilddog64/shopping-cart-payment#79 OPEN (Copilot requested); live e2e pending merge + image + substrate pin bump
**Repo:** `wilddog64/shopping-cart-payment` (work branch: `fix/payment-response-gateway-transaction-id` from `origin/main`)
**Spec branch:** `k3d-manager-v1.41.0`
**Found by:** live Tier 1 `make e2e` run `1790970000-22917` (image `shopping-cart-e2e-tests:sha-35098aca…`, commit `4a94eb0a`): 56 passed, 1 failed, 45 did not run
**Related:** `docs/bugs/2026-10-02-e2e-keycloak-user-profile-incomplete.md` (previous blocker, now live-verified), `docs/plans/shopping-cart-payment-go-rewrite-pr1.md` (Gateway Contract: "return a synthetic `gatewayTransactionId`")

## Symptom

```
[api] › tests/api/payments.spec.ts:28:9 › Payment API › Process Payment › should process payment successfully with mock gateway
Error: expect(received).toBeDefined()
Received: undefined
> 46 |       expect(payment.gatewayTransactionId).toBeDefined()
```

The test fails the same way on all three attempts. The other 7 payments tests pass, which shows that the Keycloak token, the role mapping and the JWT converter all work.

## Root cause

The mock gateway produces an ID (`go/internal/gateway/mock.go:60`, `"mock_txn_" + shortID()`). `service.go:191/203` stores it in `Payment.GatewayTransactionID`. But `PaymentResponse` in `go/internal/payment/dto.go` has no field for it, so it never reaches the JSON. `docs/api/payments.md:79,122` in the payment repo documents `"gatewayTransactionId"` in the response, and the rewrite spec requires it. The field was lost in the Java→Go rewrite.

## Fix (all in `shopping-cart-payment`, `go/internal/payment/`)

### S1: `dto.go`, `PaymentResponse` struct

Old:
```go
	Gateway       string        `json:"gateway"`
	CardLast4     *string       `json:"cardLast4"`
```
New:
```go
	Gateway              string        `json:"gateway"`
	GatewayTransactionID *string       `json:"gatewayTransactionId"`
	CardLast4            *string       `json:"cardLast4"`
```
(Let `gofmt` realign the rest of the struct.)

### S2: `dto.go`, `PaymentResponseFrom`

Old:
```go
	var failureReason *string
	if p.FailureReason.Valid {
```
New:
```go
	var gatewayTransactionID *string
	if p.GatewayTransactionID.Valid {
		v := p.GatewayTransactionID.String
		gatewayTransactionID = &v
	}
	var failureReason *string
	if p.FailureReason.Valid {
```
In the returned literal, add `GatewayTransactionID: gatewayTransactionID,` directly after `Gateway: p.Gateway,`. Then run `gofmt`.

### S3: `dto_test.go`, new test

```go
func TestPaymentResponseFromIncludesGatewayTransactionID(t *testing.T) {
	p := &Payment{GatewayTransactionID: sql.NullString{String: "mock_txn_abc", Valid: true}}
	got, err := json.Marshal(PaymentResponseFrom(p))
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if !bytes.Contains(got, []byte(`"gatewayTransactionId":"mock_txn_abc"`)) {
		t.Fatalf("gatewayTransactionId missing: %s", string(got))
	}
}
```
Add `"database/sql"` to the imports. If `Payment` needs more non-zero fields to marshal (for example `CreatedAt`), set only those.

## Gate (paste output)

1. `cd go && gofmt -l ./internal/payment` prints nothing. `go vet ./...` and `go test ./...` both report 0 failures.
2. Mutation check: revert S2 only (keep S1 and S3). `go test ./internal/payment -run GatewayTransactionID` must FAIL. Restore S2.
3. `git diff --stat origin/main` shows only `go/internal/payment/dto.go` and `go/internal/payment/dto_test.go`.

## Live gate (Claude/operator, after the image builds)

Rerun `make e2e` with the new payment image. `should process payment successfully with mock gateway` must pass, and `api/payments.spec.ts` must show 0 failures.

## What NOT to Do

- Do NOT create a PR; do NOT merge
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than the 2 listed
- Do NOT commit to `main`; work on `fix/payment-response-gateway-transaction-id` only
- Do NOT change the e2e test to drop the assertion: the response contract is the source of truth
