# Stripe checkout — deferred Copilot hardening findings

**Date:** 2026-08-02
**Source:** Copilot review threads on PRs #52 (order/auth), #53 (order/orchestrator),
#48 (payment/gateway). These are genuine findings **not** addressed in the 2026-08-02
hardening pass (which fixed: empty-subject rejection, payment-id threading + basket
`success:false`, per-request Stripe client + generic error text).

**Decision:** merge A–F first (Stripe path stays gated off until enablement, so none are
live), then address these in a dedicated post-merge hardening pass. Left as **unresolved**
Copilot threads on purpose so they stay visible.

---

## order — PR #52 (`feat/stripe-checkout-auth`)

| # | File:line | Finding | Severity |
|---|-----------|---------|----------|
| 1 | `go/cmd/server/main.go:64` | `OAUTH2_ENABLED=true` with empty `OAUTH2_ISSUER_URI` starts the server but every request fails at JWKS fetch — fail fast at startup. | medium |
| 2 | `go/internal/auth/jwt.go:139` | Validator checks signature + issuer but not audience/authorized-party (`aud`/`azp`); any same-realm token is accepted. | high |
| 3 | `go/internal/config/config.go:34,61` | `OAuth2JWKSetURI` is loaded but never referenced — dead config field. | low |

## order — PR #53 (`feat/stripe-checkout-orchestrator`)

| # | File:line | Finding | Severity |
|---|-----------|---------|----------|
| 4 | `go/cmd/server/main.go:76` | `/api/orders` handlers don't scope reads/lists to the authenticated customer — `ListOrdersByCustomer` trusts a query-string `customerId`, `GetOrder` fetches by id without ownership check. **IDOR.** | high |
| 5 | `docs/plans/stripe-checkout-orchestrator.md:700` | Plan claims no go.mod/go.sum changes, but stacked Phase A adds `github.com/golang-jwt/jwt/v5` — doc is misleading for auditors. | low (doc) |

## payment — PR #48 (`feat/stripe-checkout-gateway`)

| # | File:line | Finding | Severity |
|---|-----------|---------|----------|
| 6 | `go/internal/gateway/mock.go:147` | `request.Amount.Shift(2).IntPart()` silently truncates >2-decimal amounts (API allows 4dp); `0.0099` → `0` cents. Add a 2-decimal precision guard. | medium |
| 7 | `go/internal/gateway/mock.go:177` | `TransactionID` set to `pi.ID`, duplicating `PaymentIntentID` and losing the Charge ID; `latest_charge` is already expanded — use the charge id (fallback to pi.ID). | low |

---

## Next step

Write an exact-old/new-block spec (Codex handoff) covering #1–#7 once A–F are merged and
enablement is scheduled. #2 (aud/azp) and #4 (IDOR) are the priority — real access-control
gaps — and should land before the enablement flip that makes the Stripe/auth path live.

## Status (2026-08-02, A–F merged)

- **#2 (aud/azp) + #4 (IDOR) — SPECCED** in
  `docs/bugs/2026-08-02-stripe-checkout-order-access-control-hardening.md` (order repo, branch
  `fix/order-access-control-hardening`). Both are the pre-enablement gate. aud/azp enforcement is
  configurable via a new `OAUTH2_EXPECTED_AUDIENCE` (default `""` = off, so it lands without
  breaking the current flow) and is switched on with a **verified** value at the enablement flip
  (Keycloak audience-mapper decision documented in that spec). Codex handoff pending.
- **#1, #3, #5, #6, #7 — still open**, lower severity, deferred to a follow-up hardening pass
  (order fail-fast empty-issuer; unused `OAuth2JWKSetURI`; go.mod doc claim; payment amount>2dp
  truncation; payment `TransactionID=pi.ID` dup). Not enablement gates.
