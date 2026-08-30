# Tier-1 E2E: order service 500s — `orders` table never created

## Symptom

The Tier-1 vCluster acceptance gate (`e2e_verify_vcluster`) reports `orders.spec`
failing wholesale (42 ✘ incl. retries). The list reporter shows only
`expect(order.id).toBeDefined() → Received: undefined` and repeated
`Order cleanup skipped: orders is not iterable`. Those are downstream symptoms, not
the cause.

## Root cause (ground truth, captured 2026-08-29)

Extracted the Playwright `results.json` from the live pod before teardown, then
port-forwarded the order service and replayed the exact test payload:

```text
POST /api/orders  → HTTP 500  {"code":"INTERNAL_ERROR","message":"Failed to create order"}
GET  /api/orders?customerId=… → HTTP 500  {"code":"INTERNAL_ERROR","message":"Failed to list orders"}
```

Order pod log (`deploy/order`, image
`ghcr.io/wilddog64/shopping-cart-order:sha-56033880a16e77ad5df0752eac8ad1c00c4a258a`):

```text
order/handler.go:163  failed to create order
error: ERROR: relation "orders" does not exist (SQLSTATE 42P01)
```

Two facts this corrects from earlier notes:

1. **The deployed order image `sha-56033880` is the GO rewrite, not Java** — the
   stacktrace is `github.com/wilddog64/shopping-cart-order/internal/order.(*Handler)`
   (gin, `MockAuthMiddleware`). The client contract (`order.id`, `status`, envelope
   unwrap) was never the problem.
2. **The Go order service ships no runtime migration.** The schema
   (`V1__init_schema.sql`) lives only under `go/internal/order/testdata/` and is applied
   by the integration test alone (`store_integration_test.go`). `main.go` runs no
   migrate step. Against a fresh DB the `orders`/`order_items` tables never exist.

The substrate's `scripts/etc/e2e/postgres.yaml` init creates the `orders` **database**
(`10-create-databases.sql`) but no **schema** — so every order DB op 500s. `orders.spec`
health check passes (service is up); every DB-touching test fails.

Payments.spec (27) failing is separate and structural — no payment manifest in Tier-1
(Tier-2/ACG's job); out of scope here.

## Fix (Tier-1 substrate — self-contained, no image rebuild)

Add an ordered second initdb script to the `postgres-initdb` ConfigMap that connects to
the `orders` database and applies the order schema. Postgres runs
`/docker-entrypoint-initdb.d/*.sql` via `psql` alphabetically, so `\connect orders`
works and `20-` runs after `10-` (DB exists first). Fresh ephemeral pod per run ⇒ initdb
always fires.

The DDL must match the **deployed** binary's expectations, not repo HEAD. The deployed
image `sha-56033880` is commit `5603388`, whose `order_items` INSERT writes
`(id, order_id, product_id, product_name, quantity, unit_price)` — **no `total_price`**.
Repo HEAD (and the newer `testdata/V1__init_schema.sql`) later added a `total_price NOT
NULL` column; copying that DDL made `order_items.total_price` `NOT NULL` while the deployed
binary never sets it, producing a second 500 (`null value in column "total_price" …
23502`). The substrate DDL therefore mirrors `git show 5603388:…/testdata/V1__init_schema.sql`
(order_items without `total_price`). When the substrate image tag is bumped, re-diff the
schema against that commit.

### Second cause, same fix (list filtering — NOT a bug)

`GET /api/orders?customerId=X` filters by `httpx.GetCustomerID(c)` (the `X-User-ID` header
via `MockAuthMiddleware`), not the query param. The e2e `OrderClient` sends
`X-User-ID: testUserId` on every call and creates orders under the same `testUserId`, so
list results line up — no change needed. (A bare `curl` without the header correctly returns
`[]`.)

### Live validation (2026-08-29, against the running vCluster substrate)

With the corrected schema applied to the live `orders` DB and the deployed order service:
`POST /api/orders → 201` with the full expected contract (`id`, `status:"PENDING"`,
`items[].subtotal`, `totalAmount`, `shippingAddress.{city,state}`, `currency:"USD"`,
top-level, no envelope); `GET …?customerId=X` with `X-User-ID` → `200` with the order.

## Durable follow-up (separate, service repo — filed as an issue)

The real defect is that the Go order service cannot start against a fresh database. The
substrate copy is a test-harness stopgap with drift risk. The proper fix is service-side:
the order service should run its migration on startup (embed `V1__init_schema.sql` out of
`testdata/`, apply on boot). That is a `shopping-cart-order` change (spec-not-direct,
branch/PR, rebuild+publish image, bump the substrate `newTag`) — tracked in
`docs/issues/2026-08-29-order-service-no-startup-migration.md`, not required to green the
Tier-1 gate.

## Acceptance

Rerun `E2E_IMAGE_TAG=sha-0c2505bbdc09b4ad12e5ea251ce9a8eeb7975e00
./scripts/k3d-manager e2e_verify_vcluster`; the `orders.spec` and order-dependent
cross-service tests pass. Remaining failures should reduce to the payment-absent set only.
