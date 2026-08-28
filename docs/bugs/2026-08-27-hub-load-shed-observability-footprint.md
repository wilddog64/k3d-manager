# Hub load-shed — trim the observability footprint (Step 2)

**Filed:** 2026-08-27
**Severity:** Medium — durable capacity fix; follows Step 1 governance
(`2026-08-27-hub-cpu-overcommit-resource-governance.md`).
**Status:** SPEC

## Why

Step 1 (resource governance + istio HPA pinning) freed ~2.7 CPUs and restored control-plane
responsiveness, but the hub still runs hot (agent-2 load avg ~40 vs a healthy target < 15) on
a 10-CPU / 12.6 GB VM. Step 1 stopped the *thrash*; Step 2 removes *demand*. The single-node
hub carries a full multi-tenant observability stack sized for a real cluster.

## Measured footprint (2026-08-27, `kubectl top -n monitoring`)

| Pod | CPU | Mem | Note |
|---|---|---|---|
| `prometheus-kube-prometheus-stack-prometheus-0` | **916m** | **1671Mi** | biggest single consumer on the hub |
| `loki-0` | 205m | 234Mi | |
| `loki-canary` (DaemonSet, 4 pods) | ~193m total | ~105Mi | **synthetic self-monitoring — no product value on a dev hub** |
| `kube-prometheus-stack-grafana` | 71m | 247Mi | keep |
| `prometheus-node-exporter` (DaemonSet, 4) | ~87m total | | keep (node metrics) |
| kube-state-metrics / alertmanager / operator | ~78m | | keep |

## Fix (highest impact first)

### 2a. Drop the `loki-canary` DaemonSet (~193m, 4 pods)

Pure synthetic write/read probe. Zero value on a single-node dev hub; it is 4 pods burning
~0.2 CPU continuously.

File: `scripts/etc/helm/observability/loki-values.yaml`. Disable the canary (exact key depends
on the loki chart version — verify against `helm show values grafana/loki`; typically):
```yaml
monitoring:
  selfMonitoring:
    enabled: false
    lokiCanary:
      enabled: false
lokiCanary:
  enabled: false
```

### 2b. Cut Prometheus CPU (916m — the big lever)

Prometheus CPU is dominated by scrape volume × frequency and rule evaluation. On a hub:

File: `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`.
- **Global scrape interval** — raise the default `scrapeInterval` (e.g. 30s → 60s) for the
  stack's own service monitors. (The `federate-acg` job was already moved 30s→60s in
  `977d9e11`; extend that to the default.)
- **Retention** — currently `retention: 7d` / `retentionSize: 20GB`. For a dev hub, 3d / 8GB
  is ample and cuts TSDB compaction/query CPU + disk.
- **Trim scrape targets** — drop node-exporter/cadvisor high-cardinality collectors not used
  by any live dashboard/alert, and disable ServiceMonitors for components you do not chart.
- **Set a Prometheus CPU limit** — it currently has none of its own ceiling; a limit (e.g.
  `1500m`) caps runaway without starving normal operation (mem stays generous — TSDB needs it).

Ground each cut against what the Grafana dashboards + PrometheusRules actually query before
removing a scrape target — do not blind-drop metrics a live alert depends on.

### 2c. (Optional) Right-size Loki

`loki-0` at 205m/234Mi is reasonable; only revisit if 2a+2b are insufficient. `loki-values.yaml`
already sets the read/backend/write replicas to 0 (single-binary mode) — good.

## Out of scope

- ArgoCD / istio governance — Step 1 (already implemented).
- The **ArgoCD chart-version drift** discovered during Step 1 rollout (live `argo-cd-10.4.0`
  vs pinned `ARGOCD_CHART_VERSION=7.8.1`) — a **prerequisite** to any formal `deploy_argocd`
  redeploy, tracked separately; do not fold into this spec.

## Rollout

Edit the two committed values files, then reapply via the observability deploy path
(`argocd.sh` / the observability ApplicationSet), per the CLAUDE.md "reapply ApplicationSets on
every release" rule so `$values` tracks the release branch. Do not hand-`kubectl edit` the
prometheus/loki resources — they are ArgoCD-managed and will be reverted.

## Verification (acceptance)

- `kubectl top pod -n monitoring` — Prometheus CPU down meaningfully from 916m; `loki-canary`
  pods gone.
- `docker stats` hub total sustained < ~800%; agent load avg < ~15.
- Grafana dashboards still render; no PrometheusRule references a now-missing series
  (`count(ALERTS)` and key dashboards spot-checked).
- Prometheus not OOM/CrashLooping under the new mem envelope.

## Evidence

`kubectl top -n monitoring` 2026-08-27 (table above); `retention: 7d` / `retentionSize: 20GB`
at `kube-prometheus-stack-values.yaml:11-12`; `loki-canary` DaemonSet `DESIRED=4`.
