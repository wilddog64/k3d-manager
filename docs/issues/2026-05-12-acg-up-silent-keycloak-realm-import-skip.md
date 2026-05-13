# acg-up could finish without importing the Keycloak realm

## What Happened
`make up` could complete even when the Keycloak realm import/reconciliation step did not run. That left the bootstrap looking successful while the live Keycloak state still rejected Argo CD SSO logins.

## Observed Output
```text
[acg-up] ArgoCD browser login URL: https://argocd.shopping-cart.local
[acg-up] Open that URL manually in your browser to continue SSO login.
Invalid username or password.
user_not_found
```

## Root Cause
The realm import path in `bin/acg-up` treated Keycloak not being ready, missing admin token access, or a failed import as warnings and continued the rest of the bootstrap. That made `make up` report success even though the SSO realm was not synchronized.

## Fix
- Make the Keycloak realm import mandatory for SSO bootstrap.
- Fail `make up` if Keycloak is not ready, if the admin token cannot be fetched, or if the realm/client reconciliation fails.

## Follow-Up
- Keep the realm import path fail-fast so the bootstrap cannot report success with stale identity state.
- Re-run `make up` only after Keycloak is ready enough to accept the realm import.
