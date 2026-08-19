# Agent-0 kubelet proxy instability caused Grafana outage

## Incident

On 2026-08-19 Grafana, ArgoCD, and Keycloak returned 502 while services on
other k3d agents remained reachable. The port-forward supervisor was running,
but the Kubernetes API could not reach agent-0's kubelet:

```text
error upgrading connection: error dialing backend: proxy error from 127.0.0.1:6443 while dialing 192.168.97.3:10250, code 502: 502 Bad Gateway
Error from server (ServiceUnavailable): error trying to reach service: proxy error from 127.0.0.1:6443 while dialing 192.168.97.3:10250, code 502: 502 Bad Gateway
```

The Grafana pod was healthy after recovery (`3/3 Running`) and logged that its
HTTP server was listening on port 3000. Restarting `k3d-k3d-cluster-agent-0`
restored the kubelet proxy. Verification then returned all nodes `Ready`,
Grafana database `ok`, HTTP 200, and kubelet proxy output `ok`.

## Root cause

The local port-forward supervisor could restart a stale forward, but could not
repair the underlying agent-0 kubelet/backend failure, so it repeatedly looped.

## Prevention

1. Probe each node's kubelet proxy and alert after repeated 502/TLS failures.
2. Add a bounded, cooldown-protected agent recovery action followed by node and
   service-forward readiness checks.
3. Add anti-affinity/PDB coverage for Grafana, ArgoCD, and Keycloak so one agent
   failure does not remove every public control-plane endpoint.
4. Record node restart and forward-recovery events in status/observability and
   notify Slack when recovery is attempted.

Automatic node restart was not enabled during this incident; the restart was
performed manually to avoid an unbounded destructive recovery loop.
