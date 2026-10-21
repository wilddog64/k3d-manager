# k3dm Tests (`k3dm-tests`) — hub

[← Grafana dashboards index](../grafana-dashboards.md)

These metrics come from a laptop-side push and therefore exist only after someone runs
`make test-all` (or its `make test-metrics` compatibility wrapper). The hub Prometheus
imports the `k3dm_test_*` series from the laptop's Hostinger Pushgateway on `host.internal:9091`,
so the same dashboard is now visible from the hub Grafana without changing the hub Grafana
port-forward. Pushgateway retains the last value indefinitely, so read the **Suite
freshness** panel first. The exit-code panel is informational only: `make test-all` here exits 2 when `test-pytest`
falls back to a `python3` without pytest and 0 when a real `pytest` is on PATH, so the same
healthy suite reports either value depending on the shell it ran in. Failed cases, never the
exit code, drive health. The dashboard ConfigMap is owned only by the hub dashboard
ApplicationSet; the ACG dashboard ApplicationSet excludes it so the two Argo applications
cannot overwrite each other.

| Panel | Query |
|---|---|
| Suite freshness | `time() - k3dm_test_last_timestamp_seconds` |
| Last passing run | `time() - k3dm_test_last_success_timestamp_seconds` |
| Failed cases | `k3dm_test_cases_failed` |
| Failing cases by suite | `k3dm_test_suite_cases{result="not_ok"} > 0` (empty on a clean run) |
| Run duration over time | `k3dm_test_run_duration_seconds`, `k3dm_test_suite_duration_seconds` |
| Total cases | `k3dm_test_cases_total` |
| Run completion | `k3dm_test_run_complete` |
| Exit code | `k3dm_test_exit_code` (informational only) |

**Duration.** `make test-all` times the whole run and pushes it as
`k3dm_test_run_duration_seconds{target="test-all"}`. Per-suite duration is published only for
suites whose runner prints its own time: pytest's `in X.XXs` summary and unittest's
`Ran N tests in X s`. BATS prints no per-file time, so BATS suites have no duration series
rather than a fake `0`. A run pushed by an older exporter still shows the old `0`/millisecond
values until the next `make test-metrics`.

**Where the alerts live.** The six `k3dm-tests.alerts` rules are in
`scripts/etc/prometheus/rules-acg/k3dm-tests.yaml`, labelled
`release: acg-kube-prometheus-stack`, and are applied to the app cluster by
`make observability-acg`. They deliberately do **not** sit with the other rule files under
`scripts/etc/prometheus/rules/`, which are hub-side: the hub has no Pushgateway, its
`federate-acg` job selects only `{job=~"node-exporter|kubelet|kube-state-metrics|istiod|envoy"}`
(minus the k3s control-plane `apiserver_`, `etcd_`, `scheduler_` and `workqueue_` series, which
k3s exposes on the kubelet endpoint and which made the scrape outgrow its timeout),
so the rules were placed with the Pushgateway on the app cluster. The hub now also imports the
`k3dm_test_*` series from the Hostinger Pushgateway (see above), but only for the dashboard: the
alerts stay on Hostinger so each fires once. Apply a change to them with
`kubectl --context ubuntu-hostinger apply -f scripts/etc/prometheus/rules-acg/k3dm-tests.yaml`;
`make prometheus-rules` applies only the hub-side `rules/` directory. `DeploymentMetricsStale`
moved for the same reason.
`OfflineSuiteRunMissed` fires when no run, pass or fail, has been pushed for 26h, which is the
signature of a failed push.
