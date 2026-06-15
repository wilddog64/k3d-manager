# Shopping-Cart Order — Go Rewrite, PR1 (Functional Core)

**Work repo:** `shopping-cart-order`
**Branch (all work):** `feat/go-rewrite` — create from `origin/main`
**Spec repo:** k3d-manager (`k3d-manager-v1.7.1`) — this file only; do NOT edit k3d-manager otherwise.
**Type:** Feature (full service rewrite, phased). This is **PR1 of 2**.

---

## Why

The two JVM backends (order, payment) are the heaviest pods in the cart stack. Porting them
to Go (basket is already Go) cuts each from a ~512Mi JVM to a ~20–50Mi static binary — the
difference between the full stack fitting in a 2-core preflight vCluster or not. order goes
first (lower blast radius than the money path) to shake out the Go-port pattern before payment.

**Acceptance contract:** the existing `shopping-cart-e2e-tests` (Playwright) suite must pass
**unchanged** against the Go service. The Go port reproduces the observable contract — HTTP
surface, JSON shapes, DB schema, and RabbitMQ events — byte-for-byte. Behaviour is the spec;
the Java source is the reference.

**Phasing (decided with user 2026-06-15):**
- **PR1 (this spec):** functional core — HTTP + Postgres + RabbitMQ events + status machine +
  security headers + actuator/health + rate limiting. Runs with `OAUTH2_ENABLED=false`
  (service-level auth permits `/api/**`, matching the Java `SecurityConfig` fallback chain).
- **PR2 (follow-up spec, NOT this one):** Keycloak JWT/JWKS validation + role checks on
  `/api/orders/**`, toggled by `OAUTH2_ENABLED=true` (matches the Java `OAuth2SecurityConfig`
  chain). Do NOT implement JWT in PR1 — read `OAUTH2_*` env but leave the API open.

---

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md` in k3d-manager.
2. `git pull origin k3d-manager-v1.7.1` in k3d-manager to get this spec.
3. In `shopping-cart-order`: `git fetch origin && git checkout -b feat/go-rewrite origin/main`.
4. Read these Java files first — they are the contract you must reproduce exactly:
   - `src/main/java/com/shoppingcart/order/controller/OrderController.java` (HTTP surface)
   - `src/main/java/com/shoppingcart/order/service/OrderService.java` (status machine)
   - `src/main/java/com/shoppingcart/order/service/OrderEventPublisher.java` (events)
   - `src/main/java/com/shoppingcart/order/entity/*.java` (DB column names)
   - `src/main/java/com/shoppingcart/order/dto/*.java` (request/response JSON)
   - `src/main/java/com/shoppingcart/order/event/*.java` (envelope + each event's `@JsonProperty`
     field names and `TYPE`/`VERSION` constants — **copy these verbatim**)
   - `src/main/resources/application.yml`, `k8s/base/configmap.yaml` (env var names + defaults)
5. Reference repo for Go house style: `shopping-cart-basket/go.mod` — stack is gin,
   golang-jwt/jwt/v5, google/uuid, prometheus/client_golang, zap.

---

## Scope — PR1

**IN:** Go module added alongside the Java service (under `go/`); identical HTTP contract; Postgres persistence
against the existing schema; RabbitMQ event publishing; order status state machine; security
response headers; `/actuator/health*` + `/actuator/prometheus` endpoints; per-IP rate limiting;
Dockerfile; Go CI workflow; unit + integration tests.

**DEFERRED to PR2:** Keycloak JWT validation, role-based authorization, Vault-sourced RabbitMQ
credentials (PR1 uses static `RABBITMQ_USERNAME`/`PASSWORD`, `VAULT_ENABLED=false`).

**OUT (do not touch):** payment, basket, product-catalog, frontend; k3d-manager; the e2e suite.

---

## Target Layout — Java and Go SIDE BY SIDE (decided with user 2026-06-15)

**Keep the Java tree intact.** Do NOT delete `src/`, `pom.xml`, or the existing Java CI.
The Go service lives in a new `go/` subdirectory as its own module so the two builds never
collide. The deployed artifact stays Java until the preflight proves the Go e2e (see
Sequencing); the cutover (and any eventual promotion of `go/` to repo root + Java removal)
is a **later** PR, not this one.

A single Go module under `go/` (mirror basket's simplicity; do not over-package):

```
go/go.mod  go/go.sum
go/cmd/server/main.go           # wire config, db, rabbit, router, http server; graceful shutdown
go/internal/config/config.go    # env -> Config struct (all vars below)
go/internal/order/model.go      # Order, OrderItem, OrderStatus, ShippingAddress
go/internal/order/store.go      # Postgres CRUD via pgx (maps to existing schema)
go/internal/order/service.go    # createOrder/getOrder/listByCustomer/updateStatus/cancel + transitions
go/internal/order/handler.go    # gin handlers + request/response DTOs + error mapping
go/internal/events/publisher.go # amqp091-go publisher: envelope + 5 event types
go/internal/httpx/middleware.go # security headers, rate limiter, request logging
go/internal/health/health.go    # /actuator/health, /liveness, /readiness, /info, /prometheus
go/Dockerfile  go/Dockerfile.local
.github/workflows/go-ci.yml     # NEW additive Go workflow — do NOT touch the existing Java ci.yml
CHANGELOG.md                    # add [Unreleased] entry
```

**Untouched (Java side stays green):** `src/main/**`, `src/test/**`, `pom.xml`, the existing
`Dockerfile`, and the existing `.github/workflows/*.yml` Java/Maven workflow. They keep building
and the deployed image stays Java for now.

Pinned deps: `github.com/gin-gonic/gin`, `github.com/jackc/pgx/v5` (+ `/pgxpool`),
`github.com/rabbitmq/amqp091-go`, `github.com/google/uuid`, `github.com/shopspring/decimal`,
`go.uber.org/zap`, `github.com/prometheus/client_golang`, `golang.org/x/time/rate`.
**Money is `shopspring/decimal`** (scale 2) — never float64.

---

## HTTP API Contract (reproduce exactly)

Base path `/api/orders`. Content-Type `application/json`. All field names are **camelCase**
(Jackson default). Timestamps are ISO-8601 strings (e.g. `2026-06-15T04:11:52.123Z`), NOT
epoch. Decimals are JSON **numbers** with 2-decimal scale (e.g. `19.99`).

| Method & path | Body | Success | Errors |
|---|---|---|---|
| `POST /api/orders` | `CreateOrderRequest` | `201` + `OrderResponse` | `400` on validation |
| `GET /api/orders/{orderId}` | — | `200` + `OrderResponse` | `404` if not found |
| `GET /api/orders?customerId=X` | — | `200` + `[OrderResponse]` | — |
| `PATCH /api/orders/{orderId}/status` | `UpdateOrderStatusRequest` | `200` + `OrderResponse` | `404`; `400` invalid transition |
| `POST /api/orders/{orderId}/cancel` | `CancelOrderRequest` | `200` + `OrderResponse` | `404`; `400` if SHIPPED/COMPLETED |

Headers: `PATCH .../status` and `POST .../cancel` read optional `X-Correlation-ID`. `cancel`
also reads `X-User-ID` (default `"system"`). `orderId` is a UUID path param — malformed UUID → `400`.

**Error body** (matches Java `ErrorResponse`): `{"code":"...","message":"..."}`.
- not found → `404` `{"code":"NOT_FOUND","message":"Order not found: <id>"}`
- invalid state/transition / cancel-not-allowed → `400` `{"code":"INVALID_STATE","message":"..."}`
  - transition message: `Invalid status transition from <FROM> to <TO>`
  - cancel message: `Cannot cancel order in status: <STATUS>`

**Request shapes** (validation in parens → `400` if violated):
- `CreateOrderRequest`: `customerId` (non-blank), `items` (non-empty) of
  `{productId (non-blank), productName (non-blank), quantity (>0), unitPrice (>0)}`,
  `shippingAddress` (optional) `{street,city,state,postalCode,country}` (all non-blank if present),
  `currency` (optional, default `"USD"`).
- `UpdateOrderStatusRequest`: `status` (required enum), plus optional `paymentId`,
  `paymentMethod`, `trackingNumber`, `carrier`, `estimatedDelivery` (date `YYYY-MM-DD`).
- `CancelOrderRequest`: `reason` (non-blank).

**`OrderResponse` fields** (exact order/names): `id`, `customerId`, `status`, `items[]`
(`{id, productId, productName, quantity, unitPrice, subtotal}`), `totalAmount`, `currency`,
`shippingAddress` (object or `null`), `trackingNumber`, `carrier`, `createdAt`, `updatedAt`,
`paidAt`, `shippedAt`, `completedAt`, `cancelledAt`, `cancellationReason`. Null timestamps
serialize as `null`. `subtotal = unitPrice * quantity`; `totalAmount = Σ subtotal`.

---

## Data Model / DB Schema Contract

The schema is **owned externally** (Spring ran `ddl-auto: validate` — an init-SQL in the
data-layer creates it). **Do NOT create, migrate, or drop tables.** Connect and map to the
existing columns exactly:

**`orders`**: `id` (uuid pk), `customer_id` (text, not null), `status` (text enum, not null),
`total_amount` (numeric(10,2), not null), `currency` (varchar(3), not null), `tracking_number`,
`carrier`, `created_at` (timestamptz, not null), `updated_at`, `paid_at`, `shipped_at`,
`completed_at`, `cancelled_at`, `cancellation_reason`, and embedded address columns
`shipping_street`, `shipping_city`, `shipping_state`, `shipping_postal_code`, `shipping_country`.

**`order_items`**: `id` (uuid pk), `order_id` (uuid fk → orders.id, not null), `product_id`
(not null), `product_name` (not null), `quantity` (int, not null), `unit_price` (numeric(10,2), not null).

Generate `id` UUIDs application-side (`uuid.New()`), matching JPA `GenerationType.UUID`. Set
`created_at`/`updated_at` on insert; bump `updated_at` on every update (mirrors `@PrePersist`/`@PreUpdate`).
Insert order + items in one transaction. `status` stored as the enum NAME string
(`PENDING`/`PAID`/`PROCESSING`/`SHIPPED`/`COMPLETED`/`CANCELLED`).

> If the exact `numeric` scale or a column name differs from the above when you inspect the live
> schema (or the init-SQL referenced by `docs/plans/v1.2.0-fix-orders-init-sql-and-security-config.md`
> in k3d-manager), **the live schema wins** — match it and note the deviation in the PR. Do NOT
> guess; if you cannot determine a column, STOP and report.

---

## Order Status State Machine (exact)

Create → `PENDING`. Valid transitions (anything else → `400 INVALID_STATE`):

| From | Allowed To |
|---|---|
| PENDING | PAID, CANCELLED |
| PAID | PROCESSING, CANCELLED |
| PROCESSING | SHIPPED, CANCELLED |
| SHIPPED | COMPLETED |
| COMPLETED / CANCELLED | (none) |

`updateOrderStatus` side effects (then save, then publish):
- → `PAID`: set `paid_at=now`; publish `order.paid` with `paymentId`, `paymentMethod`.
- → `SHIPPED`: set `shipped_at=now`, `tracking_number`, `carrier`; `estimatedDelivery` defaults
  to `today+5d` if absent; publish `order.shipped`.
- → `COMPLETED`: set `completed_at=now`; publish `order.completed`.
- other valid target: save only, no event.

`cancelOrder`: reject with `400` if current status is `SHIPPED` or `COMPLETED`; else set
`CANCELLED`, `cancelled_at=now`, `cancellation_reason=reason`; publish `order.cancelled` with
`cancelledBy` and `refundInitiated=true` (hardcoded, matching Java).

---

## RabbitMQ Event Contract

Exchange `events` (topic, durable — declare idempotently, then publish). Routing key = event
`type`. Publish persistent (`DeliveryMode=2`), `content-type: application/json`. A publish
failure must be **logged, not fatal** — it does not roll back the DB write or change the HTTP
response (the Java path has a circuit breaker; PR1 mirrors best-effort).

**Envelope** (from `EventEnvelope.java`): `{"id":<uuid>, "type":<type>, "version":<ver>,
"timestamp":<iso8601>, "source":"order-service", "correlationId":<provided-or-new-uuid>,
"data":{...}}`.

Five events — **copy each event record's `@JsonProperty` field names and `TYPE`/`VERSION`
constants verbatim from the Java `event/*.java` classes**:
- `order.created` (v `1.0`) — `orderId, customerId, items[{productId,productName,quantity,unitPrice}],
  totalAmount, currency, shippingAddress{street,city,state,postalCode,country}|null`
- `order.paid` — `orderId, paymentId, totalAmount, currency, paymentMethod, paidAt`
- `order.shipped` — `orderId, trackingNumber, carrier, shippedAt, estimatedDelivery`
- `order.completed` — `orderId, completedAt`
- `order.cancelled` — `orderId, reason, cancelledBy, cancelledAt, refundInitiated`

`orderId` is the order UUID as a string. Confirm field names against the source — do not assume.

---

## Config / Env Vars (read all; same names + defaults as `application.yml`)

`SERVER_PORT`(8080); `DB_HOST`/`DB_PORT`(5432)/`DB_NAME`(orders)/`DB_USERNAME`(postgres)/`DB_PASSWORD`(postgres);
`RABBITMQ_HOST`/`RABBITMQ_PORT`(5672)/`RABBITMQ_VHOST`(/)/`RABBITMQ_USERNAME`(guest)/`RABBITMQ_PASSWORD`(guest)/`RABBITMQ_USE_TLS`(false);
`RATE_LIMIT_PER_MINUTE`(100)/`RATE_LIMIT_PER_SECOND`(20)/`RATE_LIMIT_BURST`(50);
`OAUTH2_ENABLED`(false — read, unused in PR1)/`OAUTH2_ISSUER_URI`/`OAUTH2_JWK_SET_URI`;
`VAULT_ENABLED`(false — PR1 supports only the false path). Build the Postgres DSN from the
`DB_*` vars; build the AMQP URI from the `RABBITMQ_*` vars.

---

## Actuator / Health / Metrics (keep paths so k8s manifests stay unchanged)

The existing `k8s/base/deployment.yaml` probes hit these — reproduce them so the manifest needs
**no change** (do not edit deployment.yaml in PR1):
- `GET /actuator/health` → `200 {"status":"UP"}`
- `GET /actuator/health/liveness` → `200 {"status":"UP"}`
- `GET /actuator/health/readiness` → `200 {"status":"UP"}` when Postgres ping succeeds, else `503 {"status":"DOWN"}`
- `GET /actuator/info` → `200`
- `GET /actuator/prometheus` → Prometheus exposition (prometheus/client_golang handler)

Listen on port **8080**. Keep the container image name `shopping-cart-order` so the Deployment's
`image:` and prometheus annotations resolve unchanged.

---

## Cross-Cutting (middleware)

- **Security headers** on every response (from Java `SecurityConfig`): `X-XSS-Protection: 1; mode=block`,
  `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`,
  `Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; font-src 'self'; frame-ancestors 'none'; form-action 'self'`,
  `Referrer-Policy: strict-origin-when-cross-origin`,
  `Strict-Transport-Security: max-age=31536000; includeSubDomains`,
  `Permissions-Policy: geolocation=(), microphone=(), camera=()`.
- **Rate limiter**: per-client-IP token bucket (`golang.org/x/time/rate`) honoring
  `RATE_LIMIT_PER_SECOND` + `RATE_LIMIT_BURST`; over-limit → `429`. Exempt `/actuator/**`.
- **Structured logging** via zap; log create/update/cancel at info with orderId + correlationId.
- **Auth (PR1):** `/api/**` is open (no JWT). Leave a clearly-marked seam where PR2 inserts the
  JWT middleware when `OAUTH2_ENABLED=true`.

---

## Dockerfile + CI

- **`go/Dockerfile`**: multi-stage `golang:1.21-alpine` builder → `alpine:3.19` runtime; `CGO_ENABLED=0`;
  non-root uid/gid 1000; `EXPOSE 8080`; healthcheck `wget --spider http://localhost:8080/actuator/health`;
  `ENTRYPOINT ["./order-service"]`; build context `go/`. (Mirror basket's Dockerfile; no GitHub-Packages
  Maven secret needed.) Leave the existing root Java `Dockerfile` untouched.
- **`.github/workflows/go-ci.yml`** (NEW — additive; do NOT modify the existing Java `ci.yml`): runs on
  changes under `go/**`; steps `gofmt -l` (fail on diff), `go vet ./...`, `golangci-lint run`,
  `go test ./... -race -cover`, then `docker build -f go/Dockerfile go`. Set `working-directory: go`
  (or `cd go`) for the Go steps. Pin all actions to version tags (`actions/checkout@v4`,
  `actions/setup-go@v5`, etc.) — never `@main`/`@latest`. `permissions: contents: read` unless elevation
  is required.

---

## Tests (PR1 acceptance is local; full e2e gates on the preflight — see Sequencing)

- **Unit** (`go test`, no network): the status-transition matrix (every from→to, valid and
  invalid), `subtotal`/`totalAmount` math with decimals, `cancel` guard on SHIPPED/COMPLETED,
  handler error mapping (404/400 bodies), envelope construction + each event payload shape.
- **Integration**: against a throwaway Postgres + RabbitMQ (testcontainers-go, or a documented
  `docker compose` the test spins up) — create→get→list→status-walk(PENDING→PAID→PROCESSING→
  SHIPPED→COMPLETED)→cancel paths, asserting persisted rows and that the 5 events land on `events`
  with the right routing keys + envelope. Gate behind a build tag or `testing.Short()` skip so unit
  tests run without Docker.

---

## Validation & Merge Sequencing (important)

PR1 can be built and unit/integration-tested **now**, but its **final acceptance** — the
Playwright `shopping-cart-e2e-tests` passing unchanged against the full stack — gates on the
vCluster preflight (Phase 1b of `docs/plans/v1.1.1-vcluster-preflight-webhook.md`), which deploys
the stack + runs e2e. Because Java and Go ship **side by side**, PR1 carries **zero deployment
risk**: the Java service remains the deployed artifact, its CI stays green, and the Go module is
inert until a later cutover PR repoints the image/ArgoCD. **Do NOT cut the deployed artifact to Go
in this PR.** Land PR1 as the Go implementation + Go CI + tests, living alongside Java; the cutover
(and any eventual Java removal / promotion of `go/` to root) happens only after the preflight proves
e2e green against the Go build. State this dependency in the PR description.

---

## Definition of Done

- [ ] `feat/go-rewrite` branched from `origin/main`; Java tree (`src/**`, `pom.xml`, root `Dockerfile`,
      existing `ci.yml`) **left intact**; new Go module added under `go/` alongside it; `k8s/base/*`
      unchanged.
- [ ] HTTP contract, DB schema mapping, status machine, and 5 events reproduced exactly (verified
      against the Java source, field names copied verbatim from `event/*.java`).
- [ ] `gofmt -l` clean · `go vet ./...` clean · `golangci-lint run` clean · `go test ./... -race` green.
- [ ] `docker build` succeeds; binary runs and serves `/actuator/health` on 8080.
- [ ] CHANGELOG `[Unreleased]` entry added (Go rewrite PR1, functional core).
- [ ] Committed and pushed to `origin/feat/go-rewrite`; report SHA.
- [ ] memory-bank (`activeContext.md` + `progress.md` in k3d-manager) updated with the SHA + status.

**Commit message (exact):**
```
feat(order): Go rewrite PR1 — functional core (HTTP + Postgres + RabbitMQ events)
```

---

## What NOT to Do

- Do NOT remove, move, or modify the Java tree (`src/**`, `pom.xml`, root `Dockerfile`) or the
  existing Java `ci.yml` — Java and Go ship side by side; Go goes under `go/` only.
- Do NOT implement Keycloak JWT/JWKS or role checks — that is PR2.
- Do NOT create/migrate/drop DB tables — map to the existing schema; live schema wins on conflict.
- Do NOT change `k8s/base/deployment.yaml`/`configmap.yaml`/`service.yaml` (keep paths/port/image
  name compatible instead).
- Do NOT touch payment, basket, product-catalog, frontend, the e2e suite, or k3d-manager.
- Do NOT create a PR (the user creates PRs); do NOT merge; do NOT skip hooks (`--no-verify`); do
  NOT commit to `main` — work on `feat/go-rewrite`.
- Do NOT guess a contract detail (column, JSON key, event field). If the Java source is ambiguous
  or the live schema differs, STOP and report — do not invent.
