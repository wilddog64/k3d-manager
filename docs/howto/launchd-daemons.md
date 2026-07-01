# k3d-manager LaunchAgents Reference

All `com.k3d-manager.*` LaunchAgents live in `~/Library/LaunchAgents/`.
Templates (where they exist) are in `scripts/etc/launchd/`.
Install via `make <target>` or via the plugin function noted below.

---

## Daemons at a Glance

| Label | Port / Action | KeepAlive | Install Method | Log |
|-------|--------------|-----------|----------------|-----|
| `com.k3d-manager.webhook` | HTTP server :9000 | ✅ | `make install-webhook` | `~/Library/Logs/k3dm-webhook.log` |
| `com.k3d-manager.webhook-token-rotate` | Rotates Slack webhook token | ❌ (timer: 6h) | `make install-token-rotator` | `~/Library/Logs/k3dm-webhook-token-rotate.log` |
| `com.k3d-manager.ssh-tunnel` | Reverse SSH tunnel → ACG EC2 `:6443` | ✅ | `tunnel_start` | `/tmp/k3d-manager-tunnel.out` |
| `com.k3d-manager.cloudflare-tunnel` | Cloudflare tunnel → `3ai-talk.org` | ✅ | manual / homebrew | `~/.local/share/k3d-manager/logs/cloudflare-tunnel.log` |
| `com.k3d-manager.argocd-port-forward` | ArgoCD UI → `localhost:18080` (ubuntu-k3s) | ✅ | `argocd_install` | `~/.local/share/k3d-manager/logs/argocd-pf.log` |
| `com.k3d-manager.frontend-port-forward` | Frontend → `frontend.shopping-cart.local:80` (ubuntu-k3s) | ✅ | manual | `~/.local/share/k3d-manager/logs/frontend-pf.log` |
| `com.k3d-manager.vault-port-forward` | Vault → `localhost:18200` (k3d-k3d-cluster) | ✅ | `make install-vault-port-forward` | `~/Library/Logs/k3dm-vault-port-forward.log` |
| `com.k3d-manager.keycloak-port-forward` | Keycloak → `localhost:8880` / `keycloak.shopping-cart.local` (k3d-k3d-cluster) | ✅ | `keycloak_install` | `~/.local/share/k3d-manager/logs/keycloak-pf.log` |
| `com.k3d-manager.prometheus-port-forward` | Prometheus → `localhost:19090` (k3d-k3d-cluster) | ✅ | `make install-prometheus-port-forward` | `~/Library/Logs/k3dm-prometheus-port-forward.log` |
| `com.k3d-manager.alertmanager-port-forward` | Alertmanager → `localhost:9093` (k3d-k3d-cluster) | ✅ | `make install-alertmanager-port-forward` | `~/Library/Logs/k3dm-alertmanager-port-forward.log` |
| `com.k3d-manager.cleanup` | Purges old job state dirs (`~/.local/share/k3d-manager/jobs/`) | ❌ (timer: daily 03:00) | `make install-cleanup` | `~/Library/Logs/k3dm-cleanup.log` |
| `com.k3d-manager.acg-watch` | Watches ACG sandbox TTL; auto-extends or notifies | ❌ (on-demand) | `acg_watch_install` | `/tmp/k3d-manager-acg-watch.err` |

---

## Persistent Port-Forwards

These use `KeepAlive=true` — launchd auto-restarts them if the process exits.

### `com.k3d-manager.argocd-port-forward`
- **Cluster:** `ubuntu-k3s` (ACG EC2)
- **Mapping:** `localhost:18080` → `svc/argocd-server:80` (namespace: `cicd`)
- **Browser access:** via `com.k3d-manager.argocd-browser-https` (loopback HTTPS listener at `argocd.shopping-cart.local:443`)
- **Template:** none (installed by `argocd_install` plugin function)

### `com.k3d-manager.frontend-port-forward`
- **Cluster:** `ubuntu-k3s` (ACG EC2)
- **Mapping:** `127.0.0.2:80` → `svc/frontend:80` (namespace: `shopping-cart-apps`) via port `3000:80`
- **Browser access:** `http://frontend.shopping-cart.local/`
- **Template:** none (installed manually)

### `com.k3d-manager.vault-port-forward`
- **Cluster:** `k3d-k3d-cluster` (local k3d)
- **Mapping:** `localhost:18200` → `vault-0:8200` (namespace: `secrets`)
- **Template:** `scripts/etc/launchd/com.k3d-manager.vault-port-forward.plist.tmpl`
- **Install:** `make install-vault-port-forward`

### `com.k3d-manager.keycloak-port-forward`
- **Cluster:** `k3d-k3d-cluster` (local k3d)
- **Mapping:** `localhost:8880` → `svc/keycloak:80` (namespace: `identity`)
- **Browser access:** `http://keycloak.shopping-cart.local/` (via `/etc/hosts` → 127.0.0.1:8880)
- **Health check:** `http://keycloak.shopping-cart.local/health/live`
- **Template:** none (installed by `keycloak_install` plugin function via wrapper script)

### `com.k3d-manager.prometheus-port-forward`
- **Cluster:** `k3d-k3d-cluster` (local hub)
- **Mapping:** `localhost:19090` → `svc/prometheus-operated:9090` (namespace: `monitoring`)
- **Health check:** `http://localhost:19090/-/ready`
- **Template:** `scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl`
- **Install:** `make install-prometheus-port-forward`

### `com.k3d-manager.alertmanager-port-forward`
- **Cluster:** `k3d-k3d-cluster` (local hub)
- **Mapping:** `localhost:9093` → `svc/kube-prometheus-stack-alertmanager:9093` (namespace: `monitoring`)
- **Browser access:** `https://alertmanager.3ai-talk.org/`
- **Health check:** `https://alertmanager.3ai-talk.org/api/v2/status`
- **Template:** `scripts/etc/launchd/com.k3d-manager.alertmanager-port-forward.plist.tmpl`
- **Install:** `make install-alertmanager-port-forward`

---

## Network Daemons

### `com.k3d-manager.ssh-tunnel`
- **Tool:** `autossh` (auto-reconnecting SSH)
- **Tunnels:**
  - `-L 0.0.0.0:6443:localhost:6443` — forward local 6443 → k3s API on EC2
  - `-R 8200:127.0.0.1:18200` — reverse-forward EC2:8200 → local Vault (for ESO)
- **Install:** `tunnel_start` (writes and bootstraps the plist dynamically with current EC2 IP)
- **Target host:** `ubuntu` user on ACG EC2 IP (updated on each `acg-up`)

### `com.k3d-manager.cloudflare-tunnel`
- **Tool:** `cloudflared`
- **Config:** `~/.cloudflared/config.yml`
- **Exposes:** `grafana.3ai-talk.org`, `prometheus.3ai-talk.org` → services on ubuntu-k3s; `alertmanager.3ai-talk.org` → Alertmanager on the local hub
- **Install:** via homebrew service (`brew services start cloudflared`) + plist at `~/Library/LaunchAgents/com.k3d-manager.cloudflare-tunnel.plist`

---

## Periodic Daemons

### `com.k3d-manager.webhook`
- **Trigger:** `KeepAlive=true` (persistent HTTP server)
- **Port:** 9000 (listens for Slack slash commands)
- **Binary:** `bin/k3dm-webhook` (Python)
- **Install:** `make install-webhook`
- **Restart after code changes:** `make restart-webhook`

### `com.k3d-manager.webhook-token-rotate`
- **Trigger:** `StartInterval=21600` (every 6 hours)
- **Action:** Rotates the Slack webhook HMAC token in Vault and reloads the webhook process
- **Template:** `scripts/etc/launchd/com.k3d-manager.webhook-token-rotate.plist.tmpl`
- **Install:** `make install-token-rotator`

### `com.k3d-manager.cleanup`
- **Trigger:** `StartCalendarInterval` (daily at 03:00)
- **Action:** Removes job state dirs older than 7 days from `~/.local/share/k3d-manager/jobs/`
- **Binary:** `bin/k3dm-cleanup`
- **Template:** `scripts/etc/launchd/com.k3d-manager.cleanup.plist.tmpl`
- **Install:** `make install-cleanup`

### `com.k3d-manager.acg-watch`
- **Trigger:** `RunAtLoad=true` (one-shot on bootstrap, not KeepAlive)
- **Action:** Monitors ACG sandbox TTL; sends Slack DM before expiry; optionally auto-extends session
- **Script:** `~/.local/share/k3d-manager/acg-watch-run.sh` (generated by `acg_watch_install`)
- **Install:** `acg_watch_install` plugin function

---

## Common Operations

```bash
# Reload webhook after code changes
make restart-webhook

# Install/reinstall port-forwards (run once or after kubeconfig changes)
make install-vault-port-forward
make install-prometheus-port-forward

# Check LaunchAgent status
launchctl print "gui/$(id -u)/com.k3d-manager.webhook"
launchctl print "gui/$(id -u)/com.k3d-manager.prometheus-port-forward"

# View logs
tail -f ~/Library/Logs/k3dm-webhook.log
tail -f ~/Library/Logs/k3dm-prometheus-port-forward.log
tail -f ~/Library/Logs/k3dm-alertmanager-port-forward.log

# Manually unload/reload a specific agent
launchctl bootout "gui/$(id -u)/com.k3d-manager.<label>"
launchctl bootstrap "gui/$(id -u)" ~/Library/LaunchAgents/com.k3d-manager.<label>.plist
```

---

## /etc/hosts Entries (required for browser access)

```
127.0.0.1   keycloak.shopping-cart.local
127.0.0.1   argocd.shopping-cart.local
127.0.0.2   frontend.shopping-cart.local
127.0.0.1   prometheus.shopping-cart.local
127.0.0.1   grafana.shopping-cart.local
127.0.0.1   prometheus.3ai-talk.org
127.0.0.1   grafana.3ai-talk.org
```

`127.0.0.2` (frontend) uses the loopback alias — managed by `com.k3d-manager.loopback-alias.plist`.
