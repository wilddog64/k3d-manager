# Bug: Keycloak browser redirect has no local HTTP listener on the Mac host

**Date:** 2026-05-12  
**Severity:** High - prevents Argo CD SSO login from reaching Keycloak in the browser  
**Status:** Open

## Symptom

Safari showed:

```text
Safari Can't Connect to the Server
Safari can't open the page "keycloak.shopping-cart.local/realms/shopping-cart/protocol/openid-connect/auth?... "
because Safari can't connect to the server "keycloak.shopping-cart.local".
```

The browser did not show a certificate warning because the redirect target is `http://keycloak.shopping-cart.local/...`, not `https://...`.

## What Was Observed

`/etc/hosts` on the Mac host contained:

```text
127.0.0.1 keycloak.shopping-cart.local
127.0.0.1 argocd.shopping-cart.local
```

The hostname resolved to loopback, but no local HTTP listener was bound on port `80`, so Safari had nothing to connect to.

## Root Cause

The Keycloak browser redirect is plain HTTP and expects a browser-side listener on `keycloak.shopping-cart.local:80`.

The previous browser wiring only covered:

- Argo CD canonical HTTPS on `argocd.shopping-cart.local:443`
- in-cluster Keycloak routing for service-to-service traffic

It did not install a persistent Mac-side HTTP listener for Keycloak.

## Recommended Fix

- Keep `keycloak.shopping-cart.local` mapped to `127.0.0.1` on the Mac host.
- Add a launchd-managed HTTP listener on local port `80` that forwards to `svc/keycloak` on the cluster.
- Keep the existing Argo CD HTTPS listener on `443` unchanged.

## Follow-up Notes

- The missing certificate warning was expected for this failure mode because the browser redirect was HTTP.
- The browser-side Keycloak listener should be treated as separate from the in-cluster Keycloak VirtualService / CoreDNS routing.
