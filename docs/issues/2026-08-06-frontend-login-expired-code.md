# Frontend login timeout (`expired_code`)

## Investigation

The supplied developer credential was verified against the live `shopping-cart`
realm through the `k3dm-smoke` public client and returned HTTP 200. The live
Keycloak user is enabled and federation-linked.

Keycloak emitted:

```text
type="LOGIN_ERROR" ... clientId="null" userId="null" error="expired_code" restart_after_timeout="true"
```

The frontend OAuth client is configured for standard flow with the expected
callback:

```text
https://frontend.3ai-talk.org/callback
```

The external Keycloak discovery endpoint and frontend endpoint both return HTTP
200.

## Root cause

This is an expired Keycloak browser authorization transaction, not a bad LDAP
password. A stale login tab/session or delayed callback causes Keycloak to
discard the authorization code and show “Your login attempt timed out.”

## Recovery

Open a fresh `https://frontend.3ai-talk.org/` tab (or private window), clear
site data for `frontend.3ai-talk.org` and `keycloak.3ai-talk.org` if the stale
page recurs, and start the login flow again. Do not reuse the old login tab.

