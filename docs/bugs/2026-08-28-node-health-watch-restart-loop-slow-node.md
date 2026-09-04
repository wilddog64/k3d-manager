# node-health-watch bounces a slow-but-alive agent-0 into a restart loop

**Filed:** 2026-08-28
**Severity:** High — self-inflicted DNS + monitoring outages every ~6 min under hub CPU pressure.
**Status:** MITIGATED LIVE (watchdog `launchctl bootout` 2026-08-28 ~04:20 PDT — the forced
restarts stopped; agent-0 holds Ready on its own). Durable fix below NOT yet in git.

## Symptom

Overnight the hub regressed from the 2026-08-27 recovery: `kubectl get nodes` showed
`k3d-k3d-cluster-agent-0 NotReady`, `coredns` deployment `0/1 AVAILABLE` (DNS endpoints empty),
and `prometheus-...-0` stuck `Pending`/`Unknown`. agent-0's Docker container read
`Up About a minute` while its three siblings were `Up 12–13 hours`, with
`RestartCount=0 OOMKilled=false ExitCode=0` — i.e. **restarted by an external actor, not by
Docker's restart policy** (the policy would increment `RestartCount`).

## Root cause — the watchdog misclassifies "slow" as "dead" and bounces the node

`bin/k3dm-node-health-watch` (launchd `com.k3d-manager.node-health-watch`,
`K3DM_NODE_RECOVERY_ENABLED=1`) polls every 30s:

```sh
_healthy() { kubectl ... get --raw /api/v1/nodes/<node>/proxy/healthz --request-timeout=5s | grep -qx ok; }
_ready()   { kubectl ... get node <node> -o jsonpath=...Ready... | grep -qx True; }
# loop: if _ready && _healthy -> failures=0 else failures++; failures>=3 -> docker restart <node>
```

Under hub CPU starvation the **healthz proxy call times out at 5s even though the node is
`Ready` and serving pods**. Three such timeouts (~90s) trip `docker restart k3d-...-agent-0`;
a 300s cooldown follows; then it bounces the node again. `node-health-watch.log` shows the loop:
restart 04:11:04 → "recovered" 04:13:35 → probe-fail 04:14/04:15/04:16 → restart 04:17:18,
repeating ~every 6 min.

This is the **node-level instance of the same disease** as the keycloak/CoreDNS tight-probe
loop (`2026-08-27-keycloak-restart-loop-tight-probes.md`): an aggressive health probe with a
short timeout kills a slow-but-alive target under CPU contention. The restart never addresses
the CPU pressure — it **adds** load (container + pod re-init) and evicts the two singletons
pinned to agent-0, so it makes the hub worse:

- **CoreDNS** (single replica, scheduled on agent-0) → every bounce takes cluster DNS down.
- **Prometheus** (`prometheus-...-0` PVC is local-path on agent-0) → the pod can only schedule
  on agent-0, so a bounce leaves it `Pending`/`Unknown` until the node returns.

## Fix — only recover a genuinely dead node, and give a slow one room

Loosen the watchdog so a slow healthz on a `Ready` node is not treated as failure. All levers
are env-driven (plist `EnvironmentVariables`) except the trigger-logic change:

1. **Trigger on authoritative death, not proxy latency.** Count a failure only when `_ready`
   is False (the node controller's own verdict). Treat `_healthy` as advisory/logging, not a
   restart trigger — a `Ready` node with a slow `/healthz` is alive.
2. **Raise the healthz request timeout** `5s → 15s` (parameterize as
   `K3DM_NODE_RECOVERY_HEALTHZ_TIMEOUT`) so a slow-but-alive proxy is not a false negative.
3. **Raise `K3DM_NODE_RECOVERY_FAILURE_THRESHOLD` `3 → 5`** so a transient CPU burst does not
   trip a restart.
4. Complementary: land the Step 2 hub load-shed so the node stops going slow at the source
   (same demand-side fix as the pod probes).

## Related fragility (follow-up, not this fix)

Both DNS and monitoring are **single points of failure hostage to the flakiest node**:
- CoreDNS runs 1 replica (k3s-managed) and lands on agent-0. A second replica with pod
  anti-affinity would keep DNS up across an agent-0 blip. k3s-managed — needs a manifest
  override / HelmChartConfig (see the CoreDNS note in the keycloak doc).
- Prometheus PVC pins it to agent-0. Acceptable for a dev hub, but it means every agent-0
  event is a monitoring gap.

## Verification (acceptance)

- With the watchdog stopped (or fixed), `docker inspect agent-0` `StartedAt` stops advancing;
  the node holds `Ready` across a sustained window with no new `restarting ... agent-0` lines
  in `node-health-watch.log`.
- `coredns` deployment stays `1/1 AVAILABLE`; `kube-dns` endpoints non-empty.
- `prometheus-...-0` schedules and progresses toward `2/2`.
- Re-enable the watchdog only after the fix; confirm it no longer restarts a `Ready` node.

## Evidence

`~/.local/share/k3d-manager/logs/node-health-watch.log` (2026-08-28): repeated
`health probe failed (n/3)` → `restarting k3d-k3d-cluster-agent-0 after 3 consecutive
kubelet-proxy failures` → `recovered`, cycling on the 300s cooldown. `docker inspect
k3d-k3d-cluster-agent-0`: `RestartCount=0 OOMKilled=false ExitCode=0`, `StartedAt` advancing
every few minutes while siblings stayed up 12h+.
