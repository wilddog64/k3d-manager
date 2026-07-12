# Bug: Grafana charts don't persist — Prometheus TSDB on emptyDir + tiny retentionSize

**Filed:** 2026-07-06
**Verified live:** 2026-07-07 (context `k3d-k3d-cluster`, ns `monitoring`)
**Source:** /ask agent observation → confirmed against the running cluster

## Symptom

Grafana panels ("charts") lose history after a short window — the data behind the
panels is gone, so ranges longer than the retained window render empty.

## Root cause — two independent limiters, both real

### 1. `retentionSize: 1800MB` is the binding limit (masks `retention: 7d`)

Prometheus enforces `min(retention, retentionSize)`. `runtimeinfo` reports
`storageRetention: "1w or 1GiB776MiB"` — the size hits first.

Measured on the live pod:
- Compacted blocks ingest at **~70 MB/h** for this cluster.
- 1800MB therefore holds only **~26h**; with head + WAL counted against the cap the
  real retained window was **15 hours** (`prometheus_tsdb_lowest_timestamp_seconds` =
  2026-07-06 12:00Z at an eval time of 2026-07-07 02:58Z → 0.62 days).
- 7 days at ~70 MB/h ≈ **11.4 GB**. `/prometheus` (`/dev/vdb1`) has **206 GB free** —
  1800MB is a needless bottleneck far below the 7d intent.

### 2. `/prometheus` is `emptyDir` — any pod reschedule wipes everything

No PVC exists in `monitoring`. The `prometheus-kube-prometheus-stack-prometheus-db`
volume is `emptyDir: {}` and the Prometheus CR `spec.storage` is empty.
- emptyDir survives *container* restarts (it's pod-scoped) — which is why the 8
  container restarts did not zero it and the pod has held data since 2026-06-07.
- But any *pod-level* event — node drain, `make up` recreate, StatefulSet pod
  deletion, OOM pod eviction, k3d cluster restart — deletes the whole TSDB to zero.

## Config source

`scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`

```yaml
prometheus:
  prometheusSpec:
    retention: 7d
    retentionSize: 1800MB      # <- caps at ~1 day; too small
    # <- no storageSpec: chart defaults /prometheus to emptyDir
```

## Fix

Add a persistent volume and raise/remove the size cap so `retention: 7d` governs:

```yaml
prometheus:
  prometheusSpec:
    retention: 7d
    retentionSize: 20GB        # headroom > 7d at ~70 MB/h (~11.4 GB); or drop it entirely
    storageSpec:
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 25Gi
```

Then `helm upgrade` the release. NOTE: converting emptyDir → volumeClaimTemplate
recreates the StatefulSet pod, so the current (already tiny) history resets once on
apply; all history after that persists across reschedules.

## Related (separate issue)

`docs/bugs/2026-07-06-grafana-repeatedly-killed-by-liveness-probe-under-argocd-image-updater-dashboard-load.md`
— Grafana *server* restarting under a 30d/401 dashboard query is a different failure
(the server, not the data). It compounds the visible gaps but is not why data expires.
