# Hub control-plane and edge-forward outage

## Symptoms

`make status` reported Keycloak and Prometheus HTTP 502, with ArgoCD/Grafana also
flapping between 200 and 502. The public tunnel returned 502 while local forwards
were absent.

## Evidence

The hub node and monitoring state showed:

```text
k3d-k3d-cluster-agent-0 NotReady ... NodeStatusUnknown
error: error dialing backend: proxy error ... 192.168.97.5:10250, code 502
prometheus-kube-prometheus-stack-prometheus-0 0/2 Terminating ... agent-0
loki-0 0/2 Terminating ... agent-0
```

The server readiness check reported `etcd-readiness failed`; server logs showed
multi-second Kine/SQLite queries and a large state database/WAL. After restarting
the server and agent, the agent eventually became Ready and Prometheus/Loki were
recreated, but the access-layer wrappers continued flapping while the Kubernetes
API recovered.

The active tunnel configuration also used an IPv6-sensitive `localhost` origin for
Prometheus, Alertmanager, and Grafana. Those origins are now pinned to IPv4 in the
checked-in Cloudflare config.

## Root cause

An exited k3d agent left node-affine stateful workloads terminating. The resulting
Kine/API overload caused port-forward backend 502s. Separately, the tunnel's
`localhost` Grafana origin could resolve to `::1` while the forward bound IPv4.

## Recovery performed

- Restarted `k3d-k3d-cluster-agent-0` and the local k3d cluster server/cluster.
- Force-removed only stale Prometheus/Loki pod objects so controllers could recreate them.
- Regenerated/restarted edge forwards and pinned Cloudflare monitoring origins to
  `127.0.0.1`.

## Follow-up

The node-health watcher currently logs `agent container ... is not running; no
restart attempted`; it should recreate or alert on an exited agent rather than only
restarting a running container. Kine/SQLite growth and repeated remediation scans
also need capacity/retention work. Do not treat `make status` as healthy until all
local listeners and public probes return successfully.
