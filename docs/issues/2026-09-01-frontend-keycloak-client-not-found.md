# Frontend login fails because the Keycloak `frontend` client is missing

**Date:** 2026-09-01  
**Affects:** Hostinger frontend login (`frontend.3ai-talk.org`)

## Evidence

- The deployed frontend bundle embeds:
  - authority: `https://keycloak.3ai-talk.org/realms/shopping-cart`
  - client ID: `frontend`
- Keycloak's `shopping-cart` realm discovery endpoint responds successfully.
- The Keycloak admin API query for `clientId=frontend` returned an empty list:

```text
[]
```

- The browser displays Keycloak's `Client not found` error page.

## Root cause

The frontend is built correctly for the public authority and `frontend` client ID, but the
`frontend` public client is absent from the `shopping-cart` realm. The existing smoke
provisioning path creates `k3dm-smoke`, not the application client, so it does not satisfy the
frontend login flow.

## Recommended fix

Reconcile/create the `frontend` OpenID Connect public client in the `shopping-cart` realm with
the production callback and logout origins for `https://frontend.3ai-talk.org`, then verify a
browser authorization-code login. Make the client definition declarative/idempotent so a
Keycloak restart or realm reconcile cannot remove it.

## Scope note

No frontend image or credentials were changed during this investigation.
