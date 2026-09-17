# Checkout load-test dashboard has no load-test data

**Date:** 2026-09-17

## Finding

The Checkout Load Test dashboard is a planned observability view for the staged
checkout load test. Most panels show `No data` because no `k6_*` checkout metrics
are currently present in Prometheus; this is not a Grafana outage.

## Live checks

Prometheus queries returned zero series:

```text
count(k6_checkout_load_requests_total_total) = 0
count(k6_checkout_load_latency_seconds_p95) = 0
count(k6_vus) = 0
```

The CPU saturation panel has data because it uses existing Kubernetes
container CPU and resource-limit metrics, independent of the load test.

## Panel meaning

- Throughput: successful/request rate by checkout stage.
- Latency: checkout stage p50/p95/p99.
- Error rate: error requests divided by all requests.
- Orders/payments: state transition rates.
- CPU saturation: shopping-cart application CPU usage versus limits.
- Idempotency failures: total duplicate/idempotency failures.
- Peak VUs: maximum k6 virtual users.

## Root cause and follow-up

The load-test execution gate has not produced a live remote-write run for the
selected environment/run ID. Run the authenticated `loadtest_run` flow against
the target Prometheus, verify the remote-write receiver and `run_id`, then
refresh the dashboard. The load-test live-run prerequisites are documented in
`docs/bugs/2026-08-29-loadtest-slice-f-generator.md`.
