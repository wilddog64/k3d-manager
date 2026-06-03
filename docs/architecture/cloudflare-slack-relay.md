# Architecture: Cloudflare Tunnel + Slack Relay

Two related subsystems that together expose local k3d-manager services to the
internet and accept Slack slash commands that drive cluster lifecycle.

---

## 1 — Cloudflare Named Tunnel (ingress)

`cloudflared` runs as a macOS LaunchDaemon (`com.k3d-manager.cloudflare-tunnel`)
installed by `bin/acg-up` Step 10h. It dials outbound to the Cloudflare edge
(no inbound firewall holes required) and routes public hostnames to local
port-forwarded services on the Mac.

```mermaid
flowchart LR
    Browser["Browser / Client"]

    subgraph CF["Cloudflare Edge (3ai-talk.org)"]
        DNS["DNS"]
        Edge["Cloudflare Edge\n(TLS termination)"]
    end

    subgraph Mac["Mac (LaunchDaemon)"]
        CFD["cloudflared\ncom.k3d-manager.cloudflare-tunnel\n~/.cloudflared/config.yml"]

        subgraph Locals["Local Listeners"]
            WH["k3dm-webhook\n127.0.0.1:7443"]
            ARGO["ArgoCD port-forward\nlocalhost:8080"]
            KC["Keycloak port-forward\nlocalhost:8880"]
            FE["Frontend HTTP listener\n127.0.0.2:80"]
            PROM["Prometheus port-forward\nlocalhost:80"]
            GRAF["Grafana port-forward\nlocalhost:80"]
        end
    end

    Browser -->|HTTPS| DNS
    DNS --> Edge
    Edge -->|"outbound tunnel\n(QUIC/HTTP2)"| CFD

    CFD -->|"webhook.3ai-talk.org"| WH
    CFD -->|"argocd.3ai-talk.org"| ARGO
    CFD -->|"keycloak.3ai-talk.org"| KC
    CFD -->|"frontend.3ai-talk.org"| FE
    CFD -->|"prometheus.3ai-talk.org"| PROM
    CFD -->|"grafana.3ai-talk.org"| GRAF
```

### Key files

| File | Purpose |
|------|---------|
| `scripts/etc/cloudflared/config.yml` | Static ingress rules (hostname → local service) |
| `~/.cloudflared/<tunnel-id>.json` | Tunnel credentials (restored from Keychain by `acg-up`) |
| `~/.cloudflared/cert.pem` | Cloudflare origin cert (restored from Keychain) |
| `bin/acg-up` Step 10h | Installs/updates the LaunchDaemon plist |
| `bin/acg-down` | Unloads and removes the LaunchDaemon plist |

---

## 2 — Slack Relay → Webhook Server (command path)

Slack slash commands travel through a Cloudflare Worker that verifies the
Slack signature and forwards to the local webhook server. The webhook server
runs each command as a background job and posts the result back to Slack via
`response_url`.

```mermaid
sequenceDiagram
    actor User as User (Slack)
    participant Slack as Slack API
    participant Worker as Cloudflare Worker<br/>workers/slack-relay/index.js
    participant Tunnel as Cloudflare Tunnel<br/>webhook.3ai-talk.org
    participant WH as k3dm-webhook<br/>bin/k3dm-webhook<br/>127.0.0.1:7443
    participant Job as Background Thread<br/>/tmp/k3dm-webhook-jobs/<id>/
    participant Bin as bin/acg-up<br/>bin/acg-down<br/>bin/acg-status

    User->>Slack: /acg-up aws
    Slack->>Worker: POST (X-Slack-Signature, response_url)
    Note over Worker: HMAC-SHA256 verify<br/>timestamp ±300s replay guard
    Worker->>Slack: 200 ⏳ Bringing up ACG cluster (aws)…
    Worker->>Tunnel: POST /api/v1/cluster<br/>Authorization: Bearer <token><br/>{action:"up", provider:"aws", response_url}
    Tunnel->>WH: HTTP POST 127.0.0.1:7443
    Note over WH: Bearer token auth<br/>409 if cluster job already running
    WH->>Job: spawn thread, write status=queued
    WH->>Worker: 202 {job_id}
    Job->>Bin: subprocess (make up / make down)
    Bin-->>Job: stdout/stderr → output file
    Job->>Slack: POST response_url ✅/❌ result
```

### Routes handled by k3dm-webhook

| Method | Path | Action |
|--------|------|--------|
| `POST` | `/api/v1/cluster` | `bin/acg-up` or `bin/acg-down` (action: up\|down) |
| `POST` | `/api/v1/cluster-status` | cluster health check → Slack |
| `POST` | `/api/v1/argocd-upgrade` | ArgoCD helm upgrade (chart_version, stage: acg\|infra) |
| `POST` | `/api/v1/analyze` | Claude AI log analysis → Slack |
| `GET`  | `/api/v1/status/<job_id>` | Poll job status + last 2 KB of output |

### Auth chain

```
Slack → Worker    HMAC-SHA256(SLACK_SIGNING_SECRET)  timestamp replay guard
Worker → Webhook  Authorization: Bearer <token>       stored in CF Worker secrets
Webhook token     macOS Keychain (k3dm-webhook-token) read by bin/k3dm-webhook at startup
```

### Key files

| File | Purpose |
|------|---------|
| `workers/slack-relay/index.js` | Cloudflare Worker — signature verify + relay |
| `bin/k3dm-webhook` | Python HTTP server — auth, job dispatch, Slack reply |
| `bin/k3dm-webhook-setup` | One-time setup: generate token, install LaunchAgent plist |
| `~/Library/LaunchAgents/com.k3d-manager.webhook.plist` | LaunchAgent keeping webhook server alive |
| `/tmp/k3dm-webhook-jobs/<id>/` | Job state: `status`, `output`, `action`, `response_url` |

### Concurrent job guard

`POST /api/v1/cluster` returns `409` if a cluster job (`up` or `down`) is
already running. The Worker surfaces this to Slack as:

> ⚠️ cluster job already running — use /acg-status to check progress
