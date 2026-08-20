# Grafana no-data and monitoring control-plane load

## Symptom

Grafana panels intermittently showed `No data` and `make status` returned
`Overall: UNKNOWN` because the local webhook/API path timed out. This was
observed together with a slow Grafana UI.

## Evidence

Read-only cluster inspection showed:

```text
prometheus-kube-prometheus-stack-prometheus-0  1/2 Running  8 restarts
kube-prometheus-stack-kube-state-metrics       0/1 CrashLoopBackOff 50 restarts
kube-prometheus-stack-prometheus-node-exporter 0/1 CrashLoopBackOff 30 restarts
prometheus-kube-prometheus-stack-prometheus-0  479m CPU  1309Mi memory
```

The Prometheus container has a `500m` CPU limit. Its liveness probe repeatedly
failed with `context deadline exceeded`, and Prometheus logs contained failed
federation writes, alert-notifier timeouts, and repeated duplicate/out-of-order
sample drops. Grafana itself remained Running; the upstream query engine was
the degraded component. The TSDB PVC remained Bound, so this is availability
and query latency degradation, not data deletion.

## Fix

The local observability values now request 500m and allow 1500m CPU for
Prometheus, request 100m/allow 500m for Grafana, and cap monolithic Loki at
500m CPU/1Gi memory. This gives Prometheus headroom for the CVE inventory
queries while preventing Loki from consuming unbounded node CPU. The existing
25Gi Prometheus PVC and retention settings are unchanged.

After the source change is deployed, verify that Prometheus remains `2/2`
Ready for at least two probe intervals, kube-state-metrics/node-exporter stop
crash-looping, Grafana panels return data, and `make status` no longer reports
an unavailable webhook. If the API remains saturated, the next step is
recording rules for the expensive CVE panels rather than increasing retention.
