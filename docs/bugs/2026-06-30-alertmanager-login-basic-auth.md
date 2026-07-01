# Bugfix: Alertmanager public GUI needs login protection and status-aware health checks

**Branch:** `k3d-manager-v1.12.0`
**Files:** `bin/alertmanager-auth-proxy`, `scripts/plugins/observability.sh`, `bin/cluster-status`, `Makefile`

---

## Problem

`https://alertmanager.3ai-talk.org` was exposed as a direct Cloudflare tunnel to the
raw Alertmanager listener. That made the URL public but unauthenticated, and the
health probe in `bin/cluster-status` could not report meaningful status when the
endpoint was not reachable.

The browser view should require a login prompt, and the status command should
use the same credentials so it reports the real Alertmanager health instead of
`HTTP 000000`.

---

## Fix

### Change 1 — add a local Alertmanager basic-auth proxy

Add a small reverse proxy that:

- listens on `localhost:9093`
- requires HTTP basic auth
- forwards authenticated traffic to the raw Alertmanager port-forward on `localhost:19093`

Cloudflare continues to point at `localhost:9093`, so the public hostname now
lands on the login gate instead of the raw backend.

### Change 2 — auto-generate and persist login credentials

Store Alertmanager UI credentials in Vault at:

- `secret/k3d-manager/alertmanager-basic-auth`

When the secret is absent, generate a password, persist it, and render a local
credentials file for the auth proxy and status check.

### Change 3 — make `cluster-status` report the authenticated health check

`bin/cluster-status` should read the same local credentials file and probe:

- `https://alertmanager.3ai-talk.org/api/v2/status`

with basic auth, reporting `HTTP 200` on success and a login-specific failure
if the proxy returns `401`.

---

## Files To Change

| File | Change |
|------|--------|
| `bin/alertmanager-auth-proxy` | New Python reverse proxy with basic auth |
| `scripts/etc/launchd/com.k3d-manager.alertmanager-auth-proxy.plist.tmpl` | New LaunchAgent template for the auth proxy |
| `scripts/etc/launchd/com.k3d-manager.alertmanager-port-forward.plist.tmpl` | Move raw Alertmanager backend to `localhost:19093` |
| `scripts/plugins/observability.sh` | Render credentials, install both LaunchAgents |
| `bin/cluster-status` | Probe Alertmanager with basic auth |
| `bin/cluster-down` | Remove both Alertmanager LaunchAgents |
| `Makefile` | Add install/uninstall targets and show-service-passwords output |
| `docs/howto/argocd-alerts.md` | Document login prompt and access path |
| `docs/howto/launchd-daemons.md` | Document proxy/backend split |

---

## Acceptance Criteria

- `https://alertmanager.3ai-talk.org` shows a browser login prompt
- successful login reaches Alertmanager
- `make status` reports `Alertmanager: HTTP 200`
- the same credentials appear in `make show-service-passwords`
- tests cover the auth proxy and the updated status probe

