# Issue: acg-up opens Safari before Keycloak and SSO wiring are ready

## What I tested / observed

The current `make up` flow opens Safari on the Argo CD canonical URL before the Keycloak browser listener and the Argo CD SSO wiring are finished.

Observed failure in Safari:

```text
Safari Can’t Open the Page

Safari can’t open the page “https://argocd.shopping-cart.local/auth/login?return_url=...” because the server unexpectedly dropped the connection. This sometimes occurs when the server is busy. Wait for a few minutes, and then try again.
```

## Root cause

In `bin/acg-up`, the auto-open block runs immediately after the Argo CD browser HTTPS listener becomes ready, but before:

- Step 10e/14 installs the Keycloak browser HTTP listener
- Step 10f/14 wires Argo CD SSO
- the `/etc/hosts` updates for `argocd.shopping-cart.local` and `keycloak.shopping-cart.local`

That means Safari can launch before the login path is actually usable.

## Follow-up

Move the macOS browser auto-open until after the SSO wiring completes, or gate it on an explicit final readiness check for the Keycloak-backed login URL.
