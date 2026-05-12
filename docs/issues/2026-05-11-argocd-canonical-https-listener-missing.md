# Argo CD canonical HTTPS hostname is not backed by a local listener

Status: OPEN

## What was observed

Safari showed:

```text
Safari can't open the page "https://argocd.shopping-cart.local"
because Safari can't connect to the server "argocd.shopping-cart.local".
```

On this machine, the hostname resolves locally:

```text
127.0.0.1 argocd.shopping-cart.local
```

But only the local Argo CD HTTP port-forward is listening:

```text
kubectl 75116 cliang    8u  IPv4 0xc70051a40737f04b      0t0  TCP 127.0.0.1:8080 (LISTEN)
kubectl 75116 cliang    9u  IPv6 0xcc0adfa07fd1ef59      0t0  TCP [::1]:8080 (LISTEN)
```

There is no local `443` listener backing `https://argocd.shopping-cart.local`, so the canonical browser URL cannot connect.

## Root cause

The bootstrap currently exposes Argo CD on `localhost:8080`, but the SSO/browser flow expects the canonical HTTPS hostname `https://argocd.shopping-cart.local`.

Without a local `443` proxy/listener that forwards to Argo CD, Safari cannot reach the canonical URL even though the cluster and Keycloak config are otherwise healthy.

## Recommended follow-up

- Add a local HTTPS listener or reverse proxy for `argocd.shopping-cart.local` that forwards to the Argo CD server.
- Keep the existing `localhost:8080` listener available for terminal smoke tests.
- Update bootstrap output so the browser entrypoint is explicit and not implied to be the same as the terminal login URL.

