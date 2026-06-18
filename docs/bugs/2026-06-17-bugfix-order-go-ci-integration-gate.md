# Bugfix: order Go rewrite — add DB schema + gate integration tests in CI

**Spec repo:** k3d-manager (`k3d-manager-v1.7.1`)
**Work repo:** `shopping-cart-order`
**Branch (all work repos):** `feat/go-rewrite` (existing PR #33 — do NOT create a new branch)
**Files:** `src/main/resources/db/migration/V1__init_schema.sql` (new),
`go/internal/order/store_integration_test.go`, `.github/workflows/go-ci.yml`

---

## Problem

The order Go rewrite has two build-tagged integration tests
(`go/internal/order/store_integration_test.go`,
`go/internal/events/publisher_integration_test.go`, both `//go:build integration`) that CI
never runs — `go-ci`'s only test step is `go test ./... -race -cover`, which compiles out the
`integration` tag. Worse, the Postgres test **cannot pass even when run by hand**, because the
order repo has **no database schema anywhere**:

- No `.sql` / migration files exist in the repo (payment ships
  `src/main/resources/db/migration/V1__*.sql`; order ships none).
- `application.yml` is `ddl-auto: validate` — Hibernate validates an existing schema, it does
  not create one.
- `NewPostgresStore` only opens a pool and pings; it does not create tables.
- The Go integration test does not seed anything.

So `TestPostgresStoreRoundTrip` fails on a clean database, and there is nothing in the repo
that would ever create the `orders` / `order_items` tables.

**Root cause:** (1) the order repo is missing its DB schema entirely, and (2) `go-ci.yml`
omits `-tags integration`, so the gap was invisible.

**Verified (Claude, 2026-06-17, runtime):**
- `go test -tags integration -run TestPostgresStoreRoundTrip ./internal/order/...` against a
  blank `postgres:16-alpine` →
  `store_integration_test.go:42: create: ERROR: relation "orders" does not exist (SQLSTATE 42P01)`
  → `--- FAIL`.
- `go test -tags integration -run TestRabbitPublisherPublishesOrderCreated ./internal/events/...`
  against a vanilla `rabbitmq:3.13` → `--- PASS` (publisher declares its own exchange; no schema
  needed).

---

## Reproduction

```bash
cd shopping-cart-order/go
# blank Postgres, no schema applied
export TEST_POSTGRES_DSN='postgres://postgres:postgres@localhost:5432/orders?sslmode=disable'
go test -tags integration -count=1 -run TestPostgresStoreRoundTrip ./internal/order/...
```

**Expected:** PASS.
**Actual (current):** FAIL — `relation "orders" does not exist (SQLSTATE 42P01)`.

---

## Fix

Add the missing schema as a Flyway migration, have the Go Postgres integration test self-seed
it (mirroring payment's pattern), and add a CI job that runs both integration tests against
Postgres + RabbitMQ service containers.

### Change 1 — NEW FILE `src/main/resources/db/migration/V1__init_schema.sql`

The columns/types below are derived from the Go store's SQL constants
(`insertOrderSQL`, `getOrderSQL`, `listItemsSQL`, `insertOrderItemSQL`) — every column the Go
store reads/writes must exist with a compatible type.

```sql
CREATE TABLE IF NOT EXISTS orders (
    id                   UUID PRIMARY KEY,
    customer_id          VARCHAR(255)  NOT NULL,
    status               VARCHAR(32)   NOT NULL,
    total_amount         NUMERIC(19,2) NOT NULL,
    currency             VARCHAR(3)    NOT NULL,
    tracking_number      VARCHAR(255),
    carrier              VARCHAR(255),
    created_at           TIMESTAMPTZ   NOT NULL,
    updated_at           TIMESTAMPTZ   NOT NULL,
    paid_at              TIMESTAMPTZ,
    shipped_at           TIMESTAMPTZ,
    completed_at         TIMESTAMPTZ,
    cancelled_at         TIMESTAMPTZ,
    cancellation_reason  VARCHAR(1024),
    shipping_street      VARCHAR(255),
    shipping_city        VARCHAR(255),
    shipping_state       VARCHAR(255),
    shipping_postal_code VARCHAR(64),
    shipping_country     VARCHAR(255)
);

CREATE TABLE IF NOT EXISTS order_items (
    id           UUID PRIMARY KEY,
    order_id     UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id   VARCHAR(255) NOT NULL,
    product_name VARCHAR(255) NOT NULL,
    quantity     INTEGER      NOT NULL,
    unit_price   NUMERIC(19,2) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders (customer_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items (order_id);
```

> **Reconcile with the Java entities before finalizing types.** This migration is on the real
> Flyway path, so the Java service's `ddl-auto: validate` will validate against it. Read the JPA
> entity classes (`Order`, `OrderItem` — under `src/main/java/.../**`) and adjust column
> **types / nullability / lengths** so Hibernate validate passes, WITHOUT removing or renaming
> any column the Go store uses (the Go column contract above is fixed). If the Java entity needs
> a different precision/length, prefer the Java-required type as long as it stays compatible with
> the Go scan (e.g. `NUMERIC` scale ≥ 2, `TIMESTAMPTZ`/`TIMESTAMP` for the time columns).

### Change 2 — `go/internal/order/store_integration_test.go`: self-seed the migration

**Exact old block (lines 5–28):**

```go
import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/shopspring/decimal"
)

func TestPostgresStoreRoundTrip(t *testing.T) {
	dsn := os.Getenv("TEST_POSTGRES_DSN")
	if dsn == "" {
		t.Skip("TEST_POSTGRES_DSN not set")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	store, err := NewPostgresStore(ctx, dsn)
	if err != nil {
		t.Fatalf("new store: %v", err)
	}
	defer store.Close()
```

**Exact new block:**

```go
import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/shopspring/decimal"
)

func TestPostgresStoreRoundTrip(t *testing.T) {
	dsn := os.Getenv("TEST_POSTGRES_DSN")
	if dsn == "" {
		t.Skip("TEST_POSTGRES_DSN not set")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	migrationPool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect postgres: %v", err)
	}
	for _, rel := range []string{
		filepath.Join("..", "..", "..", "src", "main", "resources", "db", "migration", "V1__init_schema.sql"),
	} {
		sqlBytes, readErr := os.ReadFile(rel)
		if readErr != nil {
			migrationPool.Close()
			t.Fatalf("read migration %s: %v", rel, readErr)
		}
		if _, execErr := migrationPool.Exec(ctx, string(sqlBytes)); execErr != nil {
			migrationPool.Close()
			t.Fatalf("apply migration %s: %v", rel, execErr)
		}
	}
	migrationPool.Close()

	store, err := NewPostgresStore(ctx, dsn)
	if err != nil {
		t.Fatalf("new store: %v", err)
	}
	defer store.Close()
```

> The test file lives at `go/internal/order/`, so `../../../src/main/resources/...` resolves to
> the repo-root `src/` tree (same depth as payment's integration test). `go test` runs the binary
> with CWD = the package dir, so this path holds regardless of where `go test` is invoked.

### Change 3 — `.github/workflows/go-ci.yml`: add an `integration` job

**Exact old block (lines 45–50, end of the `go-ci` job / end of file):**

```yaml
      - name: Go test
        run: go test ./... -race -cover

      - name: Docker build
        working-directory: .
        run: docker build -f go/Dockerfile go
```

**Exact new block:**

```yaml
      - name: Go test
        run: go test ./... -race -cover

      - name: Docker build
        working-directory: .
        run: docker build -f go/Dockerfile go

  integration:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: go
    services:
      postgres:
        image: postgres:16-alpine
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: orders
        ports:
          - 5432:5432
        options: >-
          --health-cmd "pg_isready -U postgres -d orders"
          --health-interval 5s
          --health-timeout 5s
          --health-retries 10
      rabbitmq:
        image: rabbitmq:3.13
        env:
          RABBITMQ_DEFAULT_USER: app
          RABBITMQ_DEFAULT_PASS: app
        ports:
          - 5672:5672
        options: >-
          --health-cmd "rabbitmq-diagnostics -q ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 15
    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Go
        uses: actions/setup-go@v5
        with:
          go-version-file: go/go.mod
          cache: true

      - name: Integration tests
        run: go test -tags integration -count=1 ./internal/order/... ./internal/events/...
        env:
          TEST_POSTGRES_DSN: postgres://postgres:postgres@localhost:5432/orders?sslmode=disable
          TEST_RABBITMQ_URI: amqp://app:app@localhost:5672/
```

> RabbitMQ uses non-`guest` creds (`app`/`app`) on purpose: the default `guest` user is
> restricted to loopback, and a service-container connection is not loopback from the broker's
> view. Non-guest creds avoid `ACCESS_REFUSED`.

---

## Files Changed

| File | Change |
|------|--------|
| `src/main/resources/db/migration/V1__init_schema.sql` | NEW — `orders` + `order_items` schema |
| `go/internal/order/store_integration_test.go` | Self-seed `V1__init_schema.sql` before opening the store |
| `.github/workflows/go-ci.yml` | Add an `integration` job (Postgres + RabbitMQ) running `-tags integration` |

---

## Rules

- Touch ONLY the three files above. Do NOT modify `store.go`, `publisher.go`,
  `publisher_integration_test.go`, `config.go`, `handler.go`, or any other file.
- Reconcile the migration column types with the Java JPA entities so `ddl-auto: validate` passes
  (see note under Change 1). Read the entities — do not guess.
- Pin all actions to a version tag (`actions/checkout@v4`, `actions/setup-go@v5`,
  `golangci/golangci-lint-action@v6`) and service images to pinned tags
  (`postgres:16-alpine`, `rabbitmq:3.13`) — no `@main`/`@latest`/floating tags.
- Keep `permissions: contents: read` — the new job must NOT add an elevated `permissions` block.
- The DB/MQ passwords are throwaway service-container literals — do NOT route through Vault.
- `gofmt -l go/internal/order/store_integration_test.go` — must print nothing.
- `go vet -tags integration ./...` (from `go/`) — zero new findings.
- YAML parses: `python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/go-ci.yml"))'`
  exits 0 (from repo root).
- Run `_agent_audit` before reporting done.

---

## Definition of Done

- [ ] `V1__init_schema.sql` created with the `orders` + `order_items` schema, types reconciled
      with the Java entities
- [ ] `store_integration_test.go` self-seeds the migration; existing assertions unchanged
- [ ] `go-ci.yml` has the new `integration` job exactly as specified; the existing `go-ci` job
      is byte-for-byte unchanged
- [ ] Local run green against service containers:
      `go test -tags integration -count=1 ./internal/order/... ./internal/events/...`
      (both `TestPostgresStoreRoundTrip` and `TestRabbitPublisherPublishesOrderCreated` PASS)
- [ ] `go test ./... -race -cover` (unit suite, no tag) — still green
- [ ] Java build/tests still green (`mvn test` / the `go-ci`+Java CI on the PR) — confirms the
      migration did not break Hibernate `ddl-auto: validate`
- [ ] `gofmt`, `go vet -tags integration ./...`, YAML parse, `_agent_audit` — all clean
- [ ] Committed and pushed to `feat/go-rewrite` in `shopping-cart-order` (updates PR #33)
- [ ] After push, the `Go CI` workflow run shows the new `integration` job **green** on the
      branch (confirm it ran and passed — do NOT report done on the push alone)
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(order): add DB schema and gate Go integration tests in CI

The order Go rewrite had no DB schema (no migrations, ddl-auto:validate
only), so the Postgres integration test could never pass, and go-ci ran
only `go test ./...` which compiles out the //go:build integration tests.
Add V1__init_schema.sql for orders/order_items, self-seed it in the Go
store integration test, and add an integration job that runs the tagged
tests against Postgres + RabbitMQ service containers.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

---

## What NOT to Do

- Do NOT create a PR or a new branch — PR #33 already exists on `feat/go-rewrite`; pushing updates it
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed targets
- Do NOT change the existing `go-ci` job, `store.go`, or either integration test's assertions
- Do NOT add an elevated `permissions` block to the new job
- Do NOT commit to `main` — work on `feat/go-rewrite`
