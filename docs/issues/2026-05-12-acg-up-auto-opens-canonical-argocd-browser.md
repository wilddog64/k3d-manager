# Issue: `acg-up` did not auto-open the canonical Argo CD browser URL

## What was observed

After `make up` completed, Safari still ended up on a stale `localhost:8080` Argo CD URL and showed:

```text
Invalid redirect URL: the protocol and host (including port) must match and the path must be within allowed URLs if provided
```

The bootstrap had already wired the canonical browser hostname, but the operator still had to manually navigate away from the old localhost tab.

## Root cause

The bootstrap flow made `https://argocd.shopping-cart.local` available, but it did not actively open that canonical URL on macOS after the browser listener became healthy.

That left the previous localhost tab/bookmark path in place and made it easy to hit the Argo CD login route with a `return_url=http://localhost:8080/...` request, which Argo CD rejects.

## Follow-up

- Make `acg-up` open `https://argocd.shopping-cart.local` automatically on macOS once the browser listener is healthy.
- Keep the terminal-only localhost port-forward messaging in place so users do not confuse the raw forward with the browser entrypoint.
