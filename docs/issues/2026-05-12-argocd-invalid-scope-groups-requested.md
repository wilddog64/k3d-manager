# Argo CD OIDC login requested the unsupported `groups` scope

## What was tested
- Ran `make up` after the Keycloak browser wiring fixes.
- The browser reached Keycloak, but OIDC login failed before authentication completed.

## Actual output
```text
error: invalid_scope: Invalid scopes: openid profile email groups
```

## Root cause
- The Argo CD OIDC config in `shopping-cart-infra/argocd/config/argocd-cm.yaml` requested `groups` in `requestedScopes`.
- Keycloak did not have a matching allowed scope for that request, so the auth flow failed at scope validation.
- Argo CD already receives the groups claim from the client mapper, so the explicit `groups` scope request is unnecessary.

## Follow-up
- Remove `groups` from Argo CD's `requestedScopes`.
- Keep the groups claim mapper in place so RBAC can still read group membership from the token.
