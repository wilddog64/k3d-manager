# Stripe checkout acceptance blocked by live E2E identity configuration

## Evidence

- Frontend CI promotion succeeded (`31066454922`) and Hostinger runs
  `sha-b0dc4e89b66379f82866ec197f13481bd5763aa8`.
- Hostinger payment configuration reports `stripe.enabled=true`; the
  `payment-gateway-secrets` Secret contains `stripe-api-key`.
- Keycloak password grant with the documented `e2e-tests` client returns
  `invalid_client` because that client is absent from the live realm.
- Password grant with the live `order-service` client and the available
  developer credential returns `invalid_grant` (`Invalid user credentials`).

## Required follow-up

Provision a non-production E2E Keycloak client with direct access grants and a
dedicated test user, or provide the current valid test credentials. Then run
the gated Stripe Playwright happy-path and declined-payment tests.

## 2026-08-07 live verification

- Provisioned the `e2e-tests` direct-grant client and a dedicated `e2e-user` in
  the live Keycloak realm. The token endpoint authenticates successfully with
  an explicitly URL-encoded password grant.
- Fixed the E2E helper's Playwright form encoding on
  `shopping-cart-e2e-tests` commit `e237593`; the previous request was treated
  as empty by Keycloak (`Missing form parameter: grant_type`).
- The scoped live run reached the order orchestrator: the two contract/auth
  tests passed, while both Stripe cases returned HTTP 400 because the live
  `order_items` table requires `total_price` and the deployed Go insert wrote
  only `unit_price`.
- Pushed the persistence fix on `shopping-cart-order` branch
  `fix/live-checkout-e2e-schema` at commit `0e3feb9`. Its CI checks passed; it
  still needs the normal merge/promotion path before live acceptance can be
  rerun.

Acceptance result before promotion: **2 passed, 2 failed**. No credentials are
recorded here.
