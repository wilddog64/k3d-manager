# Shopping-Cart Payment — Go Rewrite PR1 Follow-ups (tests, CHANGELOG, CI gates, amount JSON shape)

**Work repo:** `shopping-cart-payment`
**Branch (all work):** `feat/go-rewrite` — **continue the existing branch** (additional commit on top of
`ddc6c82`); do NOT branch anew, do NOT open a PR yet.
**Spec repo:** k3d-manager (`k3d-manager-v1.7.1`) — this file only.
**Type:** Follow-up to `docs/plans/shopping-cart-payment-go-rewrite-pr1.md`. Closes the DoD gaps found
in the verification of `ddc6c82` (Claude, 2026-06-17). The functional core works end-to-end (built,
ran vs real Flyway Postgres: health 200, mock payment 201 COMPLETED, idempotency, over-refund 400,
refund 200, audit rows persisted). These follow-ups make it mergeable.

---

## Why

`ddc6c82` reproduced the HTTP/DB/gateway contract faithfully but did **not** satisfy the PR1 DoD:
no tests, no CHANGELOG, CI missing two gates, and the `amount` field serializes as a JSON **string**
instead of a JSON **number** (a real observable-contract deviation from the Java service that will
break numeric consumers / the Playwright e2e). Fix these four, plus three smaller confirmations,
before the PR.

---

## Before You Start

1. `git pull origin k3d-manager-v1.7.1` in k3d-manager; read this spec **and** the original
   `docs/plans/shopping-cart-payment-go-rewrite-pr1.md` in full.
2. In `shopping-cart-payment`: `git fetch origin && git checkout feat/go-rewrite && git pull
   origin feat/go-rewrite` (you are extending `ddc6c82`, not starting over).
3. Read these existing Go files before changing anything: `go/internal/payment/{service.go,
   refund.go,handler.go,dto.go,model.go,store.go,errors.go}`, `go/internal/gateway/{mock.go,
   gateway.go}`, `go/internal/crypto/encryption.go`, `go/internal/config/config.go`,
   `go/cmd/server/main.go`, `.github/workflows/go-ci.yml`.
4. Read the Java reference for the two contract confirmations below:
   `src/main/java/com/shoppingcart/payment/dto/PaymentResponse.java` (+ any `@JsonFormat` /
   Jackson config) and `src/main/resources/application.yml` (gateway `enabled` defaults).

---

## Scope — what changes (and what does NOT)

**IN (this follow-up):** `go/**` test files (NEW `_test.go`), `CHANGELOG.md`,
`.github/workflows/go-ci.yml`, and the small `amount`-marshaling change in `go/internal/payment/`
(plus the gateway-default + startup confirmations below if they require a change).

**OUT (do not touch):** the Java tree (`src/**`, `pom.xml`, root `Dockerfile`, `db/migration/**`,
Java `ci.yml`); `k8s/base/*`; order/basket/product-catalog/frontend; the e2e suite; k3d-manager.

---

## Fix 1 — `amount` must serialize as a JSON NUMBER at scale 4 (MUST)

**Problem (verified live):** `POST /api/v1/payments` returns `"amount":"42.5"` — a quoted JSON
**string**, with trailing zeros and the decimal point collapsed (`99.0000` → `"99"`). `shopspring/
decimal`'s default `MarshalJSON` emits a quoted string. The original spec (§HTTP API Contract) states
**"Amounts are JSON numbers, scale 4."** A JS/Jackson consumer parsing `"42.5"` gets a string, not a
number — a breaking shape difference.

**Required:** every monetary field in the JSON responses (`PaymentResponse.amount`,
`RefundResponse.amount`, and any other `decimal.Decimal` rendered to JSON) must serialize as an
**unquoted JSON number**, matching the Java/Jackson output.

**Confirm against Java first:** read `PaymentResponse.java` + Jackson config and determine the exact
shape Jackson emits for the `BigDecimal amount` backed by `NUMERIC(19,4)` — specifically whether it
preserves scale (`42.5000`) or trims (`42.5`). Match that byte-for-byte.

**Recommended implementation** — a fixed-scale money type that marshals unquoted at scale 4 (adjust
the scale/trim to whatever Java actually emits):

```go
// go/internal/payment/money.go  (or wherever the response DTOs live)
type Amount decimal.Decimal

func (a Amount) MarshalJSON() ([]byte, error) {
    // emit an UNQUOTED JSON number; StringFixed(4) matches NUMERIC(19,4) if Java preserves scale.
    return []byte(decimal.Decimal(a).StringFixed(4)), nil
}
```

Use `Amount` for the amount fields in `PaymentResponse`/`RefundResponse` (the DTO layer only — keep
`decimal.Decimal` for arithmetic in the service/store). If Java instead emits a trimmed number, use
`decimal.Decimal(a).String()` and set the package-level `decimal.MarshalJSONWithoutQuotes = true`
in an `init()`/`main` instead — but **pick the one that matches Java; do not guess.** Add a unit
test asserting the exact bytes (see Fix 2).

---

## Fix 2 — Add the PR1 test suite (MUST — DoD line: `go test ./... -race` green)

`ddc6c82` ships zero `_test.go` files, so `go test ./...` passes vacuously. Add the unit +
integration coverage the original DoD required.

**Unit tests (`go test`, no network):**
- payment status machine (`PENDING→PROCESSING→COMPLETED`, `PENDING→FAILED`) and the field-set order;
- refund status machine + guards: over-refund (`amount > remaining`) → `ErrRefundExceedsRemaining`,
  refund of a non-`COMPLETED` payment rejected, fully-refunded payment flips to `REFUNDED`;
- idempotent replay: same idempotency key returns the **original** payment id (not a new one);
- decimal math at scale 4 (sum of refunds, remaining-amount calc) — no float drift;
- mock gateway: success path (failure-rate `0.0` deterministic) and the failure-rate path;
- encryption: `encrypt`→`decrypt` round-trip and `card_last4`/brand masking; **assert no full PAN/CVV
  in the encrypted blob or any logged field**;
- handler error mapping: `404` body for unknown payment, `400` body for validation / over-refund /
  invalid UUID — assert the exact JSON keys (`code`, `message`);
- **amount JSON shape (Fix 1):** marshal a `PaymentResponse` and assert `amount` is an **unquoted
  number** matching the Java shape (e.g. `"amount":42.5000`).

**Integration test (testcontainers-go, or a documented `docker compose`, gated behind a build tag
or `testing.Short()` skip):** spin a throwaway Postgres, apply the **Flyway** `V1`/`V2` SQL, then
drive `process → get → list → refund` and assert the persisted `payments` / `refunds` /
`transactions` rows (CHARGE + REFUND audit) and the `idempotency_key` unique-index behaviour. (This
mirrors exactly what was done by hand during verification — codify it.)

`go test ./... -race -cover` must be green with these present.

---

## Fix 3 — CI gates: add `golangci-lint` + `permissions: contents: read` (MUST)

`.github/workflows/go-ci.yml` is missing the `golangci-lint` step (original spec/DoD) and a
workflow-level `permissions` block (CLAUDE.md security rule: `permissions: contents: read` unless
elevation is required).

**Add a top-level permissions block** (immediately under `on:` / above `jobs:`):
```yaml
permissions:
  contents: read
```

**Add the golangci-lint step** (pin the action to a version tag — never `@main`/`@latest`), after
`go vet` and before `go test`:
```yaml
      - uses: golangci/golangci-lint-action@v6
        with:
          version: v1.61.0
          working-directory: go
```
Add a minimal `go/.golangci.yml` if the repo has none, and make sure `golangci-lint run` is clean
(fix any findings it raises rather than disabling linters wholesale).

---

## Fix 4 — CHANGELOG `[Unreleased]` entry (MUST — DoD)

Add an `[Unreleased]` section to `CHANGELOG.md` (create the file if absent, Keep-a-Changelog format)
under `### Added`, e.g.:
```
### Added
- Go rewrite (PR1): functional-core payment service under `go/` — HTTP API, Postgres persistence,
  mock gateway, idempotency, refunds, transaction audit trail, AES-256-GCM encryption, actuator
  health/metrics, per-IP rate limiting. Ships side-by-side with the Java service (Java remains the
  deployed artifact). Auth (Keycloak JWT) and real Stripe/PayPal gateways are deferred to PR2.
```

---

## Confirmations (verify against Java; change only if they diverge)

**C1 — gateway `enabled` defaults.** `config.go` defaults `STRIPE_ENABLED`/`PAYPAL_ENABLED` to
`true`, and the Stripe/PayPal stubs return synthetic success. PR1 intends them as **disabled stubs**.
Read `application.yml`: if Java defaults these to `false`, change the Go defaults to `false` to match.
Regardless, ensure no path makes a real external API call in PR1 (it currently does not — keep it
that way). State what Java does in the PR description.

**C2 — DB-down startup behaviour.** `main.go:43` makes a failed Postgres ping **fatal at startup**.
The spec's readiness contract (`/actuator/health/readiness` → `503` when Postgres is down, `200`
when up) implies the **process stays up and serves** while the DB is unavailable, so k8s can gate
traffic via the readiness probe instead of crash-looping the pod. Change startup so a DB-ping failure
is **logged and non-fatal** (server starts; readiness reports `503` until the pool connects), unless
the Java service itself hard-fails on DB at boot — confirm and match. (This matters for the preflight
/ blue/green rollout: a crash-looping pod can't report `503`.)

**C3 — Dockerfile (note only, no required change).** The Dockerfile uses `golang:1.21` → distroless
(not the spec's `alpine:3.19`) and drops the `HEALTHCHECK`. Distroless is an acceptable security
improvement and k8s probes cover liveness/readiness, so **keep it** — just note the deviation from the
spec in the PR description so reviewers aren't surprised.

---

## Rules / Gates

- `gofmt -l go/` — empty (clean).
- `go vet ./...` (in `go/`) — clean.
- `golangci-lint run` (in `go/`) — clean.
- `go test ./... -race -cover` (in `go/`) — green, with the new unit + integration tests present
  (integration gated behind a build tag / `testing.Short()`).
- `docker build -f go/Dockerfile go` — succeeds.
- Amount JSON shape asserted by a unit test against the Java shape.
- No files changed outside `go/**`, `CHANGELOG.md`, `.github/workflows/go-ci.yml`.

---

## Definition of Done

- [ ] `amount` (and any monetary field) serializes as an **unquoted JSON number** matching Java; unit
      test asserts the exact bytes.
- [ ] Unit tests added for: status machines, refund guards, idempotent replay, scale-4 decimal math,
      mock gateway success/failure, encryption round-trip + masking, handler 404/400 error bodies,
      amount JSON shape.
- [ ] Integration test added (testcontainers/`docker compose` + Flyway schema): process→get→list→
      refund persists `payments`/`refunds`/`transactions`; idempotency unique-key honoured. Gated
      behind a build tag / `testing.Short()`.
- [ ] `.github/workflows/go-ci.yml`: `permissions: contents: read` added; `golangci-lint` step added
      (action pinned to a version tag); `golangci-lint run` clean.
- [ ] `CHANGELOG.md` `[Unreleased]` entry added.
- [ ] C1 (gateway defaults) and C2 (DB-down non-fatal startup) confirmed against Java and reconciled;
      PR description states what Java does. C3 deviation noted.
- [ ] `gofmt`/`go vet`/`golangci-lint`/`go test -race`/`docker build` all green.
- [ ] Committed and pushed to `origin/feat/go-rewrite`; report SHA.
- [ ] memory-bank (`activeContext.md` + `progress.md` in k3d-manager) updated with the SHA + status.

**Commit message (exact):**
```
test(payment): PR1 follow-ups — tests, CHANGELOG, CI gates, amount JSON number shape
```

---

## What NOT to Do

- Do NOT open a PR; do NOT merge; do NOT skip hooks (`--no-verify`); do NOT commit to `main` — commit
  on `feat/go-rewrite`.
- Do NOT modify the Java tree (`src/**`, `pom.xml`, root `Dockerfile`, `db/migration/**`, Java
  `ci.yml`), `k8s/base/*`, or any other service / the e2e suite / k3d-manager.
- Do NOT implement Keycloak JWT, the `@PreAuthorize` role matrix, or real Stripe/PayPal — still PR2.
- Do NOT change the DB schema or run Flyway from Go.
- Do NOT "fix" the amount shape to a different string format — it must be a JSON **number**; match
  Java. If the Java shape is genuinely ambiguous, STOP and report rather than guessing.
