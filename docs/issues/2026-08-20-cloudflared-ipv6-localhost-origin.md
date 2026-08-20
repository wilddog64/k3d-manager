# Bug: Cloudflared ArgoCD origin resolves localhost to unavailable IPv6 listener

**Filed:** 2026-08-20

## Evidence

Cloudflare returned Error 1033 while the tunnel connector was absent. After the edge restart,
Cloudflared connected successfully, but ArgoCD still returned HTTP 502 and the tunnel log showed:

```text
Unable to reach the origin service ... dial tcp [::1]:8080: connect: connection refused
```

The ArgoCD port-forward is a local `kubectl` listener. Depending on restart timing it may bind only
IPv4, while `localhost` resolves to IPv6 first on this host. Grafana (`127.0.0.1:3001`) recovered
through the same tunnel, confirming this is origin address selection rather than a Cloudflare port
collision.

## Fix

The repository Cloudflared config now uses `http://127.0.0.1:8080` for the ArgoCD ingress. The
runtime config was reloaded with `make refresh-edge CLUSTER_PROVIDER=k3s-hostinger`.
