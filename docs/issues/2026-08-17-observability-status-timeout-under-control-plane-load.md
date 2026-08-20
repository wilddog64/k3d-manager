# Observability status timeout under control-plane load

## Symptom

Grafana became sluggish and Slack `/hostinger-status`/`make status` reported
`UNKNOWN` with `status source unavailable`, even though Prometheus and Grafana
were healthy.

## Evidence

Observed on 2026-08-17:

```text
grafana_health=200 total=0.794630s
grafana_health=200 total=2.401871s
grafana_health=200 total=1.582681s
cve_query http=200 total=1.099613s
trivy_query http=200 total=3.112245s
k3d-k3d-cluster-server-0 cpu=371.07%
k3d-k3d-cluster-agent-0 cpu=230.61%
```

The ArgoCD application controller was using approximately `1522m` CPU and
Prometheus approximately `491m`. Kubernetes `/readyz` intermittently failed
the embedded etcd-readiness check, causing the webhook's sequential HTTP smoke
probes to exceed the status request timeout.

## Root cause

`_smoke_test_services` probed independent endpoints serially. A slow endpoint
could consume up to the full per-probe timeout before later checks ran, so the
caller received no JSON response and rendered `UNKNOWN`.

## Fix

Run the independent HTTP probes concurrently while preserving each probe's
individual result. This bounds the HTTP portion of the status request to the
slowest probe rather than the sum of all probe timeouts.

## Follow-up

Add Prometheus alerts for sustained control-plane CPU and slow Prometheus query
latency, and consider recording rules for the high-cardinality CVE table queries.
