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

## Follow-up

Make the Grafana port-forward supervisor detect terminated/Pending pod selections and restart only after a
Ready endpoint exists, instead of retaining a stale process.
