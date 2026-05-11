# Bug: `acg-up` does not reconcile the existing Keycloak `argocd` client redirect URIs

## Status
Open

## Symptom
After rebuilding the cluster, Argo CD SSO still fails with a Keycloak redirect error such as:

```text
Invalid redirect URL: the protocol and host (including port) must match and the path must be within allowed URLs if provided
```

## Root Cause
`bin/acg-up` only imports `realm-shopping-cart.json` when Keycloak returns `201` for the realm create request. When Keycloak returns `409` because the realm already exists, the script skips the import path entirely.

That means the live `argocd` client inside the existing realm is never reconciled to the redirect URI set in the repo JSON:

- `https://argocd.shopping-cart.local/*`
- `http://localhost:8080/*`

If the live realm was created before those URIs were added, or if the realm persisted across a rebuild, Keycloak keeps the stale client config and rejects the browser callback.

## What Was Observed
The current bootstrap flow logs:

```text
[acg-up] Keycloak realm 'shopping-cart' already exists — skipping import
```

That behavior prevents a rebuild from refreshing the `argocd` client config.

## Recommended Fix
After obtaining the Keycloak admin token, reconcile the existing `argocd` client in the `shopping-cart` realm on every run:

1. Look up the client by `clientId`.
2. Update its stored redirect URIs and related OIDC fields from the realm JSON.
3. Treat `201` and `409` the same from the perspective of client reconciliation.

## Follow-up
Keep the bootstrap idempotent so cluster rebuilds do not require manual Keycloak cleanup before Argo CD SSO works again.
