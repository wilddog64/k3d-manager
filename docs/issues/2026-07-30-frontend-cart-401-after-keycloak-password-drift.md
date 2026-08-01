# Frontend cart add returns 401 after Keycloak credential drift

## What was observed

The product details page rendered normally, but its add-to-cart request failed. The
live frontend access log recorded the exact request:

```text
POST /api/cart/items HTTP/1.1" 401
```

The corresponding product request returned HTTP 200. The frontend, basket service,
product catalog, and basket service endpoint were all Ready on `ubuntu-hostinger`.
The basket service requires OAuth2 and is configured with issuer
`https://keycloak.3ai-talk.org/realms/shopping-cart`.

## Root cause

The cart endpoint is protected whereas product browsing is public. The browser request
had no usable authenticated session, so the basket service correctly returned 401. The
request predates the 2026-07-30 repair of the Vault/LDAP password drift; at that time
the advertised credentials could not authenticate with Keycloak.

This is not an inventory, product-catalog, basket-service availability, or frontend
proxy failure.

## Resolution

The LDAP passwords were reset from Vault and all three users now authenticate with
Keycloak. Sign out of `frontend.3ai-talk.org`, sign in again using a freshly retrieved
password from `bin/get-keycloak-password`, then retry Add to Cart. A pre-repair browser
tab cannot be treated as proof of the repaired authentication state.

If a freshly signed-in browser still receives 401, capture the request's HTTP status and
response body from DevTools; that would distinguish a missing bearer token from a JWT
validation failure.
