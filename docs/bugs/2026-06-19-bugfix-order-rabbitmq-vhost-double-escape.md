# Bugfix: order Go rewrite — RabbitMQURI double-escapes the vhost (Copilot PR #33)

**Work repo:** `shopping-cart-order` — branch `feat/go-rewrite` (continue the existing branch; do NOT
branch anew, do NOT open a PR — #33 is already open against this branch).
**Spec lives in:** `k3d-manager` (`k3d-manager-v1.7.1`) — this file only.
**Type:** Bug fix for the one unresolved Copilot finding on order #33 (HEAD `1b84696`).

---

## Problem

`Config.RabbitMQURI()` (`go/internal/config/config.go`) **double-escapes** the AMQP vhost. It
pre-escapes with `url.PathEscape(c.RabbitMQVHost)` and assigns the result to `url.URL.Path`. But
`url.URL.Path` is the **decoded** path — `URL.String()` escapes it again, so a `%` becomes `%25`.

**Root cause:** the default `RABBITMQ_VHOST` is `"/"` (`config.go:51`). `url.PathEscape("/")` → `%2F`,
assigned to `Path` → `URL.String()` re-escapes → `amqp://user:pass@host:port/%252F`. RabbitMQ decodes
`%252F` to the literal string `%2F` and treats it as a vhost named `%2F`, which does not exist →
connection fails (`vhost not found`). This breaks the **default** deployment, not an edge case.

**Copilot thread:** `go/internal/config/config.go:92` (`PRRT_kwDORUakXc6Kz8rH`).

---

## Reproduction

```go
c := Config{RabbitMQHost: "rmq", RabbitMQPort: "5672",
    RabbitMQUsername: "u", RabbitMQPassword: "p", RabbitMQVHost: "/"}
fmt.Println(c.RabbitMQURI())
// actual:   amqp://u:p@rmq:5672/%252F   <- broken (double-escaped)
// expected: amqp://u:p@rmq:5672/%2F     <- correct (vhost "/")
```

---

## Before You Start

1. `git pull origin k3d-manager-v1.7.1` in k3d-manager and read this spec in full.
2. In `shopping-cart-order`: `git fetch origin && git checkout feat/go-rewrite && git pull origin
   feat/go-rewrite` (extend HEAD `1b84696`).
3. Read `go/internal/config/config.go` before editing. `fmt` and `net/url` are already imported
   (both used by `DatabaseURI()`).

---

## Fix — `go/internal/config/config.go`: set `Path` (decoded) + `RawPath` (encoded)

Let `net/url` do the escaping exactly once. Set `u.Path` to the **decoded** path and `u.RawPath` to
the **encoded** path; `URL.String()` then emits `RawPath` verbatim (it is a valid encoding of `Path`),
producing `/%2F` for the default vhost and `/<name>` for a named vhost.

**Exact old block:**

```go
func (c Config) RabbitMQURI() string {
	scheme := "amqp"
	if c.RabbitMQUseTLS {
		scheme = "amqps"
	}
	escapedVHost := url.PathEscape(c.RabbitMQVHost)
	if escapedVHost == "" {
		escapedVHost = "%2F"
	}
	return (&url.URL{
		Scheme: scheme,
		User:   url.UserPassword(c.RabbitMQUsername, c.RabbitMQPassword),
		Host:   fmt.Sprintf("%s:%s", c.RabbitMQHost, c.RabbitMQPort),
		Path:   "/" + escapedVHost,
	}).String()
}
```

**Exact new block:**

```go
func (c Config) RabbitMQURI() string {
	scheme := "amqp"
	if c.RabbitMQUseTLS {
		scheme = "amqps"
	}
	vhost := c.RabbitMQVHost
	if vhost == "" {
		vhost = "/"
	}
	u := &url.URL{
		Scheme: scheme,
		User:   url.UserPassword(c.RabbitMQUsername, c.RabbitMQPassword),
		Host:   fmt.Sprintf("%s:%s", c.RabbitMQHost, c.RabbitMQPort),
	}
	u.Path = "/" + vhost
	u.RawPath = "/" + url.PathEscape(vhost)
	return u.String()
}
```

> Why this works: `URL.EscapedPath()` returns `RawPath` when it is a valid encoding that decodes to
> `Path`. For vhost `/`: `Path="//"`, `RawPath="/%2F"`, and `%2F`→`/` so `RawPath` decodes to `//` ==
> `Path` → `String()` emits `/%2F`. For vhost `prod`: `Path="/prod"`, `RawPath="/prod"` → `/prod`.
> The empty-string guard preserves the old "empty config means default vhost `/`" behavior.

---

## Test — add `go/internal/config/config_test.go` (NEW, no network)

There is no config test file yet. Add a focused unit test for `RabbitMQURI()`:

```go
package config

import "testing"

func TestRabbitMQURIVHostEscaping(t *testing.T) {
	base := Config{
		RabbitMQHost:     "rmq",
		RabbitMQPort:     "5672",
		RabbitMQUsername: "user",
		RabbitMQPassword: "pass",
	}

	cases := []struct {
		name  string
		vhost string
		want  string
	}{
		{"default slash", "/", "amqp://user:pass@rmq:5672/%2F"},
		{"empty defaults to slash", "", "amqp://user:pass@rmq:5672/%2F"},
		{"named vhost", "prod", "amqp://user:pass@rmq:5672/prod"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c := base
			c.RabbitMQVHost = tc.vhost
			got := c.RabbitMQURI()
			if got != tc.want {
				t.Fatalf("RabbitMQURI() = %q, want %q", got, tc.want)
			}
			if got == "amqp://user:pass@rmq:5672/%252F" {
				t.Fatalf("vhost double-escaped: %q", got)
			}
		})
	}
}
```

> If the password contains URL-reserved characters the expected string would differ; the test uses a
> plain password so `url.UserPassword` does not alter it. Keep the cases as written.

---

## Rules / Gates

- `gofmt -l go/` — empty (clean).
- `go vet ./...` (in `go/`) — clean.
- `golangci-lint run` (in `go/`) — clean.
- `go test ./... -race -cover` (in `go/`) — green, including the new `config_test.go`.
- No files changed outside `go/internal/config/config.go` and the new
  `go/internal/config/config_test.go`.
- Self-audit for bare `sudo`, inline creds, hardcoded IPs (the k3d-manager `_agent_audit` script does
  not exist in this repo).

---

## Definition of Done

- [ ] `RabbitMQURI()` sets `u.Path` (decoded) + `u.RawPath` (encoded); no manual pre-escape into `Path`.
- [ ] Default/empty vhost → `amqp://user:pass@host:port/%2F`; named vhost → `/<name>`; never `%252F`.
- [ ] New `go/internal/config/config_test.go` added and green.
- [ ] `gofmt`/`go vet`/`golangci-lint`/`go test -race` all green.
- [ ] Committed and pushed to `origin/feat/go-rewrite`; report the SHA.
- [ ] memory-bank (`activeContext.md` + `progress.md` in k3d-manager) updated with the SHA + status.

**Commit message (exact):**

```
fix(order): RabbitMQURI vhost double-escape — set URL Path + RawPath
```

---

## What NOT to Do

- Do NOT open a PR; do NOT merge; do NOT skip hooks (`--no-verify`); do NOT commit to `main` — commit
  on `feat/go-rewrite`.
- Do NOT modify any file other than `config.go` and the new `config_test.go`.
- Do NOT change the `RABBITMQ_VHOST` default or any other config default.
- Do NOT touch the Java tree, other services, or k3d-manager.
