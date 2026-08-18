# Grafana 502 persists during hub control-plane degradation

## Observation

After installing the health-aware port-forward supervisor, Grafana remained unavailable through the
public tunnel because the hub cluster itself was unhealthy. The supervisor repeatedly restarted the
forward when its `/api/health` check timed out; it did not retain a stale listener.

## Evidence

The hub API readiness check reported embedded etcd failures:

```text
Error from server (InternalError): ... [-]etcd failed ... [-]etcd-readiness failed ...
```

The Grafana endpoint and local forward were unavailable during the check:

```text
public HTTP 502
error code: 502
local HTTP 000
```

The Grafana pod was `3/3 Running`, but cluster events showed probe timeouts across Grafana, ArgoCD,
Loki, Trivy, Alertmanager, and other workloads. This indicates a hub/control-plane resource or embedded
etcd degradation rather than a Grafana-specific forwarding bug.

## Current mitigation

The new wrapper in `87382c7b` continuously retries the forward and restarts it after a failed health
check. Once hub API/etcd and pod networking recover, the public endpoint should recover automatically.

## Follow-up

Investigate hub control-plane/OrbStack resource pressure and embedded etcd health before restarting or
recreating workloads. Do not weaken the forward health gate or mask the hub readiness failure.

## Resolution (2026-08-18)

The single hub control-plane container was saturated (approximately 610% CPU) and embedded etcd/API
readiness was intermittent. Restarting `k3d-k3d-cluster-server-0` restored etcd/API responsiveness.
After the cluster settled, the edge listeners were refreshed and verified:

- `make status`: ArgoCD, Frontend, Keycloak, Prometheus, Grafana, product images, and login checks pass;
  only expected optional/non-deployed warnings remain.
- `https://grafana.3ai-talk.org/api/health`: HTTP 200, database `ok`.
- `https://keycloak.3ai-talk.org/health/live`: HTTP 200.
- `https://argocd.3ai-talk.org/healthz`: HTTP 200.
