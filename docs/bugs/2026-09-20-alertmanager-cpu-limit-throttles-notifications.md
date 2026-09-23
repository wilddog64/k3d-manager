# Alertmanager's 50m CPU limit throttles it 83% of the time, failing Prometheus notifications

**Filed:** 2026-09-20
**Alert:** `PrometheusErrorSendingAlertsToAnyAlertmanager` — "Prometheus encounters more than 3% errors sending alert to any alertmanager"
**Cluster:** hub (`k3d-cluster`)
**Status:** OPEN — root cause identified, fix not applied

## Symptom

Prometheus reports a sustained notification error ratio above the 3% alert threshold, with
periodic spikes to 20–40%. Cumulative on the current alertmanager pod: **168 errors / 1469
sent = 11.4%**.

Prometheus log, `notifier.go:622`, recurring every few minutes:

```
level=ERROR msg="Error sending alerts" component=notifier
  alertmanager=http://10.42.0.65:9093/api/v2/alerts count=46
  err="Post \"http://10.42.0.65:9093/api/v2/alerts\": context deadline exceeded"
```

## Root cause — alertmanager is CPU-throttled continuously

`scripts/etc/helm/observability/kube-prometheus-stack-values.yaml:90-96` caps alertmanager at
`cpu: 50m` — 5 ms of CPU per 100 ms CFS period.

Measured `container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total` for the
`alertmanager` container, 2-hour steps over 24 h:

| Time (UTC) | Throttled fraction |
|---|---|
| 09-19 16:00 | 0.858 |
| 09-19 18:00 | 0.846 |
| 09-19 20:00 | 0.862 |
| 09-19 22:00 | 0.817 |
| 09-20 00:00 | 0.851 |
| 09-20 02:00 | 0.857 |
| 09-20 04:00 | 0.845 |
| 09-20 06:00 | 0.873 |
| 09-20 08:00 | 0.826 |
| 09-20 10:00 | 0.839 |
| 09-20 12:00 | 0.842 |
| 09-20 14:00 | 0.861 |

**83–87% of every CFS period is throttled, flat across the whole window.** This is a chronic
condition, not an incident.

Mean usage is only `0.021` cores, which is why the limit looks generous on an average — but
alertmanager's work is bursty. With **61 alerts firing** and Prometheus POSTing batches of up
to 46 at a time, the parse + dedup + group + nflog-persist path needs far more than 5 ms
within a single 100 ms window. The request stalls across many throttled periods and exceeds
Prometheus's notifier timeout (default **10 s**), so the POST is recorded as an error even
though alertmanager eventually processes it.

Memory is not implicated: working set is 28 MiB against a 64 MiB limit.

## Secondary failure mode — stale pod IPs

A distinct error appears whenever the alertmanager pod is rescheduled:

```
err="Post \"http://10.42.0.33:9093/api/v2/alerts\": dial tcp 10.42.0.33:9093: connect: no route to host"
```

Prometheus discovers alertmanagers via `kubernetes_sd_configs` `role: endpoints`. Four
distinct pod IPs appear in the 24 h metric series — `10.42.0.11`, `10.42.0.23`, `10.42.0.33`,
`10.42.0.65` — because the pod restarted 5 times. Until the Endpoints update propagates,
Prometheus keeps POSTing to the dead IP and every attempt fails, driving the ratio to 1.0.

The 14:30–14:50Z window where the ratio hit **1.0** is this mode: the k3s server was
crash-looping after the restart documented in
`2026-09-09-hub-kine-compaction-stall.md`, which both evicted alertmanager (exit 255,
`reason=Unknown`) and slowed Endpoints propagation. That window is an amplifier, **not** the
cause — the >3% breach is continuous since at least 09-19 16:00 and the throttle fraction is
unchanged before and after.

## Relationship to the kine compaction stall

Independent. Earliest notification errors are 09-17 23:00, before compaction died at
09-18 02:16Z, and at that point the rate was 1.7% — under threshold. The throttling is
constant regardless of datastore state. Fixing kine will not fix this; fixing this will not
fix kine.

## Fix

Raise the alertmanager CPU limit in
`scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`:

```yaml
    resources:
      requests:
        memory: 32Mi
        cpu: 10m
      limits:
        memory: 64Mi
        cpu: 50m
```

to:

```yaml
    resources:
      requests:
        memory: 64Mi
        cpu: 50m
      limits:
        memory: 128Mi
        cpu: 500m
```

Rationale: `500m` gives 50 ms per CFS period, a 10x headroom over the measured burst need,
while staying a small fraction of one core. The request rises to `50m` so the scheduler
accounts for the real baseline. Memory goes to `128Mi` for headroom as the firing-alert count
grows — the current 28 MiB working set is 44% of the existing 64 MiB limit, which is closer to
the ceiling than it should be.

The ACG variant (`kube-prometheus-stack-acg-values.yaml`) declares `alertmanager:` with no
`resources` block and is therefore unthrottled — no change needed there.

## Verification

After applying:

1. `container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total` for the
   `alertmanager` container drops from ~0.85 to near 0.
2. No `context deadline exceeded` in the Prometheus notifier log over a 1 h window.
3. `rate(prometheus_notifications_errors_total[10m]) / rate(prometheus_notifications_sent_total[10m])`
   stays below 0.03 for 1 h, so `PrometheusErrorSendingAlertsToAnyAlertmanager` resolves.

## Follow-up — the stale-IP mode is not fixed by this

Raising the CPU limit does not address `no route to host` after a reschedule. That mode is
inherent to endpoint-IP discovery plus a single-replica alertmanager, and it resolves on its
own once Endpoints propagate. It only became visible because the pod restarted 5 times in a
day, which is itself a consequence of the server-node instability. No change proposed here;
revisit if it persists once the hub is stable.
