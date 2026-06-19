# Bugfix: backfill Copilot PR findings docs — payment #23 + order #33

**Spec repo:** k3d-manager (this file). **Work repos:** `shopping-cart-payment`, `shopping-cart-order`.
**Branch (both work repos):** `feat/go-rewrite` (existing PR branches — do NOT create new branches).
**Type:** docs-only. No code, config, workflow, or test files may be touched.

---

## Problem

Both Go-rewrite PRs went through a Copilot review, but neither work repo received its
per-PR findings doc + README Issue Logs update that every prior PR in these repos followed:

- **payment PR #23** — Copilot posted 28 findings (review `4524340362`) against the
  pre-hardening commit `736028dd`. All actionable findings were fixed in `f39fba1` (verified
  PASS); 2 were deliberately declined; all 23 open threads were replied to and resolved by
  Claude on 2026-06-18. Repo `docs/issues/` stops at PR #19 — **no `pr23` doc exists**.
- **order PR #33** — Copilot posted findings (review submitted 2026-06-16); GitGuardian also
  flagged a hardcoded `DB_PASSWORD`. Code fixes shipped in `ac85ad5` / `c5a5d95`; deferrals
  posted; all threads resolved. Repo `docs/issues/` stops at PR #25 — **no `pr33` doc exists**.

**Root cause:** the hardening/fix work was handed off as code-only specs; the work-repo issue
log + README update step (normally part of `/create-pr` Phase 2) was never folded in.

This must be closed **before either PR is merged** so the repos' Issue Logs stay complete.

---

## Fix

### Change 1 — payment: create `docs/issues/2026-06-18-copilot-pr23-review-findings.md`

Create this file **verbatim** in the `shopping-cart-payment` repo on `feat/go-rewrite`:

```markdown
# Copilot Review Findings — PR #23 (Go rewrite PR1 hardening)

**PR:** https://github.com/wilddog64/shopping-cart-payment/pull/23
**Review:** Copilot `4524340362` — "⚠️ Not ready to approve" (28 findings), posted against
pre-hardening commit `736028dd`.
**Resolution commit:** `f39fba1` — `fix(payment): harden Go PR1 per Copilot review (gateways, crypto, config, tx)`.
All 23 open threads replied to and resolved 2026-06-18.

## Findings fixed in `f39fba1`

| # | File:line | Finding | Fix |
|---|-----------|---------|-----|
| 1 | config.go:64 | DB password default `changeme123` | default → `""` (explicit `DB_PASSWORD` required) |
| 2 | config.go:70 | RabbitMQ guest/guest defaults | defaults → `""` |
| 3 | config.go:76 | Stripe enabled-by-default + placeholder key/secret | `StripeEnabled` default `false`; key/secret → `""` |
| 4 | config.go:81 | PayPal enabled-by-default + placeholder creds | `PayPalEnabled` default `false`; creds → `""` |
| 5 | encryption.go:37 | random key generated when `ENCRYPTION_KEY` empty | fail fast (error) instead of silent random key |
| 6 | encryption.go:63 | Encrypt gates on `s.enabled` not readiness | gate on `s.IsEnabled()` |
| 7 | encryption.go:86 | Decrypt gates on `s.enabled` not readiness | gate on `s.IsEnabled()` |
| 8 | gateway.go:37 | silent fallback to `mock` for unknown gateway | removed; errors at use time |
| 9 | main.go:49 | MockGateway always constructed enabled | `NewMockGateway(cfg.MockGatewayEnabled, …)` |
| 10 | service.go:77 | multi-write payment flow without a DB transaction | wrapped create→update→audit→update in `RunInTx` |
| 11 | health.go:40 | readiness pings DB with `context.Background()` | use request context |
| 12 | store.go:458 | `scanPaymentRow` silently drops `payment_method_id` parse error | return wrapped error |
| 13 | middleware.go:45 | unbounded per-IP rate-limiter map | bounded map + lastSeen TTL (10m) sweep janitor (1m) |
| 14 | mock.go:136 | StripeGateway returns fake success | fail fast `not_implemented` (deferred to PR2) |
| 15 | mock.go:175 | PayPalGateway returns fake success | fail fast `not_implemented` (deferred to PR2) |
| 16 | handler.go:203 | amount scale not validated vs NUMERIC(19,4) | reject `Amount.Exponent() < -4` → `AMOUNT_SCALE_INVALID` |
| 17 | handler.go:213 | refund amount scale not validated | same scale check |
| 18 | config.go:110 | `sslmode=disable` hardcoded | configurable `DBSSLMode` (`DB_SSLMODE`), url-escaped |
| 19 | service.go:38 | idempotency pre-check race | unique-violation (SQLSTATE 23505) returns existing payment |
| 20–24 | service_test.go:26/85, integration_test.go:60, mock_test.go:18, encryption_test.go:21 | full PAN/CVV literals in tests | replaced with `tok_test_4242` / `test-cvc` |

## Findings deliberately DECLINED (contract preservation)

The Go service replaces a Java backend whose REST contract is the acceptance contract
(shared `shopping-cart-e2e-tests` Playwright suite). Two suggestions were declined because
they would break that contract:

- **handler.go:49 — "require an idempotency key (400 on missing)".** Declined. The Java
  contract treats the idempotency key as optional. Double-charge risk is instead closed at
  the data layer: `orderId` + a unique constraint on `payments.idempotency_key`, with the
  concurrent race handled in `f39fba1` (unique-violation returns the existing payment).
- **handler.go:59 — "return 201 for all states instead of 202".** Declined. The Java
  contract returns 201 for a COMPLETED payment and 202 for a non-terminal result; the e2e
  suite asserts this split. The 201/202 split (handler.go:56-59) is preserved deliberately.

## Process note

The work-repo issue log + README update belongs in the same handoff as the code fix
(`/create-pr` Phase 2), not a follow-up — fold it into every future PR-findings spec.
```

### Change 2 — payment: update README Issue Logs

**File:** `README.md` (shopping-cart-payment).

**Exact old block (lines 110–112):**

```markdown
### Issue Logs
- **[Local Java version mismatch](docs/issues/2026-03-14-local-java-version-mismatch.md)** — CI instructions for Java alignment.
- **[CI Maven wrapper/GitHub Packages fix](docs/issues/2026-03-17-ci-maven-wrapper-fix.md)** — Dockerfile + secret setup for package downloads.
```

**Exact new block (keep 5 most recent, newest first):**

```markdown
### Issue Logs
- **[Copilot PR #23 findings](docs/issues/2026-06-18-copilot-pr23-review-findings.md)** — Go rewrite PR1 hardening: secret defaults, fail-fast crypto/gateways, DB transaction, scale validation, PAN scrub; 2 declined for contract preservation.
- **[Copilot PR #19 findings](docs/issues/2026-05-22-copilot-pr19-review-findings.md)** — earlier Copilot review findings.
- **[Rate limit missing](docs/issues/2026-03-18-rate-limit-missing.md)** — rate limiter gap notes.
- **[Multi-arch workflow pin](docs/issues/2026-03-17-multiarch-workflow-pin.md)** — GitHub Actions cross-arch build pinning notes.
- **[CI Maven wrapper/GitHub Packages fix](docs/issues/2026-03-17-ci-maven-wrapper-fix.md)** — Dockerfile + secret setup for package downloads.
```

> If the exact bracketed descriptions for the PR #19 / rate-limit / multi-arch entries differ
> from the real file titles, use the real doc's H1 as the link text — keep the 5-most-recent
> ordering by date and the PR #23 entry at the top.

### Change 3 — order: create `docs/issues/2026-06-16-copilot-pr33-review-findings.md`

Create this file **verbatim** in the `shopping-cart-order` repo on `feat/go-rewrite`:

```markdown
# Copilot Review Findings — PR #33 (Go rewrite PR1)

**PR:** https://github.com/wilddog64/shopping-cart-order/pull/33
**Review:** Copilot (submitted 2026-06-16) — 5 inline findings; GitGuardian also flagged a
hardcoded `DB_PASSWORD`.
**Resolution commits:** `66f7e0e` (initial) → `c5a5d95` (config/publisher/not-found hardening)
→ `ac85ad5` (CI integration gate + schema). All threads resolved.

## Fixed

| File:line | Finding | Fix |
|-----------|---------|-----|
| config.go:45 | GitGuardian: hardcoded `DB_PASSWORD` default `"postgres"` | default → `""` (explicit env required; `DB_USERNAME` left as-is — not a secret) |
| config.go:73 (a) | `sslmode=disable` hardcoded | env-configurable `DBSSLMode` (`DB_SSLMODE`) |
| publisher.go:312 (b) | hand-rolled `net.DialTimeout` AMQP dialer bypasses library TLS | switch to canonical `amqp.DefaultDial(5 * time.Second)` |
| store.go:160 (c) | `Update` ignores command tag — updating a missing order returns `nil` | return `ErrOrderNotFound` when 0 rows affected |

## Deferred to PR2 (authorization)

PR1 runs `OAUTH2_ENABLED=false`; customer identity from the authenticated JWT principal is
PR2 scope. `handler.go` intentionally unchanged:

- **handler.go:98 (d)** — `customerId` taken from request body.
- **handler.go:193 (e)** — list-by-`customerId` query param.

Both replaced by JWT-principal-derived identity in the PR2 (Keycloak JWT) work.

## Process note

Work-repo issue log + README update belongs in the same handoff as the code fix, not a
follow-up backfill.
```

### Change 4 — order: update README Issue Logs

**File:** `README.md` (shopping-cart-order).

**Exact old block (lines 152–157):**

```markdown
### Issue Logs
- **[Copilot PR #25 findings](docs/issues/2026-04-11-copilot-pr25-review-findings.md)** — Stale status date in activeContext.md, inaccurate CHANGELOG entry for README Issue Logs.
- **[Copilot PR #24 findings](docs/issues/2026-04-11-copilot-pr24-review-findings.md)** — Stale kustomization tag, stale CHANGELOG entry, dangling word fixed.
- **[RabbitMQ connection refused](docs/issues/2026-03-25-rabbitmq-connection-refused.md)** — Fixed in shopping-cart-infra PR #22: `loopback_users.guest = false` + data-layer ArgoCD app + reduced resource requests.
- **[Rate limiting distributed state](docs/issues/2026-03-18-rate-limit-distributed.md)** — Bucket4j in-memory per-pod; Redis integration deferred to v1.1.0.
- **[Multi-arch workflow pin](docs/issues/2026-03-17-multiarch-workflow-pin.md)** — GitHub Actions cross-arch build pinning notes.
```

**Exact new block (PR #33 at top, drop the oldest to keep 5):**

```markdown
### Issue Logs
- **[Copilot PR #33 findings](docs/issues/2026-06-16-copilot-pr33-review-findings.md)** — Go rewrite PR1: GitGuardian DB_PASSWORD default, sslmode env, canonical AMQP dialer, ErrOrderNotFound; d/e deferred to PR2 (JWT).
- **[Copilot PR #25 findings](docs/issues/2026-04-11-copilot-pr25-review-findings.md)** — Stale status date in activeContext.md, inaccurate CHANGELOG entry for README Issue Logs.
- **[Copilot PR #24 findings](docs/issues/2026-04-11-copilot-pr24-review-findings.md)** — Stale kustomization tag, stale CHANGELOG entry, dangling word fixed.
- **[RabbitMQ connection refused](docs/issues/2026-03-25-rabbitmq-connection-refused.md)** — Fixed in shopping-cart-infra PR #22: `loopback_users.guest = false` + data-layer ArgoCD app + reduced resource requests.
- **[Rate limiting distributed state](docs/issues/2026-03-18-rate-limit-distributed.md)** — Bucket4j in-memory per-pod; Redis integration deferred to v1.1.0.
```

---

## Files Changed

| Repo | File | Change |
|------|------|--------|
| shopping-cart-payment | `docs/issues/2026-06-18-copilot-pr23-review-findings.md` | new |
| shopping-cart-payment | `README.md` | Issue Logs — add PR #23 (keep 5 most recent) |
| shopping-cart-order | `docs/issues/2026-06-16-copilot-pr33-review-findings.md` | new |
| shopping-cart-order | `README.md` | Issue Logs — add PR #33 (keep 5 most recent) |

---

## Rules

- Docs-only. Do NOT touch any `.go`, `.yml`, `.yaml`, `pom.xml`, `Dockerfile`, or test file.
- Do NOT alter the resolved Copilot threads or PR metadata (Claude owns those).
- README Issue Logs must keep exactly the 5 most recent entries by date, newest first.
- Run `./scripts/k3d-manager _agent_audit` is N/A here (work repos) — instead confirm `git diff --stat` shows only the 4 files above per repo.

---

## Definition of Done

- [ ] payment `docs/issues/2026-06-18-copilot-pr23-review-findings.md` created
- [ ] payment `README.md` Issue Logs updated (PR #23 top, 5 entries)
- [ ] order `docs/issues/2026-06-16-copilot-pr33-review-findings.md` created
- [ ] order `README.md` Issue Logs updated (PR #33 top, 5 entries)
- [ ] `git diff --stat` in each repo shows only the 2 expected files
- [ ] Committed and pushed to `feat/go-rewrite` in BOTH repos
- [ ] memory-bank updated with both commit SHAs and task status

**Commit message (exact, both repos):**
```
docs(issues): record Copilot PR review findings + README Issue Logs
```

---

## What NOT to Do

- Do NOT create a PR (both PRs already exist).
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than the 2 listed per repo.
- Do NOT commit to `main` — work on `feat/go-rewrite` in each repo.
- Do NOT touch code, CI, or any resolved Copilot thread.
