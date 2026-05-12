# Keycloak browser redirect is mapped to loopback instead of the ingress gateway

Status: Open

## What was observed

Safari showed:

```text
Safari Can't Connect to the Server
Safari can't open the page "keycloak.shopping-cart.local/realms/shopping-cart/protocol/openid-connect/auth?claims=...&client_id=argocd&redirect_uri=https%3A%2F%2Fargocd.shopping-cart.local%2Fauth%2Fcallback&response_type=code&scope=openid+profile+email+groups&state=..."
because Safari can't connect to the server "keycloak.shopping-cart.local".
```

## Root cause

The Mac-host `/etc/hosts` entry for `keycloak.shopping-cart.local` was being treated as a browser-side loopback target. That works only if a local listener is actually bound on the browser host, but the repo does not run a local Keycloak listener there.

Keycloak is exposed through the cluster ingress gateway, so the browser hostname needs to resolve to the ingress gateway address rather than `127.0.0.1`.

## Recommended follow-up

- Keep `argocd.shopping-cart.local` mapped to the local Argo CD TLS listener on `127.0.0.1`.
- Map `keycloak.shopping-cart.local` to the ingress gateway IP so Safari can reach the Keycloak route.
- Add a smoke check in `acg-up` that verifies the host mapping is not stale before announcing SSO is ready.
