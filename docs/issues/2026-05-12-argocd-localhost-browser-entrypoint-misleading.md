# Issue: Argo CD bootstrap/docs still imply localhost is the browser entrypoint

## Summary

The SSO flow rejects `localhost:8080` as the browser return URL, but the repo still had user-facing guidance that could send people back to localhost instead of the canonical HTTPS hostname.

## What was observed

The bootstrap output still described the localhost port-forward in a way that could be read as the browser path:

```text
ArgoCD reachable at http://localhost:8080 (launchd: com.k3d-manager.argocd-port-forward)
```

The how-to docs also still said:

```text
then open https://localhost:8080
```

When the browser used localhost, Argo CD returned:

```text
Invalid redirect URL: the protocol and host (including port) must match and the path must be within allowed URLs if provided
```

## Root Cause

The UI/bootstrap copy still treated the localhost port-forward as a browser destination even though the SSO flow expects the canonical HTTPS host:

```text
https://argocd.shopping-cart.local
```

That mismatch is confusing and leads users to open the wrong URL after SSO is enabled.

## Fix

- [`bin/acg-up`](/Users/cliang/src/gitrepo/personal/k3d-manager/bin/acg-up) now labels the localhost port-forward as terminal-only and points browser login at the canonical host.
- [`docs/howto/argocd.md`](/Users/cliang/src/gitrepo/personal/k3d-manager/docs/howto/argocd.md) now tells users not to use localhost as the browser SSO entrypoint.

## Follow-up

- Keep the canonical host in the bootstrap output and docs.
- Avoid reintroducing any browser-facing localhost copy for SSO flows.
