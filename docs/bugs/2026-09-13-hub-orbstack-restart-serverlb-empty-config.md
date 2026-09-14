# Bug: hub OrbStack restart exposed empty serverlb config, watchdog loop, stale ambient redirection

**Branch:** `k3d-manager-v1.33.0`
**Filed:** 2026-09-13
**Status:** RECOVERED LIVE — durable fixes specced: Defect 1 → `2026-09-13-hub-recovery-serverlb-empty-upstreams.md`, Defect 2 → `2026-09-13-node-health-watch-restarts-on-host-api-unreachable.md`
**Related:** `2026-08-28-node-health-watch-restart-loop-slow-node.md`, `2026-09-11-hub-control-plane-readoption.md`

## Trigger

Planned OrbStack memory bump for zero-downtime headroom (user-approved, single-user lab, restart acceptable):

```
orbctl config set memory_mib 16384
orbctl stop && orbctl start
```

Docker VM went 11.73GiB → 15.66GiB. All k3d containers came back, and all 4 nodes went Ready inside the cluster. The host still lost the API and the frontend.

## Defect 1 — serverlb has no upstreams (latent since the 2026-09-10 rebuild)

- `kubectl` from the host: `Unable to connect to the server: EOF`. `curl https://127.0.0.1:61222/healthz` → `000`.
- `k3d-k3d-cluster-serverlb:/etc/confd/values.yaml` was the image default (85 bytes, mtime `Jan 1 1970`), with `6443.tcp: []`, `80.tcp: []` and `443.tcp: []`. k3d writes this file at cluster/node create, and the 2026-09-10/11 rebuild never did. nginx kept serving from its previously generated config until the restart made confd regenerate `stream { }`.
- `k3d node list` sees all 5 containers, so k3d's own view was intact; only the LB file was missing.

**Live fix (user ran):** restore the node list and restart only the LB. It uses container names, not IPs, because node IPs reshuffle on restart.

```yaml
ports:
  6443.tcp:
  - k3d-k3d-cluster-server-0
  80.tcp:   [server-0, agent-0, agent-1, agent-2]   # written as k3d-k3d-cluster-<name>
  443.tcp:  [server-0, agent-0, agent-1, agent-2]
settings:
  workerConnections: 1024
```

```
docker cp serverlb-values.yaml k3d-k3d-cluster-serverlb:/etc/confd/values.yaml && docker restart k3d-k3d-cluster-serverlb
```

This persists across OrbStack restarts, but is lost if the serverlb container is recreated.

**Durable fix needed:** hub recovery/readoption must assert serverlb `values.yaml` upstreams, e.g. a check in `hub_recovery` that fails when any `*.tcp` list is empty.

## Defect 2 — node-health-watch restarts a healthy node when the *host* can't reach the API

`bin/k3dm-node-health-watch` `_ready` runs `kubectl get node` from the host. With the LB broken, that fails, and the watchdog counts it as `NotReady`: 5 failures, then `docker restart k3d-k3d-cluster-agent-0`, every ~6 min (log: `did not recover within 100s`, repeat). agent-0 was Ready in-cluster the whole time. The loop stopped on its own once the LB was fixed.

The 2026-08-28 fix taught the watchdog to ignore slow `/healthz`, but "API unreachable" still reads as "NotReady".

**Durable fix needed:** distinguish "API unreachable" (no restart; log advisory) from "API reachable and node condition Ready != True" (restart candidate). For example, require a successful `kubectl get --raw /readyz` before counting a NotReady failure.

## Defect 3 — ambient pods lose inbound traffic after node restart

- After the LB fix, `frontend.3ai-talk.org` and `127.0.0.1:8000` still timed out, while `port-forward svc/frontend` returned 200.
- ztunnel on agent-2 logged `direction="inbound" dst.workload="frontend-..." error="connection failed: deadline has elapsed"` for every gateway request.
- All 4 `shopping-cart-apps` pods (the only ambient namespace) were on agent-2, whose in-pod redirection was stale after the node container restarts.

**Live fix (user ran):** `kubectl -n shopping-cart-apps rollout restart deploy` → frontend 200 local and public.

**Runbook note:** after any hub node restart, restart ambient-namespace workloads if the gateway → pod path times out.

## Defect 4 — hostNetwork pod keeps a stale node IP

The restart reshuffled node IPs (agent-1 `.2` → `.4`; `.2` became serverlb). `istio-cni-node-b7jk7` (hostNetwork) kept `podIP=192.168.97.2`, so its readiness probe dialed serverlb:8000 → `connection refused`. The pod stayed `0/1`, and `istio-cni-ubuntu-k3s` showed Progressing. It was the only stale hostNetwork pod; the node-exporters had updated.

**Live fix (user ran):** `kubectl -n istio-system delete pod istio-cni-node-b7jk7`. The DaemonSet recreated it at `.4`, 1/1.

## Final state (2026-09-13 ~13:40 PDT)

- Host API reachable; 4/4 nodes Ready; Vault unsealed.
- 37/37 ArgoCD apps Synced/Healthy.
- `frontend.3ai-talk.org` 200; `bin/smoke-test-cluster-health` 9/0.
- No watchdog restarts since 13:24.
- Docker VM 15.66GiB, hub using ~7.8GiB.
