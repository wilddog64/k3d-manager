# Tier 2 Stripe flow reads the payments-by-order object as an empty list

**Status:** LIVE-VERIFIED — 2026-10-17: shopping-cart-e2e-tests PR #12 merged `7ef0a5f8`; Tier 2 run `1792240129-27700` 4/4 PASS
**Live evidence:** 2026-10-17 · run 1792240129-27700 · env sandbox/local-m4 · scenario stripe/product-catalog · commit a8b2dddd · proves fix
**Priority:** P2
**Severity:** Medium — Tier 2 can never reach 4/4. The flow it checks works; only its last assertion is wrong
**Found by:** Claude, live run `1792236389-10503` (2026-10-17), branch `k3d-manager-v1.43.4`
**Approval:** explicit 2026-10-17 "go for those" (operator), on Claude's proposed one-line fix
**Related:** `docs/bugs/2026-10-17-stripe-placeholder-key-sticks-in-vault.md` (the 402 this run
proved fixed; this assertion was unreachable until then)

## Symptom

```
flows/stripe-checkout-orchestrator.spec.ts — completes checkout, marks order PAID, clears cart, records a stripe payment
Error: expect(received).toBeGreaterThan(expected) / Expected: > 0 / Received:   0
```

Every assertion before it passed: checkout returned 200 with `paymentStatus: PAID`, the order read
back as `PAID`, and the cart was empty.

## Cause

The test reads `GET /api/v1/payments/order/{orderId}` and expects a list:

```ts
const payments = Array.isArray(payBody) ? payBody : (payBody.data ?? [])
```

The payment service returns **one** `PaymentResponse` object, or 404 when there is none
(`shopping-cart-payment` `PaymentController.java:97`, `getPaymentByOrder` →
`ResponseEntity<PaymentResponse>`). An object is not an array and has no `data` field, so the test
gets `[]`. The preceding `expect(payRes.ok())` passed, which means the payment exists: a missing one
would be a 404.

The service sets `gateway` to `"stripe"` (`StripeGateway.NAME`) and `status` to `COMPLETED`
(`PaymentStatus`), so the two assertions after the count will pass once the object is read.

## Fix — shopping-cart-e2e-tests (separate repo; spec for Codex)

**Branch:** `fix/payments-by-order-object`, from `origin/main` (`e5e644d`).

**F1.** In `tests/flows/stripe-checkout-orchestrator.spec.ts`, wrap a single object instead of
discarding it.

Old:
```ts
    const payments = Array.isArray(payBody) ? payBody : (payBody.data ?? [])
```

New:
```ts
    const payments = Array.isArray(payBody) ? payBody : (payBody.data ?? [payBody])
```

**F2.** In `CHANGELOG.md`, under `## [Unreleased]` (create the heading above the newest version if
it is missing), add under `### Fixed`:

```markdown
- **Stripe checkout flow reads the payments-by-order response correctly.**
  `GET /api/v1/payments/order/{orderId}` returns a single payment object, not a list. The flow
  treated the object as an empty list, so it failed "records a stripe payment" after a checkout that
  had succeeded. It now wraps a single object, and still accepts an array or a `{data: [...]}` body.
```

## Files

- `tests/flows/stripe-checkout-orchestrator.spec.ts`
- `CHANGELOG.md`

## Rules

All offline. Nothing may call a live service or Stripe:

- `npx tsc --noEmit -p .` is clean.
- `npm run lint` is clean.
- `npx playwright test --list --project=flows` still lists
  "completes checkout, marks order PAID, clears cart, records a stripe payment".

Paste the output of all three.

## Definition of Done

- [ ] F1 and F2 applied exactly; the three gates above pass (paste the output).
- [ ] Commit message: `fix(flows): read the payments-by-order response as a single payment`.
- [ ] Push `fix/payments-by-order-object` and confirm `git rev-parse origin/fix/payments-by-order-object`
      equals the local HEAD. Report the SHA.

## What NOT to Do

- Do NOT create a PR. Claude opens it; the operator merges.
- Do NOT commit to `main` or skip hooks (`--no-verify`).
- Do NOT modify files outside `## Files`, including this doc and `memory-bank/` in either repo.
- Do NOT run the Playwright suite against any environment, or change `api-client.ts` (its
  `getPaymentByOrder` helper is not used by this flow).

## Live proof

After the merge, `publish-image.yml` pushes `shopping-cart-e2e-tests:latest`. The Tier 2 harness
pulls `latest` with `Always` (`scripts/plugins/e2e.sh:5`), so the next `make e2e-sandbox` picks it up
with no pin change. Expect 4/4.

## Live proof (2026-10-17)

Run `1792240129-27700` (k3d-manager `a8b2dddd`, e2e image from `7ef0a5f8`): **4/4 passed**, `exit_code=0`,
no failures. The gate passed on its first poll (15 Synced and Healthy), and `make e2e-sandbox` exited about 1s
after its last log line.
