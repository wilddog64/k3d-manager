# Bugfix: order Go rewrite — PR #33 GitGuardian + Copilot findings

**Work repo:** `shopping-cart-order` (NOT k3d-manager)
**Branch (all work):** `feat/go-rewrite` (existing — the PR #33 branch; do NOT create a new branch)
**PR:** https://github.com/wilddog64/shopping-cart-order/pull/33
**Files:** `go/internal/config/config.go`, `go/internal/events/publisher.go`, `go/internal/order/store.go`

---

## Problem

PR #33 (order Go rewrite PR1) is green on Java Build&Test, Checkstyle, and go-ci, but:

1. **GitGuardian Security Check FAILS (blocks merge)** — flags a hardcoded `DB_PASSWORD`
   default `"postgres"` at `config.go:45`. The check is the GitGuardian **GitHub App**
   (not a ggshield CI job), so it only clears when the secret is removed from a new commit
   (decision: remove the default — code-only fix).
2. **Copilot inline findings a/b/c** to fix now (d/e are auth, deferred to PR2):
   - a — `config.go:73` `sslmode=disable` is hardcoded.
   - b — `publisher.go:312` custom `Dial` closure (plain `net.DialTimeout`) is a non-canonical
     dialer that Copilot flags as bypassing the library's `amqps://` TLS handling.
   - c — `store.go:160` `Update` ignores the command tag, so updating a non-existent order
     ID returns `nil` instead of `ErrOrderNotFound`.

**Root cause:** PR1 reproduced the Java dev defaults verbatim (`${DB_PASSWORD:postgres}`,
implicit no-SSL JDBC) and used a hand-rolled AMQP dialer; the Update path never checked rows
affected.

**NOT in scope (defer to PR2):** Copilot d (`handler.go:98` `customerId` from body) and
e (`handler.go:193` list by `customerId` query param) are authorization concerns. PR1 runs
`OAUTH2_ENABLED=false`; customer identity from the authenticated JWT principal is PR2. Do NOT
change `handler.go`. (Claude posts the deferral replies on the Copilot threads.)

---

## Reproduction

- `gh pr checks 33 --repo wilddog64/shopping-cart-order` → `GitGuardian Security Checks  fail`.
- GitGuardian incident 27408404: Generic Password, `go/internal/config/config.go` R45.

---

## Fix

### Change 1 — `config.go`: remove hardcoded DB_PASSWORD default (clears GitGuardian)

**Exact old block (line 45):**

```go
		DBPassword: getEnv("DB_PASSWORD", "postgres"),
```

**Exact new block:**

```go
		DBPassword: getEnv("DB_PASSWORD", ""),
```

> Leave `DBUsername: getEnv("DB_USERNAME", "postgres")` unchanged — a username is not a
> secret and GitGuardian does not flag it. Operationally safe: k8s/ESO injects the real
> `DB_PASSWORD`; the Java side keeps its own `${DB_PASSWORD:postgres}` default (this is a
> deliberate, minor Go-only deviation to satisfy the secret scanner + the repo "never
> hardcode secrets" rule).

### Change 2 — `config.go`: make sslmode env-configurable (Copilot a)

Add a `DBSSLMode` field to the `Config` struct.

**Exact old block (struct, lines 13–17):**

```go
	DBHost     string
	DBPort     string
	DBName     string
	DBUsername string
	DBPassword string
```

**Exact new block:**

```go
	DBHost     string
	DBPort     string
	DBName     string
	DBUsername string
	DBPassword string
	DBSSLMode  string
```

Populate it in `Load()`.

**Exact old block (lines 43–45):**

```go
		DBName:     getEnv("DB_NAME", "orders"),
		DBUsername: getEnv("DB_USERNAME", "postgres"),
		DBPassword: getEnv("DB_PASSWORD", ""),
```

**Exact new block:**

```go
		DBName:     getEnv("DB_NAME", "orders"),
		DBUsername: getEnv("DB_USERNAME", "postgres"),
		DBPassword: getEnv("DB_PASSWORD", ""),
		DBSSLMode:  getEnv("DB_SSLMODE", "disable"),
```

> Note: Change 1 already set the `DBPassword` line to `""`; the old block above reflects the
> post-Change-1 state. Apply Change 1 first.

Use it in `DatabaseURI()`.

**Exact old block (line 72):**

```go
	}).String() + "?sslmode=disable"
```

**Exact new block:**

```go
	}).String() + "?sslmode=" + c.DBSSLMode
```

> Default stays `disable`, so runtime behavior is unchanged (and still matches the Java
> pgjdbc no-SSL default); operators can now set `DB_SSLMODE=require`/`verify-full` without a
> code change.

### Change 3 — `publisher.go`: use the library's canonical dialer (Copilot b)

**Exact old block (lines 311–315):**

```go
	conn, err := amqp.DialConfig(p.uri, amqp.Config{
		Dial: func(network, addr string) (net.Conn, error) {
			return net.DialTimeout(network, addr, 5*time.Second)
		},
	})
```

**Exact new block:**

```go
	conn, err := amqp.DialConfig(p.uri, amqp.Config{
		Dial: amqp.DefaultDial(5 * time.Second),
	})
```

> `amqp.DefaultDial` is the library's own dialer (sets the connection deadline and
> interoperates with `DialConfig`'s `amqps://` TLS wrapping), preserving the 5s timeout while
> removing the hand-rolled closure Copilot flagged. After this edit `net` is no longer used —
> **remove `"net"` from the import block** in `publisher.go` (gofmt/go vet/build will fail
> otherwise). `time` stays (used by `5 * time.Second`).

### Change 4 — `store.go`: return ErrOrderNotFound when no row updated (Copilot c)

**Exact old block (lines 172–194):**

```go
	if _, err = tx.Exec(ctx, updateOrderSQL,
		order.CustomerID,
		string(order.Status),
		order.TotalAmount.StringFixed(2),
		order.Currency,
		stringOrNil(order.TrackingNumber),
		stringOrNil(order.Carrier),
		order.CreatedAt,
		order.UpdatedAt,
		timeOrNil(order.PaidAt),
		timeOrNil(order.ShippedAt),
		timeOrNil(order.CompletedAt),
		timeOrNil(order.CancelledAt),
		stringOrNil(order.CancellationReason),
		addressOrNil(order.ShippingAddress, "street"),
		addressOrNil(order.ShippingAddress, "city"),
		addressOrNil(order.ShippingAddress, "state"),
		addressOrNil(order.ShippingAddress, "postalCode"),
		addressOrNil(order.ShippingAddress, "country"),
		order.ID,
	); err != nil {
		return err
	}
```

**Exact new block:**

```go
	tag, err := tx.Exec(ctx, updateOrderSQL,
		order.CustomerID,
		string(order.Status),
		order.TotalAmount.StringFixed(2),
		order.Currency,
		stringOrNil(order.TrackingNumber),
		stringOrNil(order.Carrier),
		order.CreatedAt,
		order.UpdatedAt,
		timeOrNil(order.PaidAt),
		timeOrNil(order.ShippedAt),
		timeOrNil(order.CompletedAt),
		timeOrNil(order.CancelledAt),
		stringOrNil(order.CancellationReason),
		addressOrNil(order.ShippingAddress, "street"),
		addressOrNil(order.ShippingAddress, "city"),
		addressOrNil(order.ShippingAddress, "state"),
		addressOrNil(order.ShippingAddress, "postalCode"),
		addressOrNil(order.ShippingAddress, "country"),
		order.ID,
	)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		err = ErrOrderNotFound
		return err
	}
```

> `Update` uses a named return `(err error)` and a deferred `tx.Rollback` on `err != nil`.
> Assign to the named `err` (do not shadow with a new variable) so the missing-row path
> rolls back instead of committing a no-op. `tag, err :=` at function top scope reuses the
> named return (`tag` is the only new var) — this is valid Go.

---

## Files Changed

| File | Change |
|------|--------|
| `go/internal/config/config.go` | drop `DB_PASSWORD` default; add `DBSSLMode` field + `DB_SSLMODE` env (default `disable`); use it in `DatabaseURI()` |
| `go/internal/events/publisher.go` | `Dial` → `amqp.DefaultDial(5*time.Second)`; remove unused `net` import |
| `go/internal/order/store.go` | `Update` checks `RowsAffected()`, returns `ErrOrderNotFound` on 0 |

**Do NOT touch** `go/internal/order/handler.go` (Copilot d/e are PR2 auth — deferred).

---

## Rules

- Validate via Dockerized Go toolchain (host has no Go), same as PR1:
  - `docker run --rm -v "$PWD":/w -w /w/go golang:1.21 gofmt -l .` → empty
  - `docker run --rm -v "$PWD":/w -w /w/go golang:1.21 go vet ./...` → clean
  - `docker run --rm -v "$PWD":/w -w /w/go golang:1.21 go test ./... -race -cover` → all pass
  - `docker build -f go/Dockerfile go` → OK
- Only the three listed files change. No new files (no `.gitguardian.yaml` — there is no
  secret left to ignore). No `handler.go` edits.
- Do NOT weaken any other default or touch the Java tree.

---

## Definition of Done

- [ ] `config.go`: `DB_PASSWORD` default removed; `DBSSLMode`/`DB_SSLMODE` added; `DatabaseURI()` uses it
- [ ] `publisher.go`: canonical `amqp.DefaultDial`; `net` import removed
- [ ] `store.go`: `Update` returns `ErrOrderNotFound` when `RowsAffected()==0`
- [ ] gofmt/vet/`go test -race`/`docker build` all green (Dockerized)
- [ ] Committed and pushed to `feat/go-rewrite` — verify on `origin/feat/go-rewrite`
- [ ] memory-bank `activeContext.md` + `progress.md` updated with the commit SHA
- [ ] Report the SHA + paste the memory-bank lines updated

**Commit message (exact):**
```
fix(order): remove hardcoded DB_PASSWORD default; configurable sslmode; canonical AMQP dial; Update row-count guard
```

---

## What NOT to Do

- Do NOT create a PR (PR #33 already exists; pushing to `feat/go-rewrite` updates it)
- Do NOT create a new branch — work on existing `feat/go-rewrite`
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the three listed targets (esp. NOT `handler.go`)
- Do NOT commit to `main`
- Do NOT add `.gitguardian.yaml` or any ignore file — the fix removes the secret outright
