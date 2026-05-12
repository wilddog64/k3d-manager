# Issue: Safari keeps returning to the stale localhost Argo CD tab

## What was observed

Even after the canonical browser URL was made available, Safari still ended up on the localhost-based login path and showed:

```text
Invalid redirect URL: the protocol and host (including port) must match and the path must be within allowed URLs if provided
```

The browser state appears to keep reusing the old `localhost:8080` tab/session instead of navigating to the canonical host.

## Root cause

`bin/acg-up` used a generic `open` handoff on macOS. That is enough to launch the browser, but it does not reliably replace an already-open Safari tab that is still sitting on the stale localhost flow.

## Fix

- [`bin/acg-up`](/Users/cliang/src/gitrepo/personal/k3d-manager/bin/acg-up) now tries to drive Safari directly with `osascript` so the browser is actively navigated to `https://argocd.shopping-cart.local`.
- If Safari automation is unavailable, it falls back to the generic `open` handoff.

## Recommended follow-up

- Re-test `make up` on macOS Safari and confirm the canonical URL is actually focused in the browser.
- If Safari still restores the stale localhost page, consider adding an explicit browser-state warning before the final open step.
