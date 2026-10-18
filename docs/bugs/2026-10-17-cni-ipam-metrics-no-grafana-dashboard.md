# Bug: Hostinger pod IP pool metrics have no Grafana dashboard; the triage guide cites panels that do not exist

**Filed:** 2026-10-17 (Claude, after the CNI IPAM fix went live)
**Status:** FIX COMMITTED — `21f48c28` (Codex); verified offline 2026-10-17; E2 live pending
**Priority:** P3 — the alerts work; only the at-a-glance view and the guide row are missing or wrong
**Severity:** low
**Approval:** approved — operator, 2026-10-17: "go ahead" (to a Pod IP pool dashboard plus the triage-row fix)
**Release:** v1.43.4 (bug; v1.43.4 and v1.43.5 are both at the 5-plan cap)
**Component:** `scripts/etc/argocd/platform-ops/` (new dashboard ConfigMap), `docs/guides/grafana-dashboards.md`
**Related:** `docs/bugs/2026-10-17-hostinger-pod-ip-pool-exhausted-leaked-cni-reservations.md`

## Problem

The CNI IPAM fix (`cf7b2882`, `93d6bfbf`) publishes six series to the hub Pushgateway
(`k3dm_cni_ipam_{reservations,range_size,stale_last_run,alloc_errors_1h,sweep_last_run_timestamp_seconds,probe_success}`,
label `host="hostinger"`, job `k3dm-cni-ipam`) and three alert rules. No dashboard queries them,
so the pool's state is visible only through Explore or an alert. The triage row added to
`docs/guides/grafana-dashboards.md` (line 614) begins "Pod IP pool panels show `No data`…" —
those panels do not exist.

## Fix

### 1. New file `scripts/etc/argocd/platform-ops/grafana-dashboard-host-cni-ipam.yaml`

Modelled on `grafana-dashboard-host-disk.yaml` (same metadata labels, same JSON style). The hub
dashboard ApplicationSet already includes `grafana-dashboard-*.yaml` from this directory, so no
deploy wiring changes.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-host-cni-ipam
  namespace: monitoring
  labels:
    grafana_dashboard: "1"
    release: kube-prometheus-stack
data:
  host-cni-ipam.json: |
    {
      "annotations": {"list": []},
      "editable": true,
      "graphTooltip": 1,
      "title": "k3dm Host Pod IP Pool",
      "uid": "k3dm-host-cni-ipam",
      "tags": ["k3dm", "cni", "ipam"],
      "schemaVersion": 39,
      "version": 1,
      "refresh": "1m",
      "time": {"from": "now-24h", "to": "now"},
      "panels": [
        {"id": 1, "type": "stat", "title": "Pool used %", "gridPos": {"h": 6, "w": 6, "x": 0, "y": 0}, "fieldConfig": {"defaults": {"unit": "percent", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "orange", "value": 80}, {"color": "red", "value": 90}]}}, "overrides": []}, "targets": [{"expr": "100 * k3dm_cni_ipam_reservations / k3dm_cni_ipam_range_size", "legendFormat": "{{host}}"}]},
        {"id": 2, "type": "stat", "title": "Reservations", "gridPos": {"h": 6, "w": 6, "x": 6, "y": 0}, "fieldConfig": {"defaults": {"unit": "none"}, "overrides": []}, "targets": [{"expr": "k3dm_cni_ipam_reservations", "legendFormat": "used"}, {"expr": "k3dm_cni_ipam_range_size", "legendFormat": "range"}]},
        {"id": 3, "type": "stat", "title": "Allocation errors (1h)", "gridPos": {"h": 6, "w": 6, "x": 12, "y": 0}, "fieldConfig": {"defaults": {"unit": "none", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 1}]}}, "overrides": []}, "targets": [{"expr": "k3dm_cni_ipam_alloc_errors_1h", "legendFormat": "{{host}}"}]},
        {"id": 4, "type": "stat", "title": "Probe status", "gridPos": {"h": 6, "w": 6, "x": 18, "y": 0}, "fieldConfig": {"defaults": {"unit": "none", "mappings": [{"type": "value", "options": {"0": {"text": "down", "color": "red"}, "1": {"text": "up", "color": "green"}}}]}, "overrides": []}, "targets": [{"expr": "k3dm_cni_ipam_probe_success", "legendFormat": "{{host}}"}]},
        {"id": 5, "type": "timeseries", "title": "Pool used % over time", "gridPos": {"h": 8, "w": 12, "x": 0, "y": 6}, "fieldConfig": {"defaults": {"unit": "percent", "custom": {"showPoints": "never"}, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "orange", "value": 80}, {"color": "red", "value": 90}]}}, "overrides": []}, "targets": [{"expr": "100 * k3dm_cni_ipam_reservations / k3dm_cni_ipam_range_size", "legendFormat": "{{host}}"}]},
        {"id": 6, "type": "timeseries", "title": "Stale reservations removed per sweep", "gridPos": {"h": 8, "w": 12, "x": 12, "y": 6}, "fieldConfig": {"defaults": {"unit": "none", "custom": {"showPoints": "never"}}, "overrides": []}, "targets": [{"expr": "k3dm_cni_ipam_stale_last_run", "legendFormat": "{{host}}"}]},
        {"id": 7, "type": "stat", "title": "Since last sweep", "gridPos": {"h": 6, "w": 12, "x": 0, "y": 14}, "fieldConfig": {"defaults": {"unit": "s", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "orange", "value": 1800}, {"color": "red", "value": 3600}]}}, "overrides": []}, "targets": [{"expr": "time() - k3dm_cni_ipam_sweep_last_run_timestamp_seconds", "legendFormat": "{{host}}"}]},
        {"id": 8, "type": "stat", "title": "Last push age", "gridPos": {"h": 6, "w": 12, "x": 12, "y": 14}, "fieldConfig": {"defaults": {"unit": "s"}, "overrides": []}, "targets": [{"expr": "time() - max(push_time_seconds{job=\"k3dm-cni-ipam\"})"}]}
      ]
    }
```

The 80% orange step matches `HostPodIPPoolHigh`; the 3600 s red step matches the staleness arm of
`HostCniIpamSweepStale`.

### 2. `docs/guides/grafana-dashboards.md`

Replace the triage row at line 614 (old → new):

```
| Pod IP pool panels show `No data` or a high reservation ratio | Hermes, the Hostinger sweep timer, or the hub Pushgateway port-forward is unavailable | check `k3dm_cni_ipam_reservations`, `k3dm_cni_ipam_range_size`, and the sweep timer/state file |
```

```
| **k3dm Host Pod IP Pool** shows `No data`, `Probe status` down, or a high `Pool used %` | `No data`: Hermes or the hub Pushgateway port-forward is down. `Probe status` down: the collector cannot read `/var/lib/k3dm/cni-ipam-sweep.state` over SSH. High usage with `Stale reservations removed` at 0: real pod load, not a leak | `systemctl list-timers k3dm-cni-ipam-sweep.timer` and the state file on the host; `bin/k3dm-cni-ipam-metrics --dry-run` on the hub |
```

Add one row to the dashboard inventory table (line 26 area), directly after `k3dm Host Disk`:

```
| k3dm Host Pod IP Pool | `k3dm-host-cni-ipam` | `platform-ops/grafana-dashboard-host-cni-ipam.yaml` | ArgoCD app `hub-grafana-dashboards` | hub |
```

### 3. Test `scripts/tests/bin/test_cni_ipam_dashboard.py`

Offline pytest only (no Grafana, no cluster). Cover M1–M4 and N1–N2 below.

## Acceptance

```yaml
must:
  - id: M1
    text: scripts/etc/argocd/platform-ops/grafana-dashboard-host-cni-ipam.yaml is a ConfigMap in namespace monitoring with labels grafana_dashboard "1" and release kube-prometheus-stack; data key host-cni-ipam.json parses as JSON with uid k3dm-host-cni-ipam and title "k3dm Host Pod IP Pool".
  - id: M2
    text: The dashboard has panels for pool used %, reservations, allocation errors (1h), probe status, pool used % over time, stale removed per sweep, time since last sweep and last push age; panel ids are unique.
  - id: M3
    text: Every panel expr references only k3dm_cni_ipam_* series the collector emits, or push_time_seconds with job="k3dm-cni-ipam".
  - id: M4
    text: The pool used % panels' warning step is 80, matching the HostPodIPPoolHigh threshold in scripts/etc/prometheus/rules/host-cni-ipam.yaml.
  - id: M5
    text: The grafana-dashboards.md triage row and inventory table name the dashboard "k3dm Host Pod IP Pool"; make validate-manifests passes.
must_not:
  - id: N1
    text: The guide never refers to Pod IP pool panels unless a platform-ops dashboard ConfigMap queries k3dm_cni_ipam_reservations (red on the pre-fix tree, where the row exists and no dashboard does).
  - id: N2
    text: grafana-dashboard-host-disk.yaml is byte-identical to its pre-fix content (uid k3dm-host-disk, five panels).
  - id: N3
    text: No ApplicationSet, plugin or Makefile file changes; deploy rides the existing grafana-dashboard-*.yaml include.
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, N1, N2, N3]
    kind: offline
    text: pytest scripts/tests/bin/test_cni_ipam_dashboard.py plus make validate-manifests and bats scripts/tests/plugins/grafana_dashboard_appsets.bats; N1 shown red on the pre-fix tree (a temp copy, not the working tree).
  - id: E2
    proves: [M1, M2]
    kind: live
    text: After push, ArgoCD app hub-grafana-dashboards (tracking k3d-manager-v1.43.4, include grafana-dashboard-*.yaml) syncs the ConfigMap — make platform-ops applies only a fixed list of five dashboards and does not deploy this one; Claude or the operator opens "k3dm Host Pod IP Pool" and every stat shows a value (Pool used % about 18, Probe status up).
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-host-cni-ipam.yaml (ConfigMap, data key host-cni-ipam.json)
  - docs/guides/grafana-dashboards.md triage table
  - scripts/etc/prometheus/rules/host-cni-ipam.yaml (threshold source)
  - bin/k3dm-cni-ipam-metrics (series names)
```

## Definition of Done

- [ ] Files: the new ConfigMap, the guide's triage row and inventory row, the new pytest file — nothing else.
- [ ] `python3 -m pytest -q scripts/tests/bin/test_cni_ipam_dashboard.py scripts/tests/bin/test_host_disk_rules.py` green; N1 red on the pre-fix tree, output pasted.
- [ ] `make validate-manifests` and `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` green.
- [ ] Commit message verbatim: `fix(grafana): add the Hostinger pod IP pool dashboard and correct its triage row`
- [ ] Pushed to `origin/k3d-manager-v1.43.4`; `git rev-parse origin/k3d-manager-v1.43.4` matches.
- [ ] memory-bank `activeContext.md` and `progress.md` updated with the SHA.

## What NOT to Do

- Do NOT create a PR, merge, or commit to `main`. Do NOT use `--no-verify`.
- Do NOT modify files outside the listed targets — in particular not `grafana-dashboard-host-disk.yaml`, any ApplicationSet, `scripts/plugins/`, the Makefile, or `scripts/lib/foundation/`.
- Do NOT apply anything to a cluster, call Grafana, or push to a Pushgateway.
- Do NOT add series the collector does not emit.
