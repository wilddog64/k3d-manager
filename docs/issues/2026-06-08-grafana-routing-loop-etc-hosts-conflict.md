# Issue: Grafana/Prometheus Routing Loop & Port Conflict (Local vs Tunnel)

**Branch:** `k3d-manager-v1.6.4`
**Date:** 2026-06-08
**Files:** `bin/acg-up`, `bin/acg-refresh`, `scripts/etc/cloudflared/config.yml`

---

## Symptom

Grafana (`https://grafana.3ai-talk.org`) frequently becomes unreachable with a `503 Service Unavailable` or `Connection Refused` error, even when the cluster is healthy and the `data-layer` is synced. 

Running `acg-refresh` sometimes fixes it temporarily, but the error recurs, or works via `curl` (HTTP) but fails in the browser (HTTPS).

## Root Cause

There is a fundamental architecture conflict between how the project handles **Local Port Forwarding** and **Cloudflare Tunnels**.

### 1. The `/etc/hosts` Hijack
The `acg-up` script adds the following entries to the Mac's `/etc/hosts`:
```text
127.0.0.1 prometheus.3ai-talk.org
127.0.0.1 grafana.3ai-talk.org
```
This forces the browser to resolve these public domains to `localhost`, completely bypassing the "real" Cloudflare Tunnel path from the internet.

### 2. The Port 443 Bottleneck
The project uses `socat` to listen on `127.0.0.1:443` to provide HTTPS for local browser access. However:
*   The `socat` process (managed by `com.k3d-manager.argocd-browser-https`) is hard-coded to forward **all** traffic to `127.0.0.1:8080` (ArgoCD).
*   When a user visits `https://grafana.3ai-talk.org`, the browser connects to `127.0.0.1:443`.
*   `socat` sends the request to **ArgoCD**, which does not know how to handle Grafana traffic and returns an error or drops the connection.

### 3. Log Permission & Path Mismatches
*   `acg-refresh` was attempting to manage the Cloudflare tunnel as a **System Daemon** (`/Library/LaunchDaemons`), while `acg-up` installed it as a **User Agent** (`~/Library/LaunchAgents`).
*   The log file `/Users/cliang/.local/share/k3d-manager/logs/cloudflare-tunnel.log` was often created by `root` (during `acg-up`), causing the user-level `cloudflared` process to fail to start due to `Permission Denied` when writing logs.

---

## My Two Cents: How to Fix This Permanently

The current setup is trying to be "hybrid" (local + tunnel) but the two methods are fighting each other. Here is the recommended architectural fix:

### Phase 1: Stop Hijacking Public Domains
We should **never** put public `.org` domains in `/etc/hosts`. 
*   **Fix:** Remove `grafana.3ai-talk.org` and `prometheus.3ai-talk.org` from the `_HOSTS_LIST` in `bin/acg-up`.
*   **Result:** The browser will resolve the DNS to Cloudflare. Traffic will go: `Browser` → `Cloudflare Edge` → `Cloudflare Tunnel (on Mac)` → `Local Ingress (Port 80)` → `Cluster`. This is 100% reliable and avoids the Port 443 conflict entirely.

### Phase 2: Unify `acg-up` and `acg-refresh`
`acg-refresh` should be a subset of `acg-up`, not a separate implementation of the same logic.
*   **Fix:** Move the LaunchAgent/Daemon installation logic into a shared library function (e.g., in `scripts/lib/acg.sh`) so both scripts use identical paths, labels, and permission checks.

### Phase 3: Replace `socat` with a proper Local Proxy
If we MUST support local HTTPS for multiple services (ArgoCD, Grafana, Keycloak) on the same port (443):
*   **Fix:** Replace the multiple `socat` listeners with a single **Nginx** or **Caddy** container/process running on the Mac.
*   **Logic:** It can perform SNI routing—sending `argocd.*` to 8080 and `grafana.*` to 80 locally. This is how "real" ingress works and would stop the 443 collision.

---

## Temporary Workaround
To reach Grafana right now without a routing loop:
1.  Use the HTTP URL: [http://grafana.3ai-talk.org](http://grafana.3ai-talk.org) (The browser won't hit the `socat` 443 listener).
2.  OR: Delete the `grafana` and `prometheus` lines from your `/etc/hosts` file.
