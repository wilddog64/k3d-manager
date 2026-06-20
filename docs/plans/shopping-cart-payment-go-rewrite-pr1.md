# Shopping-Cart Payment — Go Rewrite, PR1 (Functional Core)

**Work repo:** `shopping-cart-payment`
**Branch (all work):** `feat/go-rewrite` — create from `origin/main`
**Spec repo:** k3d-manager (`k3d-manager-v1.7.1`) — this file only; do NOT edit k3d-manager otherwise.
**Type:** Feature (full service rewrite, phased). This is **PR1 of 2**. Mirrors the order rewrite
(`docs/plans/shopping-cart-order-go-rewrite-pr1.md`) — read that spec first for the shared house
rules; this spec gives the payment-specific contract.

---

## Why

`shopping-cart-payment` is the second of the two heavy JVM backends (order already has a Go-rewrite
spec). Porting it to Go cuts a ~512Mi Spring Boot pod to a ~20–50Mi static binary so the full stack
fits the 2-core preflight vCluster. Payment is the **money path** — higher blast radius than order —
so it goes second, reusing the pattern order proved. Decision: `project_shopping_cart_go_rewrite`.

**Acceptance contract:** the existing `shopping-cart-e2e-tests` (Playwright) suite must pass
**unchanged** against the Go service. The Go port reproduces the observable contract — HTTP surface,
JSON shapes, DB schema, transaction/refund semantics — byte-for-byte. Behaviour is the spec; the
Java source is the reference.

**Phasing:**
- **PR1 (this spec):** functional core — HTTP + Postgres (4 tables) + the **mock** gateway +
  idempotency + refunds + transaction audit trail + AES-256-GCM encryption service +
  security headers + actuator/health + per-IP rate limiting. Runs with `OAUTH2_ENABLED=false`
  (API open, for local/unit acceptance — the Go service adds this toggle since the Java
  `SecurityConfig` has no open fallback).
- **PR2 (follow-up spec, NOT this one):** Keycloak JWT/JWKS resource-server validation + the
  `@PreAuthorize` role matrix (`PAYMENT_USER/READ/WRITE/ADMIN`, `PLATFORM_ADMIN`), the Stripe +
  PayPal real gateways, and Vault-sourced RabbitMQ/gateway credentials. Do NOT implement JWT,
  Stripe, or PayPal in PR1 — read the `OAUTH2_*`/gateway env but leave the seam.

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager.
2. `git pull origin k3d-manager-v1.7.1` in k3d-manager to get this spec; read the **order** PR1
   spec (`docs/plans/shopping-cart-order-go-rewrite-pr1.md`) for the shared conventions.
3. In `shopping-cart-payment`: `git fetch origin && git checkout -b feat/go-rewrite origin/main`.
4. Read these Java files first — they are the contract you must reproduce exactly:
   - `src/main/java/com/shoppingcart/payment/controller/PaymentController.java` (HTTP surface)
   - `src/main/java/com/shoppingcart/payment/service/PaymentService.java` (process flow, idempotency, status)
   - `src/main/java/com/shoppingcart/payment/service/RefundService.java` (refund flow + guards)
   - `src/main/java/com/shoppingcart/payment/gateway/PaymentGateway.java` + `PaymentGatewayRouter.java`
     + `gateway/mock/MockGateway.java` (the gateway contract + the PR1 mock behaviour)
   - `src/main/java/com/shoppingcart/payment/security/EncryptionService.java` + `PciDataMasker.java`
     (AES/GCM scheme + masking — copy the algorithm + key handling exactly)
   - `src/main/java/com/shoppingcart/payment/entity/*.java` + `dto/*.java` (DB columns + JSON shapes)
   - `src/main/resources/db/migration/V1__init_schema.sql` + `V2__*.sql` (**authoritative schema**)
   - `src/main/resources/application.yml`, `k8s/base/configmap.yaml` (env var names + defaults)
5. Reference repo for Go house style: `shopping-cart-basket/go.mod` and the order `go/` tree once
   it lands — gin, pgx/v5, amqp091-go, google/uuid, shopspring/decimal, zap, prometheus/client_golang.

---

## Scope — PR1

**IN:** Go module under `go/` alongside the Java service; identical HTTP contract; Postgres
persistence against the existing 4-table schema; the **mock** payment gateway; idempotency-key
dedup; refund flow + refund-amount guards; transaction audit-log writes; AES-256-GCM
EncryptionService + PCI last4/masking; security response headers; `/actuator/health*` +
`/actuator/prometheus`; per-IP rate limiting; Dockerfile; Go CI workflow; unit + integration tests.

**DEFERRED to PR2:** Keycloak JWT validation + the `@PreAuthorize` role matrix; the Stripe and
PayPal gateways (PR1 wires them as disabled stubs); Vault-sourced credentials
(`RABBITMQ_VAULT_ENABLED=false`, static gateway keys).

**OUT (do not touch):** order, basket, product-catalog, frontend; k3d-manager; the e2e suite.

---

## Target Layout — Java and Go SIDE BY SIDE

Identical rule to order: **keep the Java tree intact** (`src/**`, `pom.xml`, root `Dockerfile`,
existing Maven CI, `src/main/resources/db/migration/**`). The Go service is a new `go/` module; the
deployed artifact stays Java until the preflight proves the Go e2e. Suggested layout:

```
go/go.mod  go/go.sum
go/cmd/server/main.go            # wire config, db pool, gateway router, http server; graceful shutdown
go/internal/config/config.go     # env -> Config (all vars below)
go/internal/payment/model.go     # Payment, Refund, Transaction, PaymentMethod, status/type enums
go/internal/payment/store.go     # pgx CRUD against payments/refunds/transactions/payment_methods
go/internal/payment/service.go   # processPayment (idempotency, status machine, audit), getters
go/internal/payment/refund.go    # processRefund + guards + audit
go/internal/payment/handler.go   # gin handlers + DTOs + error mapping
go/internal/gateway/gateway.go   # PaymentGateway interface + Router (default mock)
go/internal/gateway/mock.go      # MockGateway (delay + failure-rate, deterministic)
go/internal/crypto/encryption.go # AES-256-GCM encrypt/decrypt + last4/mask helpers
go/internal/httpx/middleware.go  # security headers, rate limiter, request logging, auth seam
go/internal/health/health.go     # /actuator/health, /liveness, /readiness, /info, /prometheus
go/Dockerfile  go/Dockerfile.local
.github/workflows/go-ci.yml      # NEW additive Go workflow — do NOT touch the Java ci.yml
CHANGELOG.md                     # add [Unreleased] entry
```

Pinned deps: `github.com/gin-gonic/gin`, `github.com/jackc/pgx/v5` (+ `/pgxpool`),
`github.com/google/uuid`, `github.com/shopspring/decimal`, `go.uber.org/zap`,
`github.com/prometheus/client_golang`, `golang.org/x/time/rate`. **Money is `shopspring/decimal`
at scale 4** (`NUMERIC(19,4)`) — never float64.

---

## HTTP API Contract (reproduce exactly)

Base path **`/api/v1/payments`**. Content-Type `application/json`. Field names **camelCase**.
Timestamps are ISO-8601 strings (`Instant.toString()`, e.g. `2026-06-15T04:11:52.123456Z`), NOT
epoch. Amounts are JSON numbers, scale 4.

| Method & path | Body / params | Success | Errors |
|---|---|---|---|
| `POST /api/v1/payments` | `ProcessPaymentRequest` | `201` if status `COMPLETED`, else `202` + `PaymentResponse` | `400` validation; `409`/idempotent replay (see below) |
| `GET /api/v1/payments/{paymentId}` | UUID path | `200` + `PaymentResponse` | `404` if not found |
| `GET /api/v1/payments?orderId=X` | query | `200` + `[PaymentResponse]` (0 or 1 elem) | — |
| `GET /api/v1/payments?customerId=X` | query | `200` + `[PaymentResponse]` | — |
| `GET /api/v1/payments` (neither param) | — | `400` | — |
| `GET /api/v1/payments/order/{orderId}` | path | `200` + `PaymentResponse` | `404` |
| `GET /api/v1/payments/customer/{customerId}` | path | `200` + `[PaymentResponse]` | — |
| `GET /api/v1/payments/{paymentId}/refunds` | path | `200` + `[RefundResponse]` | — |
| `POST /api/v1/payments/{paymentId}/refund` | `RefundRequest` | `200` + `RefundResponse` | `404`; `400` invalid/over-refund |

**Headers:** `POST /payments` reads optional `X-Correlation-ID`, and an idempotency key from (in
order) `X-Idempotency-Key`, then `Idempotency-Key`, then the body `idempotencyKey`. When a
correlation id is provided it is echoed back as `X-Correlation-ID`. `POST .../refund` reads optional
`X-Correlation-ID` and `X-User-ID`.

**Idempotency:** `idempotency_key` has a UNIQUE partial index. A repeat `POST /payments` with the
same key must return the **original** payment (not create a second) — reproduce the Java
`PaymentService` behaviour exactly (confirm: return existing `PaymentResponse` with the original
status; do not error). If the Java path throws on conflict instead, match that — **read the source,
do not guess.**

**`ProcessPaymentRequest`** (validation → `400`): `orderId` (non-blank), `customerId` (non-blank),
`amount` (non-null, ≥ `0.01`), `currency` (exactly 3 chars), `gateway` (optional → router default
`mock`), `paymentMethodId` (optional), raw card fields `cardNumber/cardExpMonth/cardExpYear/cardCvc/
cardholderName` (optional — **never persisted as PAN/CVV**; only `card_last4` + `card_brand` derived
via the masker), `idempotencyKey` (optional).

**`PaymentResponse` fields** (exact names): `id`, `orderId`, `customerId`, `amount`, `currency`,
`status`, `gateway`, `cardLast4`, `cardBrand`, `failureReason`, `createdAt`, `completedAt`. Null
timestamps serialize as `null`.

**`RefundRequest`:** `amount` (non-null, ≥ `0.01`), `reason` (optional).
**`RefundResponse` fields:** `id`, `paymentId`, `amount`, `currency`, `status`, `reason`.

**Error body:** match the Java exception-handler shape (read `exception/*` + any
`@RestControllerAdvice`). At minimum `404` for unknown payment, `400` for validation / over-refund.
Confirm the exact JSON keys against the Java source before finalizing.

---

## Data Model / DB Schema Contract — Flyway-owned, **do NOT migrate from Go**

The schema is created by the repo's **Flyway** migrations (`db/migration/V1__init_schema.sql`,
`V2__add_billing_email_to_payment_methods.sql`) run by the **Java** service (`ddl-auto: validate`).
The Go service must **connect and map to the existing tables — never create, migrate, drop, or run
Flyway.** Authoritative columns (from V1; apply V2's `billing_email` addition to `payment_methods`):

- **`payments`**: `id` uuid pk, `order_id` varchar(255) NN, `customer_id` varchar(255) NN,
  `amount` numeric(19,4) NN, `currency` varchar(3) NN, `status` varchar(20) NN, `gateway`
  varchar(20) NN, `gateway_transaction_id`, `gateway_payment_intent_id`, `payment_method_id` uuid,
  `card_last4` varchar(4), `card_brand` varchar(20), `metadata` text, `failure_reason` varchar(500),
  `failure_code` varchar(50), `created_at` timestamp NN, `processed_at`, `completed_at`,
  `updated_at`, `correlation_id` varchar(100), `idempotency_key` varchar(50)
  (UNIQUE WHERE NOT NULL).
- **`refunds`**: `id` uuid pk, `payment_id` uuid NN fk→payments, `amount` numeric(19,4) NN,
  `currency` varchar(3) NN, `status` varchar(20) NN, `reason` varchar(500), `gateway_refund_id`,
  `failure_reason`, `failure_code`, `initiated_by` varchar(100), `created_at` NN, `processed_at`,
  `completed_at`, `updated_at`, `correlation_id`.
- **`payment_methods`**: `id` uuid pk, `customer_id` NN, `type` varchar(20) NN, `gateway`
  varchar(20) NN, `gateway_token` varchar(255) NN, `card_last4`, `card_brand`, `card_exp_month`,
  `card_exp_year`, `cardholder_name_encrypted` text, `billing_address_encrypted` text,
  `is_default` bool, `is_active` bool, `metadata` text, `created_at` NN, `updated_at`,
  `last_used_at`, plus V2 `billing_email`.
- **`transactions`** (audit): `id` uuid pk, `payment_id` uuid NN fk, `refund_id` uuid fk→refunds,
  `type` varchar(20) NN, `amount` numeric(19,4) NN, `currency` NN, `success` bool NN,
  `gateway_transaction_id`, `gateway_response` text, `gateway_error_code`, `gateway_error_message`,
  `created_at` NN, `correlation_id`.

Generate `id` UUIDs app-side (`uuid.New()`). Set `created_at`/`updated_at` on insert; bump
`updated_at` on update. Enum columns store the enum NAME string. Write the payment + its audit
`transactions` row in one transaction.

> If a live column name/scale differs when inspected, **the live schema (Flyway migration) wins** —
> match it and note the deviation in the PR. Do not guess; if a column is ambiguous, STOP and report.

---

## Status Machines (exact — from the enums + services)

**PaymentStatus:** `PENDING → PROCESSING → COMPLETED`; `PENDING → FAILED`;
`COMPLETED → REFUND_PENDING → REFUNDED`; `COMPLETED → REFUND_PENDING → REFUND_FAILED`.
Create → `PENDING`. On mock gateway success → `COMPLETED` (set `completed_at`, `gateway_transaction_id`,
`card_last4`/`card_brand`); on failure → `FAILED` (set `failure_reason`/`failure_code`). Reproduce
the exact `PaymentService` transition + field-set order.

**RefundStatus:** `PENDING → PROCESSING → COMPLETED`; `PENDING|PROCESSING → FAILED`. `processRefund`
guards (read `RefundService` for the exact rules): refund only a `COMPLETED` payment; refund amount
must be > 0 and not exceed the payment amount minus prior refunds → else `400`. On success set the
payment to `REFUNDED` (or `REFUND_PENDING` per the source) and write a `REFUND`-type transaction.

**TransactionType:** `AUTHORIZATION, CAPTURE, CHARGE, REFUND, VOID, CHARGEBACK`. PR1 writes at least
`CHARGE` (on process) and `REFUND` (on refund) audit rows — match what the Java services write.

---

## Gateway Contract (PR1 = mock only)

Reproduce the `PaymentGateway` interface: `getName()`, `isEnabled()`, `processPayment(req)`,
`processRefund(req)`, `tokenize(req)`, `deleteToken(token)`, `supportsRecurring()=false`,
`supportsPartialRefund()=true`. A `Router` registers all gateways by name and resolves
`getGatewayOrDefault(name)` → default `mock` (env `PAYMENT_GATEWAY_DEFAULT`); unknown gateway →
the Java path throws `IllegalArgumentException` (map to `400`), disabled gateway →
`IllegalStateException` (map to `400`/`409` — match the source).

**MockGateway (implement in PR1):** honour `MOCK_GATEWAY_DELAY_MS` (default 500) and
`MOCK_GATEWAY_FAILURE_RATE` (default `0.0`) — sleep the delay, then succeed unless the failure-rate
roll fails; return a synthetic `gatewayTransactionId`. Deterministic when failure-rate is `0.0`
(the e2e default). **Stripe + PayPal:** register as disabled stubs (`isEnabled()` reads
`STRIPE_ENABLED`/`PAYPAL_ENABLED` but the real API calls are PR2) — do NOT call external APIs in PR1.

---

## Encryption / PCI (reproduce the scheme)

Implement an `EncryptionService` matching the Java one: **AES-256-GCM** (`AES/GCM/NoPadding`),
key from `ENCRYPTION_KEY` (base64/hex per the Java source — **match exactly** so Java-written and
Go-written ciphertext interoperate), used for `payment_methods.cardholder_name_encrypted` /
`billing_address_encrypted`. Reproduce `PciDataMasker` for `card_last4` derivation and any logging
masks. **Never persist or log full PAN/CVV.** Confirm the GCM nonce length, tag handling, and key
encoding against `security/EncryptionService.java` — do not invent a scheme.

---

## Config / Env Vars (same names + defaults as `application.yml`)

`SERVER_PORT`(**8084**); `DB_HOST`/`DB_PORT`(5432)/`DB_NAME`(payments)/`DB_USERNAME`(postgres)/`DB_PASSWORD`;
`RABBITMQ_HOST`/`RABBITMQ_PORT`(5672)/`RABBITMQ_VHOST`(/)/`RABBITMQ_USERNAME`(guest)/`RABBITMQ_PASSWORD`(guest);
`RABBITMQ_VAULT_ENABLED`(false — PR1 supports only the false path);
`PAYMENT_GATEWAY_DEFAULT`(mock)/`STRIPE_ENABLED`/`PAYPAL_ENABLED`/`MOCK_GATEWAY_DELAY_MS`(500)/`MOCK_GATEWAY_FAILURE_RATE`(0.0);
`ENCRYPTION_ENABLED`(true)/`ENCRYPTION_KEY`;
`RATE_LIMIT_ENABLED`(true)/`RATE_LIMIT_PER_MINUTE`(60)/`RATE_LIMIT_PER_SECOND`(10)/`RATE_LIMIT_BURST`(20);
`OAUTH2_ENABLED`(false — read; API open in PR1)/`OAUTH2_ISSUER_URI`/`OAUTH2_JWK_SET_URI`.
Build the Postgres DSN from `DB_*`. Does payment publish/consume RabbitMQ events? **Check the Java
source** (`application.yml` has a `rabbitmq` block) — if there is a listener/publisher, reproduce its
contract; if RabbitMQ is only wired for future use and no events are published in the request path,
note that and keep the connection optional/best-effort (never fatal).

---

## Actuator / Health / Metrics (keep paths so k8s manifests stay unchanged)

Reproduce so `k8s/base/deployment.yaml` probes need **no change** (do not edit it in PR1):
- `GET /actuator/health` → `200 {"status":"UP"}`
- `GET /actuator/health/liveness` → `200 {"status":"UP"}`
- `GET /actuator/health/readiness` → `200 {"status":"UP"}` when Postgres ping succeeds, else `503`
- `GET /actuator/info` → `200`
- `GET /actuator/prometheus` → Prometheus exposition (prometheus/client_golang)

Listen on **8084**. Keep the image name `shopping-cart-payment` so the Deployment's `image:` and
prometheus annotations resolve unchanged.

---

## Cross-Cutting (middleware)

- **Security headers** on every response (match `SecurityConfig`/any header filter — read the
  source; reuse the order header set if identical).
- **Rate limiter:** per-client-IP token bucket (`golang.org/x/time/rate`) honouring
  `RATE_LIMIT_PER_SECOND` + `RATE_LIMIT_BURST`; over-limit → `429`. Exempt `/actuator/**`.
- **Structured logging** via zap; log process/refund at info with paymentId + correlationId;
  **never log card data**.
- **Auth seam (PR1):** `/actuator/**` open; with `OAUTH2_ENABLED=false` all `/api/**` open. Leave a
  clearly-marked seam where PR2 inserts JWT validation + the `@PreAuthorize` role checks
  (`PAYMENT_USER/READ/WRITE/ADMIN`, `PLATFORM_ADMIN`) per endpoint.

---

## Dockerfile + CI

- **`go/Dockerfile`**: multi-stage `golang:1.21-alpine` → `alpine:3.19`; `CGO_ENABLED=0`; non-root
  uid/gid 1000; `EXPOSE 8084`; healthcheck `wget --spider http://localhost:8084/actuator/health`;
  `ENTRYPOINT ["./payment-service"]`; build context `go/`. Leave the root Java `Dockerfile` untouched.
- **`.github/workflows/go-ci.yml`** (NEW additive — do NOT modify the Java `ci.yml`): runs on
  `go/**` changes; `gofmt -l` (fail on diff), `go vet ./...`, `golangci-lint run`,
  `go test ./... -race -cover`, then `docker build -f go/Dockerfile go`. Pin all actions to version
  tags (`actions/checkout@v4`, `actions/setup-go@v5`) — never `@main`/`@latest`.
  `permissions: contents: read` unless elevation is required.

---

## Tests (PR1 acceptance is local; full e2e gates on the preflight)

- **Unit** (`go test`, no network): payment + refund status transitions; over-refund + non-completed
  refund guards; idempotent replay returns the original; amount/decimal math at scale 4; mock-gateway
  success/failure paths; encryption round-trip (encrypt→decrypt) and last4/masking; handler error
  mapping (404/400 bodies).
- **Integration** (testcontainers-go or a documented `docker compose`): against throwaway Postgres —
  run the **Flyway migrations** (or apply `V1`/`V2` SQL) to create the schema, then exercise
  process→get→list→refund, asserting persisted `payments`/`refunds`/`transactions` rows and the
  idempotency unique-key behaviour. Gate behind a build tag / `testing.Short()` skip.

---

## Validation & Merge Sequencing

Identical to order: PR1 builds + unit/integration-tests **now**, but final acceptance (Playwright
e2e unchanged against the full stack) gates on the vCluster preflight (Phase 1b of
`docs/plans/v1.1.1-vcluster-preflight-webhook.md`). Java and Go ship **side by side** → PR1 carries
**zero deployment risk**: Java stays the deployed artifact, its CI stays green, the Go module is
inert until a later cutover PR repoints the image/ArgoCD. **Do NOT cut the deployed artifact to Go in
this PR.** State this dependency in the PR description.

---

## Definition of Done

- [ ] `feat/go-rewrite` branched from `origin/main`; Java tree (`src/**`, `pom.xml`, root
      `Dockerfile`, `db/migration/**`, existing `ci.yml`) **left intact**; Go module added under
      `go/`; `k8s/base/*` unchanged.
- [ ] HTTP contract, 4-table schema mapping, both status machines, idempotency, refund guards, mock
      gateway, and the AES-256-GCM encryption scheme reproduced exactly (verified against the Java
      source + Flyway migrations; field/column names copied verbatim).
- [ ] `gofmt -l` clean · `go vet ./...` clean · `golangci-lint run` clean · `go test ./... -race` green.
- [ ] `docker build` succeeds; binary runs and serves `/actuator/health` on 8084.
- [ ] CHANGELOG `[Unreleased]` entry added (Go rewrite PR1, functional core).
- [ ] Committed and pushed to `origin/feat/go-rewrite`; report SHA.
- [ ] memory-bank (`activeContext.md` + `progress.md` in k3d-manager) updated with the SHA + status.

**Commit message (exact):**
```
feat(payment): Go rewrite PR1 — functional core (HTTP + Postgres + mock gateway + refunds)
```

---

## What NOT to Do

- Do NOT remove, move, or modify the Java tree (`src/**`, `pom.xml`, root `Dockerfile`,
  `db/migration/**`) or the Java `ci.yml` — Java and Go ship side by side; Go goes under `go/` only.
- Do NOT implement Keycloak JWT/JWKS, the `@PreAuthorize` role matrix, or the Stripe/PayPal real
  gateways — that is PR2 (register Stripe/PayPal as disabled stubs).
- Do NOT create/migrate/drop DB tables or run Flyway from Go — map to the existing schema; live
  schema wins on conflict.
- Do NOT store or log full PAN/CVV — only `card_last4`/`card_brand`; PII columns are AES-256-GCM.
- Do NOT change `k8s/base/*` (keep paths/port 8084/image name compatible instead).
- Do NOT touch order, basket, product-catalog, frontend, the e2e suite, or k3d-manager.
- Do NOT create a PR (the user creates PRs); do NOT merge; do NOT skip hooks (`--no-verify`); do NOT
  commit to `main` — work on `feat/go-rewrite`.
- Do NOT guess a contract detail (column, JSON key, idempotency behaviour, GCM scheme). If the Java
  source is ambiguous or the live schema differs, STOP and report — do not invent.
