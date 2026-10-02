# Bug: Go payment service drops `gatewayTransactionId` from the payment response

**Filed:** 2026-10-02
**Status:** Go FIXED `4a2503d`, PR #79 MERGED `ea86c42`; **e2e NOT fixed by that**: the published image is the Java service (see Correction). Java fix S4–S5 `4169430` (Codex, Claude-verified diff; branch CI 37065016633 green, 140 tests vs main 139); PR wilddog64/shopping-cart-payment#80 OPEN (Copilot requested)
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

## Correction (2026-10-02, after #79 merged): the e2e runs the Java service

The root cause above was incomplete. The image `ghcr.io/wilddog64/shopping-cart-payment` comes from the
root `Dockerfile` (`eclipse-temurin:21`, Spring Boot), via `ci.yaml` → `build-push-deploy.yml`. `go-ci.yml`
only runs `docker build -f Dockerfile .` inside `go/` and never pushes. So the substrate (`sha-412bc78…`, and
`sha-ea86c42…` after #79) runs the **Java** service, and the Java DTO
`src/main/java/com/shoppingcart/payment/dto/PaymentResponse.java` also omits `gatewayTransactionId`. The Go
rewrite copied that omission; it did not introduce it. #79 is still correct (the Go service now matches
`docs/api/payments.md`), but it does not change what e2e runs. Bumping the substrate pin to `sha-ea86c42` alone
would not fix the e2e test.

**Repo/branch for S4–S5:** `shopping-cart-payment`, `fix/payment-java-response-gateway-transaction-id` from `origin/main` (`ea86c42`).

### S4: `src/main/java/com/shoppingcart/payment/dto/PaymentResponse.java`

Old:
```java
    private String gateway;
    private String cardLast4;
```
New:
```java
    private String gateway;
    private String gatewayTransactionId;
    private String cardLast4;
```
Old:
```java
                .gateway(payment.getGateway())
                .cardLast4(payment.getCardLast4())
```
New:
```java
                .gateway(payment.getGateway())
                .gatewayTransactionId(payment.getGatewayTransactionId())
                .cardLast4(payment.getCardLast4())
```

### S5: new `src/test/java/com/shoppingcart/payment/dto/PaymentResponseTest.java`

```java
package com.shoppingcart.payment.dto;

import com.shoppingcart.payment.entity.Payment;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;

class PaymentResponseTest {

    @Test
    void fromCopiesGatewayTransactionId() {
        Payment payment = Payment.builder().gatewayTransactionId("mock_txn_abc").build();

        assertEquals("mock_txn_abc", PaymentResponse.from(payment).getGatewayTransactionId());
    }
}
```

### Gate S4–S5

Maven can't run locally: the private `rabbitmq-client` package needs GitHub Packages auth. So branch CI is the gate.
1. `git diff --stat origin/main` shows only the 2 files above.
2. The branch push triggers `ci.yaml`. **Build and Test** must pass, and its test count must be one higher than main's.
3. Mutation (Claude): on a scratch commit, drop the `.gatewayTransactionId(...)` builder line and confirm the new test fails in CI. Optional if the reviewer accepts the test by reading it.

### Then

Merge, wait for the main image `sha-<merge>`, bump `scripts/etc/e2e/kustomization.yaml` `shopping-cart-payment` `newTag`,
and rerun `make e2e`.
