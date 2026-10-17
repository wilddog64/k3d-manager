# e2e-sandbox Tier 2 cannot mint a Keycloak token (doubled realm path, no e2e client on the hub realm)

**Status:** OPEN — 2026-10-17; fix shape needs an operator decision (see Options)
**Priority:** P1
**Severity:** High — every Tier 2 Stripe test fails 401 before reaching payment-service
**Found by:** Claude, live run `1792198836-11122` (2026-10-17T01:03Z), the first a′ run to reach Playwright
**Introduced by:** `945018ee` (v1.36.0 Tier 2 manifest); exposed since shopping-cart-e2e-tests #9/#10
(2026-10-02), when the payment flow started minting a real bearer token

## Symptom

4/4 `flows/stripe-checkout-orchestrator.spec.ts` tests got `401` (expected 400/400/200/402). Test stderr:

```
Error getting auth token: Error: Keycloak token request failed: 404 {"error":"HTTP 404 Not Found"...}
```

Everything before Playwright worked: hub-apps gate (15 Synced/Healthy), Stripe profile label, order and
payment restarts, Job created; cleanup reset the label to `none` and `payment.gateway.default` to `mock`.

## Cause — two defects

1. **Doubled realm path.** `_e2e_sandbox_job_manifest` (`scripts/plugins/e2e.sh`) sets
   `KEYCLOAK_URL=https://keycloak.3ai-talk.org/realms/shopping-cart`, but `tests/helpers/auth.ts`
   builds `${KEYCLOAK_URL}/realms/${KEYCLOAK_REALM}/protocol/openid-connect/token`. The request goes to
   `/realms/shopping-cart/realms/shopping-cart/...` → 404 (probed: realm discovery 200, doubled path 404).
   Tier 1 sets the base URL (`http://keycloak:8080`) and is unaffected.
2. **No e2e identity on the hub realm.** The helper uses a password grant with client `e2e-tests`,
   a client secret, and user `e2e-user`. Those exist only in the Tier 1 throwaway Keycloak
   (`scripts/etc/e2e/keycloak.yaml`). The Tier 2 Job passes no `KEYCLOAK_CLIENT_ID`,
   `KEYCLOAK_CLIENT_SECRET`, username or password, and the hub `shopping-cart` realm has no such
   client. Fixing (1) alone turns the 404 into `invalid_client`.

## Options (operator decision)

- **A — e2e client + user in the hub realm.** Confidential client `e2e-tests` (direct-access grants on,
  no browser flows, scoped roles only) and a non-admin `e2e-user`; client secret and password in Vault,
  synced to the sandbox by ESO into a run-scoped Secret the Job reads. Cost: a password-grant client on
  the public Keycloak — mitigate with a long random secret and no admin roles.
- **B — client-credentials grant.** Service-account client, no user. Needs the e2e helper to support
  `client_credentials` and the services to accept a service-account token. Smaller attack surface; more
  cross-repo work.
- **C — Tier 2 skips auth.** Run with `OAUTH2_ENABLED=false` against the sandbox services. Loses the
  real-token coverage that PR #9 added; not recommended.

Whichever option: set `KEYCLOAK_URL=https://keycloak.3ai-talk.org` and `KEYCLOAK_REALM=shopping-cart`.
