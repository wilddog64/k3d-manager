# Checkout and Deployment dashboard No data triage — 2026-10-08

**Result:** PARTIAL — source configuration mismatches found; live PromQL and Grafana panel errors unavailable.
**Source revision:** `20b9993aaaa82e17d09a1f84dcd361d6d6f0bdf5`
**Screenshots:** Checkout Load Test (last 1h, blank run_id) and k3dm Deployment Metrics (last 24h, error icons).

## Live read-only check

Bridge request `20261008T164534Z-dashboard-observability`, action make-observability-status, job `39c7dff6`.
Accepted HTTP 202; terminal HTTP 200, body.status=success,
body.exit_code=0, classification=passed.
Full returned output (bridge bounds/truncates the beginning; not a complete hub inventory):

```text
                       1/1   Running   0               5d
INFO: [observability] --- trivy-system ---
scan-vulnerabilityreport-5676b6cd49-b9txr   0/1   Completed   0     40m
scan-vulnerabilityreport-6bc8bbd9fc-fxn5r   0/1   Completed   0     40m
scan-vulnerabilityreport-6fb6c5f87c-v5v4x   0/1   Completed   0     40m
scan-vulnerabilityreport-7759bd949-9nglm    0/1   Completed   0     39m
scan-vulnerabilityreport-85ccbdd5cb-92k8b   0/1   Completed   0     40m
scan-vulnerabilityreport-d86bcc49b-r5dh8    0/1   Completed   0     40m
scan-vulnerabilityreport-dcd56cf54-lgz7j    0/1   Completed   0     40m
trivy-operator-b6df5d6f6-9hnb8              1/1   Running     0     2d17h
trivy-server-0                              1/1   Running     0     5d
INFO: [observability] === ACG (ubuntu-hostinger) ===
INFO: [observability] --- monitoring ---
acg-kube-prometheus-stack-grafana-545c6f7785-8tvn2              3/3   Running   0     78d
acg-kube-prometheus-stack-kube-state-metrics-7b4b75c4d5-pqj57   1/1   Running   0     78d
acg-kube-prometheus-stack-operator-9fb86cbd6-5k66t              1/1   Running   0     78d
acg-kube-prometheus-stack-prometheus-node-exporter-6mp75        1/1   Running   0     78d
alertmanager-acg-kube-prometheus-stack-alertmanager-0           2/2   Running   0     78d
loki-0                                                          2/2   Running   0     49d
loki-gateway-95fdb789f-p6w4c                                    2/2   Running   0     78d
prometheus-acg-kube-prometheus-stack-prometheus-0               2/2   Running   0     38d
prometheus-pushgateway-6b76b495b5-d8v2q                         1/1   Running   0     78d
promtail-8qb7t                                                  1/1   Running   0     78d
INFO: [observability] --- trivy-system ---
acg-trivy-operator-8445955db-c8gnh         1/1   Running     0     37h
scan-vulnerabilityreport-b9895884f-db4wr   0/1   Completed   0     78s
trivy-server-0                             1/1   Running     0     46d
```

Hostinger Grafana 3/3, Prometheus 2/2, and Pushgateway 1/1 are running. This proves pod presence
only, not scrape health, local port-forward health, metric publication or datasource connectivity.
Direct cloud browser inspection of grafana.3ai-talk.org reaches the Grafana login page. No login
or credentials requested. The existing bridge allowlist exposes no arbitrary PromQL/Grafana API
query, so current samples and the exact error behind the screenshot icons remain unknown.

## Source inspection output

Parsed dashboard JSON from its YAML and the hub Helm values:

```text
Deployment target datasource UIDs: ['P5A1115AEDF367D43']
Hub additional datasources: [('acg-prometheus', 'NOT PINNED'), ('Loki', 'loki')]
Checkout panel datasource overrides: [None, None, None, None, None, None, None]
Checkout run_id datasource: Prometheus
Checkout CPU query: 100 * (sum(rate(container_cpu_usage_seconds_total{namespace="shopping-cart-apps"}[5m])) / clamp_min(sum(kube_pod_container_resource_limits{namespace="shopping-cart-apps",resource="cpu"}), 1))
Hub external Pushgateway keep filter: [{'source_labels': ['__name__'], 'regex': 'k3dm_test_.+', 'action': 'keep'}]
```

## Deployment Metrics

Every target in scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml references
P5A1115AEDF367D43. That UID is explicitly provisioned as prometheus-acg in app-cluster values;
hub values provision acg-prometheus with no matching UID pinned. If the screenshot is from hub
Grafana and no manual datasource supplies that UID, these targets cannot resolve their datasource.
Error icons support a query/datasource error rather than a confirmed empty metric result, but the
deployed datasource inventory and actual error must be inspected before declaring the live cause.

The hub test-metric scrape keeps only k3dm_test_.+, and the app federation does not select
k3dm_deployment_*; test-all activity does not establish deployment-series availability. A separate
hub Pushgateway target exists in current values, so historical docs asserting the hub has none
are not authoritative current live evidence.

The deployment producer DOES exist in bin/k3dm-webhook:_push_metrics, with health precheck,
bounded retries and three k3dm_deployment_* gauges. It publishes lifecycle completion rather than
ordinary test-all runs. Hostinger Pushgateway being Running is insufficient to prove the laptop
forward or these pushes work. Older issue docs claiming no producer are stale; do not repeat them.

## Checkout Load Test

The six k6-derived panels need actual k6 checkout metrics and an appropriate run/time range.
The generator exists, defaults to localhost:19190/api/v1/write (app-cluster Prometheus), and
requires confirmed loadtest_run execution. It is not ordinary test-all telemetry.
The scheduled baseline plan is still PROPOSED in source; no live run history was obtained.

The run_id variable selects datasource Prometheus and the panels have no explicit override.
On hub Grafana that normally selects hub/default Prometheus, while the producer writes app-cluster
Prometheus. Existing federation selectors do not import k6_*; therefore a successful app-cluster
load run alone would not necessarily populate the hub dashboard.
No recent run versus wrong datasource/run/time selection cannot be distinguished with current
live evidence. The receiver's live enablement remains unknown; do not launch a stress run to
diagnose a read-only telemetry problem.

CPU saturation is separate: it uses Kubernetes metrics and does not depend on run_id or k6.
Current source uses [5m], fixing the older [1m]/60s-scrape defect. This screenshot's CPU No data
must be investigated independently: deployed query may be old, or shopping-cart CPU/limit
series/federation may be absent from the selected datasource. Missing samples are not zero CPU.

Current ApplicationSets deploy Checkout through the app dashboard directory, contradicting older
guide prose saying there is no applier. Hub ApplicationSet explicitly includes only k3dm Tests
from that directory; presence of these two app dashboards on hub needs deployed ownership/history
verification. Do not treat old runbooks as fresh live measurement.

## Exact follow-up checks

1. Read the deployment panel error/Query inspector; inspect deployed datasource UID
   P5A1115AEDF367D43 and compare its URL to the intended app-cluster Prometheus.
2. In app-cluster Prometheus, query k3dm_deployment_success and pushgateway target up.
   If metrics are absent, inspect webhook push logs/local forward before attempting another deployment.
3. Compare k6_checkout_load_requests_total_total in app versus hub Prometheus, without a run_id
   filter first; then inspect run_id labels and widen the time range around the latest known load run.
4. Read CPU numerator and denominator separately:
   sum(rate(container_cpu_usage_seconds_total{namespace="shopping-cart-apps"}[5m]))
   and sum(kube_pod_container_resource_limits{namespace="shopping-cart-apps",resource="cpu"}).
5. Verify rendered dashboard JSON, datasource configuration, ArgoCD branch and scrape/receiver
   configuration before changing source. Stable datasource contract and honest empty-state messaging
   are the likely corrective work; no blind zeros or speculative topology change.

No dashboard/datasource edits, new bug declaration, runtime changes, stress traffic or service restart.
Documentation checks only; BATS/ShellCheck runtime tests are not applicable.
