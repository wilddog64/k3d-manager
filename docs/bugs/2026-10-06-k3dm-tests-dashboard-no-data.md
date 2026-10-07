# k3dm tests dashboard shows no data after metrics are pushed

Status: OPEN
Severity: High
Area: Test observability / Grafana datasource topology

## Evidence

After the `make test-all` run, the terminal reported:

```text
[k3dm-test-metrics] 1707 cases, 1 failed
[k3dm-test-metrics] metrics pushed: test-all/local
[test-all] metrics log: /tmp/k3dm-test-all-1791341010.log
make: *** [test-all] Error 2
```

The local Pushgateway was healthy and contained the published series:

```text
k3dm_test_cases_total{instance="test-all-local",job="k3dm-tests",target="test-all"} 1707
k3dm_test_exit_code{instance="test-all-local",job="k3dm-tests",target="test-all"} 2
k3dm_test_run_duration_seconds{instance="test-all-local",job="k3dm-tests",target="test-all"} 466
k3dm_test_suite_cases{instance="test-all-local",job="k3dm-tests",result="not_ok",suite="bats"} 1
```

The active localhost:9091 port-forward targets `ubuntu-hostinger`'s
`prometheus-pushgateway`. The dashboard source
`scripts/etc/grafana/dashboards/k3dm-tests-configmap.yaml` hard-codes datasource
UID `P5A1115AEDF367D43`, which is defined as the `prometheus-acg` datasource in
`kube-prometheus-stack-acg-values.yaml`. The dashboard therefore queries the ACG
Prometheus while the test publisher writes to the Hostinger Pushgateway.

The Grafana API itself requires authentication, so the deployed dashboard instance
and its resolved datasource could not be queried from the host during this check.

## Root cause

The producer, Pushgateway port-forward, Prometheus scrape target, and Grafana
dashboard are not using one explicit topology. A successful push can therefore be
invisible to the Grafana instance shown by the operator.

## Recommended fix

Choose and document the canonical Prometheus for local `test-all` metrics. Align the
Pushgateway port-forward, scrape configuration, Grafana datasource UID, and dashboard
deployment to that same target. Add a live smoke check that pushes a uniquely named
test metric and confirms it is queryable through the dashboard's Prometheus.
