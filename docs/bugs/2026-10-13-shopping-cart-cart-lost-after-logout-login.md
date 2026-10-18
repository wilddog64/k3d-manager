# Bug: Suspected regression: shopping-cart items disappear after logout and login

**Filed:** 2026-10-13
**Status:** LIVE-VERIFIED — NOT REPRODUCED, operator live browser test 2026-10-15: operator added 3 items, logged out and back in; cart intact (see "Verification 2026-10-15")
**Branch:** `k3d-manager-v1.43.3` (triage 2026-10-15, operator-approved placement)
**Priority:** P2
**Date:** 2026-10-13
**Detected by:** human
**Affected:** shopping-cart frontend + basket-service; authenticated session persistence
**Branch observed:** `k3d-manager-v1.43.2` (live application revision unverified)

## Reported symptom

Items added to the shopping cart may not remain after the same user signs out and signs back in. This is a **suspected regression**, not yet confirmed by a controlled repro. The current separate Keycloak `Invalid redirect uri` failure blocks normal login and may prevent verifying this behavior.

## Expected behavior / contract to confirm

If the product intends an **account-persistent** basket, items added while authenticated should still be available when the *same account* logs out and logs back in. They should not leak to a different account. Confirm whether the implemented contract is account-persistent or intentionally session-only before classifying behavior as a defect.

## Relevant prior art

- `docs/plans/checkout-and-blue-green-design.md` explicitly documents lost carts across visits and calls out two independent issues: frontend affinity and durable basket state in basket-service/Redis keyed by a stable session/customer identifier. It states the durable data path, not sticky sessions, is the load-bearing solution.
- `docs/issues/2026-07-30-frontend-cart-401-after-keycloak-password-drift.md` documents Add to Cart returning HTTP 401 when frontend authentication was invalid; verify POST success before claiming data vanished.
- `docs/bugs/2026-10-13-shopping-cart-frontend-keycloak-invalid-redirect-uri.md` records current OIDC authorization failure. Verify authentication first.

## Reproduction and diagnosis (do not alter live data)

1. After frontend OIDC login works, sign in as test user A in a fresh browser profile. Add one unique product/quantity to cart; confirm `POST /api/cart/items` succeeds (not 401) and a subsequent basket GET returns the item.
2. Record the public API route, response code, and non-sensitive account/session identifier. Confirm the item is persisted in the basket-service storage (Redis) with expected TTL; don't log tokens/cookies/passwords.
3. Log out and log in as **the same user A**. Refresh and retrieve the basket. Check whether client clears local state but fails to refetch, a session cookie/customer ID changes, the authenticated subject maps to a different basket key, or Redis TTL/eviction/pod restart removed the item.
4. Repeat as user B to ensure baskets remain isolated; evaluate browser refresh, new tab, restart, and redeploy independently.
5. Determine whether expected behavior is authenticated account persistence or guest-session persistence, then document the real contract.

## Likely causes — not established

- Basket keyed only by ephemeral frontend session ID rather than stable authenticated user/customer identifier.
- Frontend clears cart on logout and fails to reload the persisted basket on new login.
- Basket persistence/TTL or Redis data loss, or write requests silently rejected with 401.
- Mixed in-memory frontend state across replicas; affinity alone cannot guarantee long-term persistence.

## Fix and acceptance criteria

- [ ] Authentication repaired, and behavior reproduced with HTTP request/response evidence.
- [ ] Expected persistence contract confirmed from application specification/product requirements.
- [ ] Cause isolated to frontend identity mapping, basket API, Redis persistence, or unintended session semantics.
- [ ] Same-account logout/login and browser refresh preserve the cart when required.
- [ ] Another account cannot access the first user's basket.
- [ ] E2E regression includes add → confirm persisted → logout → login → verify, plus cross-user isolation and unauthorized request checks.
- [ ] Tests and live evidence verified; close as non-bug if intended session-only behavior is confirmed.

**Do not** fix by introducing global/shared cart identifiers, weakening OAuth2 checks, or logging sensitive session credentials.

## Verification 2026-10-15 (operator, live browser)

Run after the Keycloak post-logout redirect fix (shopping-cart-infra #112, `556a4ea`) made logout
actually end the session. The operator added three items (PrimeWave Desk Mat Pro 3.0 $37, SwiftEdge
USB Hub Ultra 3.0 $53, SwiftEdge 24-inch Monitor Max 3.0 $259), logged out, logged back in: all three
items were still in the cart, subtotal $349.00. Not reproduced.

The likely origin of the 2026-10-13 observation: logout was rejected ("Invalid redirect uri"), so the
operator cleared cookies as the workaround, which loses client-side session state. With logout working,
basket persistence across a real logout/login holds. Reopen with a fresh repro if it recurs.
