# Bugfix: payment Go rewrite — round-5 Copilot finding (PCI: zero card fields on `req`)

**Work repo:** `shopping-cart-payment` — branch `feat/go-rewrite` (continue the existing branch; do
NOT branch anew, do NOT open a PR — #23 is already open against this branch).
**Spec lives in:** `k3d-manager` (`k3d-manager-v1.7.1`) — this file only.
**Type:** Single-finding follow-up to `docs/bugs/2026-06-19-bugfix-copilot-pr23-round4.md` (R4). Closes
the one unresolved Copilot thread on payment #23 (HEAD `307ddf3`).

---

## Problem

R4 zeroed the **gateway** copy of the card data (`request.CardNumber/CardCVC/CardExpMonth/CardExpYear`)
immediately after the gateway call. But the **inbound** service request `req` (`ProcessPaymentRequest`,
passed by value into `ProcessPayment`) still holds the raw PAN/CVV/expiry in
`req.CardNumber` / `req.CardCvc` / `req.CardExpMonth` / `req.CardExpYear`, and those locals stay alive
through the `persist` / `RunInTx` DB-and-audit write path. This violates the repo's PCI rule: do not
retain CVV/PAN in variables past the gateway invocation.

**Root cause:** the zeroing in R4 cleared `request` but not `req`. `req` is a by-value parameter, so
zeroing its sensitive fields is safe (the caller's copy is untouched) and simply minimizes how long the
PAN/CVV live in this function's locals.

**Copilot thread:** `go/internal/payment/service.go:101` (`PRRT_kwDORUaaec6K2FGG`, comment `3442769663`).

---

## Before You Start

1. `git pull origin k3d-manager-v1.7.1` in k3d-manager and read this spec in full.
2. In `shopping-cart-payment`: `git fetch origin && git checkout feat/go-rewrite && git pull origin
   feat/go-rewrite` (extend HEAD `307ddf3`).
3. Read `go/internal/payment/service.go` (the `ProcessPayment` method) and confirm the field names on
   `ProcessPaymentRequest` in `go/internal/payment/dto.go`: the CVC field is spelled **`CardCvc`** (not
   `CardCVC` — that spelling is only on the gateway `PaymentRequest`).

---

## Fix — `go/internal/payment/service.go`: also zero the sensitive fields on `req`

Add four `req.*` zeroing lines alongside the existing four `request.*` zeroing lines, immediately after
the gateway call. Do not touch billing fields or `CardholderName` — only PAN, CVV, and expiry.

**Exact old block:**

```go
	result := gatewayImpl.ProcessPayment(request)
	request.CardNumber = ""
	request.CardCVC = ""
	request.CardExpMonth = ""
	request.CardExpYear = ""
	persist := func(store paymentStore) error {
```

**Exact new block:**

```go
	result := gatewayImpl.ProcessPayment(request)
	request.CardNumber = ""
	request.CardCVC = ""
	request.CardExpMonth = ""
	request.CardExpYear = ""
	req.CardNumber = ""
	req.CardCvc = ""
	req.CardExpMonth = ""
	req.CardExpYear = ""
	persist := func(store paymentStore) error {
```

> Why this is safe: `req` is a by-value parameter; nothing after the gateway call reads `req` (the
> `persist` closure uses `payment` / `correlationID` / `result` / `now`, not `req`). Zeroing only the
> local copy minimizes PAN/CVV retention without affecting the caller.

---

## Rules / Gates

- `gofmt -l go/` — empty (clean).
- `go vet ./...` (in `go/`) — clean.
- `golangci-lint run` (in `go/`) — clean (the four new assignments are consumed by being cleared; this
  is intentional zeroing, not a dead store flagged by staticcheck/ineffassign — confirm lint stays
  green, do not add `//nolint`).
- `go test ./... -race -cover` (in `go/`) — green (existing suite must still pass; no new test required
  — this is a defensive-zeroing change with no observable behavior change).
- `docker build -f go/Dockerfile go` — succeeds.
- No files changed outside `go/internal/payment/service.go`.
- Self-audit for bare `sudo`, inline creds, hardcoded IPs (the k3d-manager `_agent_audit` script does
  not exist in this repo).

---

## Definition of Done

- [ ] `req.CardNumber`, `req.CardCvc`, `req.CardExpMonth`, `req.CardExpYear` zeroed immediately after
      `gatewayImpl.ProcessPayment(request)`, alongside the existing `request.*` zeroing.
- [ ] Only `go/internal/payment/service.go` changed.
- [ ] `gofmt`/`go vet`/`golangci-lint`/`go test -race`/`docker build` all green.
- [ ] Committed and pushed to `origin/feat/go-rewrite`; report the SHA.
- [ ] memory-bank (`activeContext.md` + `progress.md` in k3d-manager) updated with the SHA + status.

**Commit message (exact):**

```
fix(payment): zero raw card fields on request param after gateway call (PCI)
```

---

## What NOT to Do

- Do NOT open a PR; do NOT merge; do NOT skip hooks (`--no-verify`); do NOT commit to `main` — commit
  on `feat/go-rewrite`.
- Do NOT modify any file other than `service.go`.
- Do NOT zero billing fields or `CardholderName` — only PAN, CVV, and expiry.
- Do NOT change the spelling of the gateway field (`request.CardCVC`) or the service field (`req.CardCvc`).
- Do NOT touch the Java tree, other services, the e2e suite, or k3d-manager.
