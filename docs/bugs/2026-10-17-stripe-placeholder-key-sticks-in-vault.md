# A placeholder Stripe key in Vault is reused forever, so Tier 2's success checkout gets 402

**Status:** IN PROGRESS — payment fix dispatched to Codex 2026-10-17 (operator: "let's get that spec to codex then I will merge PR if you created and that passed CI and copilot review"). Previously DEFERRED — both causes confirmed; the fix is proven by a direct Stripe call (`pi_3URNAGGSVhtK1dwe1heJ9ZK2` succeeded). Not dispatched: shopping-cart retires at v2.0.0, and e2e moves to TwinkleAI at v1.50.0 (operator, 2026-10-17). Reopen only if Tier 2 gates a release before then.
**Priority:** P3 (was P1; lowered because shopping-cart is being retired)
**Severity:** High — Tier 2 `make e2e-sandbox` cannot pass; every real Stripe charge fails
**Found by:** Claude, live runs `1792200904-21736` and the 01:44Z rerun (2026-10-17), branch `k3d-manager-v1.43.4`
**Related:** `docs/bugs/2026-09-20-seed-clobbers-real-payment-secrets.md` (fixed the clobber, not this),
`docs/bugs/2026-10-17-e2e-sandbox-tier2-keycloak-token-404.md` (the blocker in front of this one)

## Symptom

With the Keycloak identity fixed, Tier 2 got to 3/4. The remaining failure:

```
✘ stripe-checkout-orchestrator.spec.ts:51 › completes checkout, marks order PAID … Expected: 200 Received: 402
```

The test failed the same way on both retries. The declined-card test passes only because it expects 402 anyway.
payment-service logged `StripeGateway: Payment failed`, thrown from `PaymentIntent.create` →
`LiveStripeResponseGetter.exceptionFromStatus`, for every charge. Claude's redacting log capture dropped
the exception message line, because it contained a key-shaped token.

## Cause

`secret/payment-gateway-secrets` in `shopping-cart-payment` (ESO, from Vault `secret/payment/stripe`)
has `stripe-api-key: 19 bytes` and `stripe-webhook-secret: 17 bytes`, read with `kubectl describe`
(sizes only). Those lengths match the seeder's placeholders exactly:

- `sk_test_placeholder` = 19 bytes;
- `whsec_placeholder` = 17 bytes.

`shopping_cart_seed_sandbox_vault_kv` (`scripts/plugins/shopping_cart.sh:816`):

```bash
  if _vault_kv_exists "payment/stripe"; then
    _info "[acg-up] Reusing existing Vault secret payment/stripe"
  else
    … seed source → Keychain k3dm-stripe-sk-test → placeholder
```

Once any run has written the placeholder, every later run sees the path exists and keeps it. That
happens on a run with no seed source and no unlocked Keychain, or on a run before `f28a4539`. The
2026-09-20 fix stopped a real key being overwritten, but nothing ever upgrades a placeholder. The
Keychain does hold the real key: the same e2e run built `secret/stripe-e2e` from
`k3dm-stripe-sk-test` with no warning.

The Playwright pod gets the real key (`STRIPE_SECRET_KEY` from `stripe-e2e`). payment-service gets
the placeholder, so Stripe rejects the call and order-service maps it to 402.

## Fix (to spec)

1. **Treat a placeholder as absent.** In the reuse branch, read `api_key` without printing it and
   compare it to `sk_test_placeholder`. If it matches, fall through to the seed source → Keychain
   path and overwrite only `api_key`, keeping the existing `webhook_secret`. Log only
   `payment/stripe api_key was a placeholder — restored from <source>`.
2. **Preflight in `make e2e-sandbox` (Tier 2).** Before enabling the Stripe profile, fail fast if the
   payment key is the placeholder, with a message that names the repair. Compare in-process and
   never print the value.
3. **Harness log capture.** The e2e exit trap restarts order and payment, which erases the evidence.
   Save their last 10 minutes of logs, redacted, into the run directory before the restart.

## Operator repair (now, without waiting for the fix)

Write the Keychain key into the hub Vault through stdin, so it is never echoed, then let ESO refresh.
Then rerun `make e2e-sandbox`, which restarts payment on its own.

## Live proof

`make e2e-sandbox` Tier 2 reports 4/4, and `payment-gateway-secrets` `stripe-api-key` is no longer
19 bytes.

## Repair applied, and a second cause (2026-10-17 01:51Z)

- **Repair.** The operator's Mac has no `vault` CLI, so the first `vault kv patch` silently did
  nothing. The repair that worked used `curl` to POST to `localhost:18200/v1/secret/data/payment/stripe`:
  the token went in a temporary header file, the key came from the Keychain through stdin into `jq`,
  then the ExternalSecret was force-synced. `stripe-api-key` became 107 bytes. Future repair steps
  must use `curl`, not `vault`.
- **Still failing.** Run `1792201944-27199` still got 402 on the success checkout. The placeholder
  was a real cause, but it is not the only one.
- **Never passed.** Tier 2 Stripe has not passed in any recorded run since 2026-09-25, so the success
  path has never been proven live.
- **Prime suspect.** `StripeGateway.processPayment` (shopping-cart-payment) creates the PaymentIntent
  with `payment_method=pm_card_visa` and `confirm=true`, but sets neither `return_url` nor
  `automatic_payment_methods[allow_redirects]=never`. Recent Stripe API versions reject that
  combination, because automatic payment methods are on by default. This is unconfirmed: the cleanup
  restart erased the exception message again. To confirm, read the failed `POST /v1/payment_intents`
  in the Stripe dashboard (Developers → Logs, test mode, about 01:53Z), or capture the logs during
  a rerun.

## Second cause confirmed: Stripe rejects server-side confirm without `return_url` (2026-10-17 02:13Z)

- **The key is not the problem.** The Keychain key, and so Vault and the cluster, belongs to
  `acct_1Tzo4gGSVhtK1dwe`, the same account as the frontend's `VITE_STRIPE_PUBLISHABLE_KEY`.
  `GET /v1/account` with that key succeeds. The operator's only dashboard login is a different account,
  `acct_1Tzo4YKH1dHRwQRM`, which is why no request ever showed up in Developers → Logs.
- **Repro.** The operator replayed the payment service's exact call against `acct_1Tzo4gGSVhtK1dwe`
  (`amount=1000 currency=usd payment_method=pm_card_visa confirm=true`). The key went through stdin
  (`curl -K -`). Stripe answered `invalid_request_error`: "This PaymentIntent is configured to accept
  payment methods enabled in your Dashboard … you must provide a `return_url`. If you don't want to
  accept redirect-based payment methods, set `automatic_payment_methods[enabled]` to `true` and
  `automatic_payment_methods[allow_redirects]` to `never`."
- **Why it reads as a decline.** `StripeGateway.processPayment` turns every `StripeException` into a
  failure result, and order-service maps that to 402. So an invalid request looks like a declined card.

### Fix — shopping-cart-payment (separate repo; spec for Codex)

**Repo:** `wilddog64/shopping-cart-payment`. **Branch:** `fix/stripe-intent-no-redirects`, cut from
`origin/main` (`193ee6f`). Do NOT work on the local `fix/tomcat-jackson3-cve-overrides`.

**F1. `src/main/java/com/shoppingcart/payment/gateway/stripe/StripeGateway.java`.** Move the
parameter build into a package-private method so it can be tested, and disable redirect-based
methods whenever the server confirms.

Old (inside `processPayment`):
```java
            PaymentIntentCreateParams.Builder paramsBuilder = PaymentIntentCreateParams.builder()
                    .setAmount(amountInCents)
                    .setCurrency(request.getCurrency().toLowerCase())
                    .setDescription("Order: " + request.getOrderId())
                    .putMetadata("order_id", request.getOrderId())
                    .putMetadata("customer_id", request.getCustomerId());

            if (request.getPaymentMethodToken() != null) {
                paramsBuilder.setPaymentMethod(request.getPaymentMethodToken());
                paramsBuilder.setConfirm(true);
            }
```
New:
```java
            PaymentIntentCreateParams.Builder paramsBuilder = buildPaymentIntentParams(request, amountInCents);
```
and add, as a new method of the class:
```java
    PaymentIntentCreateParams.Builder buildPaymentIntentParams(PaymentRequest request, long amountInCents) {
        PaymentIntentCreateParams.Builder paramsBuilder = PaymentIntentCreateParams.builder()
                .setAmount(amountInCents)
                .setCurrency(request.getCurrency().toLowerCase())
                .setDescription("Order: " + request.getOrderId())
                .putMetadata("order_id", request.getOrderId())
                .putMetadata("customer_id", request.getCustomerId());

        if (request.getPaymentMethodToken() != null) {
            paramsBuilder.setPaymentMethod(request.getPaymentMethodToken());
            paramsBuilder.setConfirm(true);
            paramsBuilder.setAutomaticPaymentMethods(
                    PaymentIntentCreateParams.AutomaticPaymentMethods.builder()
                            .setEnabled(true)
                            .setAllowRedirects(PaymentIntentCreateParams.AutomaticPaymentMethods.AllowRedirects.NEVER)
                            .build());
        }
        return paramsBuilder;
    }
```

**F2. New test `src/test/java/com/shoppingcart/payment/gateway/stripe/StripeGatewayParamsTest.java`.**
1. With a payment-method token, `build().getAutomaticPaymentMethods()` is non-null, `getEnabled()` is
   `true` and `getAllowRedirects()` is `NEVER`. `getConfirm()` is `true`, and the payment method is
   the token.
2. Without a token, `getAutomaticPaymentMethods()` is null and `getConfirm()` is null, so the
   existing behaviour is unchanged.
3. Mutation check: drop the `setAutomaticPaymentMethods` call and test 1 must fail. Report that.

No network and no live Stripe key in tests (stripe-java 34.0.0, already pinned).

**Definition of Done**
- [ ] `./mvnw -q test` green; paste the summary.
- [ ] Commit: `fix(stripe): disable redirect payment methods on server-side confirm` and push to
      `origin/fix/stripe-intent-no-redirects`; report the SHA.
- [ ] Do NOT create a PR, do NOT touch `main`, do NOT skip hooks, and do NOT modify files outside F1–F2.

**Live proof:** after the image rolls, Tier 2 `make e2e-sandbox` reports 4/4. That also marks this
bug's success path proven live for the first time.

### Follow-up (not blocking)

The operator can only log into `acct_1Tzo4YKH1dHRwQRM`, so nobody can read the Stripe logs for the
account the platform actually uses. Moving to it means updating the Keychain `k3dm-stripe-sk-test`,
Vault `payment/stripe`, `VITE_STRIPE_PUBLISHABLE_KEY` and a frontend rebuild. That is operator
credential work, to be scheduled separately.

## Fix proven against Stripe (2026-10-17 02:20Z)

The same replay with `automatic_payment_methods[enabled]=true` and `[allow_redirects]=never` returned
`status: succeeded` (`pi_3URNAGGSVhtK1dwe1heJ9ZK2`). The F1/F2 spec above is correct as written; it is
parked, not dispatched.
