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
