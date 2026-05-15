# Argo CD rejects localhost return_url during SSO login

Status: OPEN

## What was observed

Safari showed:

```text
Safari can't open the page "localhost:8080/auth/login?return_url=http%3A%2F%2Flocalhost%3A8080%2Fapplications"
because Safari can't connect to the server "localhost".
```

I verified the live Argo CD login endpoint directly:

```text
$ curl -sk 'http://localhost:8080/auth/login?return_url=http%3A%2F%2Flocalhost%3A8080%2Fapplications'
Invalid redirect URL: the protocol and host (including port) must match and the path must be within allowed URLs if provided
```

The same endpoint accepts the canonical browser URL:

```text
$ curl -sk 'http://localhost:8080/auth/login?return_url=https%3A%2F%2Fargocd.shopping-cart.local%2Fapplications'
<a href="http://keycloak.shopping-cart.local/realms/shopping-cart/protocol/openid-connect/auth?claims=...&client_id=argocd&redirect_uri=https%3A%2F%2Fargocd.shopping-cart.local%2Fauth%2Fcallback&response_type=code&scope=openid+profile+email+groups&state=...">See Other</a>
```

The live Argo CD config currently sets:

```text
url: https://argocd.shopping-cart.local
oidc.config.issuer: http://keycloak.shopping-cart.local/realms/shopping-cart
```

The live Keycloak client already allows both expected redirect URIs:

```text
http://localhost:8080/*
https://argocd.shopping-cart.local/*
```

## Root cause

The Argo CD `url` setting is canonicalized to `https://argocd.shopping-cart.local`, and `/auth/login` rejects `return_url=http://localhost:8080/...` before Keycloak is involved. The live Keycloak client redirect list is not the problem here.

## Recommended follow-up

- Update user-facing docs and/or bootstrap output to make `https://argocd.shopping-cart.local` the only supported browser entrypoint for SSO login.
- Consider adding an explicit warning when a user tries to open Argo CD via `localhost:8080` after SSO is enabled.
- Keep `/etc/hosts` entries for `argocd.shopping-cart.local` and `keycloak.shopping-cart.local` in place so the canonical URL resolves locally.
