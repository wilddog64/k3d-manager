# Grafana 502 from stale service port-forward

## Symptom

`https://grafana.3ai-talk.org` returned Cloudflare HTTP 502 while the Grafana pod itself was healthy.

## Evidence

- Grafana pod was `3/3 Running`.
- The `com.k3d-manager.grafana-port-forward` LaunchAgent was repeatedly forwarding to a terminated
  Pending pod and logging kubelet proxy HTTP 502 errors.
- The local listener on port 3001 was absent or held by the stale forwarding process.
- After the Grafana pod became ready on a reachable node, fully reloading the LaunchAgent restored:
  - local Grafana `/api/health`: HTTP 200, database `ok`
  - public Grafana `/api/health`: HTTP 200

## Root cause

Grafana was restarted during dashboard reconciliation. The service port-forward selected the replacement
pod while it was Pending, then kept a stale forwarding process after that pod was replaced. Cloudflare had
no healthy localhost:3001 origin, so it returned 502.

## Resolution

The Hostinger access-layer LaunchAgents now run through a health-aware supervisor wrapper. Grafana is
checked at `/api/health` and Pushgateway at `/metrics`; after a startup grace period, a failed health
check terminates the stale `kubectl port-forward` and starts a fresh one. This keeps the tunnel alive
through pod replacement instead of retaining a forwarding process connected to a Pending or terminated
pod.
