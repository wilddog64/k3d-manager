# acg-up browser auto-open removed for noninteractive flows

## What Happened
`make up` was auto-opening Safari after SSO wiring completed. That made the bootstrap feel incomplete on macOS and would fail outright on Linux because there is no browser handoff path there.

## Observed Output
```text
[acg-up] ArgoCD SSO wired: login at https://argocd.shopping-cart.local → Keycloak realm shopping-cart
[acg-up] Opening canonical ArgoCD browser URL: https://argocd.shopping-cart.local
Safari Can't Open the Page
```

## Root Cause
The browser-open step is not required for bootstrap completion and couples `make up` to a local GUI browser. That adds a platform-specific side effect after the infrastructure has already been brought up.

## Follow-Up
- Keep `make up` focused on bringing the stack up and let the user open the browser manually when needed.
- Avoid reintroducing browser automation into the bootstrap path unless it is explicitly requested and platform-gated.
