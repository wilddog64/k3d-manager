# ArgoCD SSO `groups` scope fix already present on `origin/main`

## What I attempted

- Followed `docs/bugs/2026-05-18-argocd-sso-invalid-groups-scope.md`
- Created/checked out `fix/argocd-groups-scope` in `shopping-cart-infra`
- Verified `argocd/config/argocd-cm.yaml`

## Actual output

```text
$ git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra show HEAD:argocd/config/argocd-cm.yaml | sed -n '18,35p'
    issuer: http://keycloak.shopping-cart.local/realms/shopping-cart
    clientID: argocd
    clientSecret: $oidc.keycloak.clientSecret
    requestedScopes:
      - openid
      - profile
      - email
    # Map Keycloak groups to ArgoCD
    requestedIDTokenClaims:
      groups:
        essential: true

  # Dex is disabled when using OIDC directly
  dex.config: ""

  # Admin user settings
  admin.enabled: "true"
```

```text
$ git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra diff HEAD -- argocd/config/argocd-cm.yaml
```

```text
$ git -C /Users/cliang/src/gitrepo/personal/shopping-carts/shopping-cart-infra status --short --branch
## fix/argocd-groups-scope...origin/main
```

## Root cause

The requested fix is already present in the current `origin/main` snapshot of `shopping-cart-infra`. The `requestedScopes` list already contains only `openid`, `profile`, and `email`, so there was nothing to change or commit.

## Recommended follow-up

- Refresh the bug spec or close it as already resolved if the branch tip is the intended source of truth.
- If a change was expected on a different commit range, confirm the target revision before assigning the task again.
