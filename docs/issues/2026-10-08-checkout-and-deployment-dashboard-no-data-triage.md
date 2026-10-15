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


## Follow-up evidence — 2026-10-15 AWS ACG lifecycle jobs (dashboard still empty)

**Operator screenshot (2026-10-15 ~17:41 UTC):** The `k3dm Deployment Metrics` dashboard showed **No data** for all five panels: `Last acg-up Duration`, `Last acg-down Duration`, `Last Deployment Success`, `Last Deployment Time`, and `Deployment Duration Over Time`. The first three stat panels and the time-series panel show warning/error indicators; **No data + warning indicators does not establish that the underlying samples were never generated.**

Recent lifecycle jobs expected to be represented:

| Action | Webhook job ID | Reported outcome | Timing |
|---|---|---|---|
| AWS ACG `cluster-up` | `5f5cff23` | Success | approximately 18 minutes |
| AWS ACG `cluster-down` | `b0e9616d` | Success | approximately 1 minute |

The above outcomes are based on the Slack lifecycle notifications, **not** verified metric samples. They also do not independently prove full infrastructure readiness/deletion; separate lifecycle bugs track those distinctions.

**Confirmed source behavior:** `scripts/lib/webhook/lifecycle.py:_finish` calls `_push_metrics(action, provider, status, elapsed_secs, job_id)` for non-dry-run lifecycle completion. `bin/k3dm-webhook:_push_metrics` writes the three `k3dm_deployment_*` gauges to Pushgateway, but only if `PUSHGATEWAY_URL` is configured; failed pushes are logged as non-fatal warnings and can leave the lifecycle job green. As previously established, the dashboard uses fixed datasource UID `P5A1115AEDF367D43`; its deployed UID and reachability must be checked where the screenshot originated.

**Investigate before fixing:**
1. Capture the exact Grafana panel Query Inspector error, identify whether this is hub or app Grafana, and verify that UID `P5A1115AEDF367D43` resolves to the intended reachable Prometheus datasource.
2. Query `k3dm_deployment_success`, `k3dm_deployment_duration_seconds`, and `k3dm_deployment_last_timestamp_seconds` on the intended Prometheus datasource; inspect actual labels (`action`, `provider`, `job_id`) for the two named jobs and check panel time range.
3. Inspect the webhook metric-push logs for both job IDs (including `PUSHGATEWAY_URL` configuration, health-check/retry result and any `metrics push skipped` warning); check Pushgateway `/metrics` and the associated Prometheus scrape target. Distinguish producer failure, scrape/federation gaps, datasource mismatch, and query error.
4. Verify data persistence expectations after AWS sandbox down: metrics pushed only to an ephemeral app-cluster Pushgateway/Prometheus may disappear when that sandbox is destroyed. Establish an appropriate durable hub-side telemetry destination if historical lifecycle visibility is intended across sandbox deletions.
5. Add deterministic regression checks of successful and failed metric publication, dashboard datasource resolution, and history retention across sandbox teardown. Preserve nonfatal lifecycle execution if intended, but make telemetry publication failures visible to the operator.

**Scope and status:** Existing October 8 triage issue updated with a new recurrence; no specific root cause proven without live Prometheus/Pushgateway and Grafana inspection. No code, dashboard, infrastructure, or runtime changes in this documentation update.


## Follow-up evidence — 2026-10-15 `DeploymentMetricsStale` alert

An operator screenshot shows a firing `DeploymentMetricsStale` warning from Hostinger-side Prometheus. Its displayed labels include `action=up`, `provider=aws`, `instance=up-aws`, `job=k3dm-webhook`, `cluster=ubuntu-hostinger`, `status=failed`, and `severity=warning`. The alert annotation states that the deployment dashboard had zero series for **64 days** because the Pushgateway port-forward was removed on access-layer refresh, and summarizes `no k3dm deployment metric pushed for up/aws in >14d`.

**Verified source rule:** `scripts/etc/prometheus/rules-acg/k3dm-tests.yaml` defines:

```promql
time() - k3dm_deployment_last_timestamp_seconds > 1209600
```

with `for: 1h`. It detects a **stale existing time series** (>14 days old), not necessarily the absence of all time series, and does not itself verify whether Pushgateway is currently unreachable. The 64-day port-forward statement is historical rule annotation, not a fresh runtime diagnosis. The `status=failed` label belongs to the last observed deployment time series; it does **not** establish failure of the 2026-10-15 successful AWS `cluster-up` job `5f5cff23`. Likewise, the alert origin `cluster=ubuntu-hostinger` is a monitoring/source label, not proof that the AWS sandbox is down.

**New diagnostic leads:**
1. Confirm whether current webhook `PUSHGATEWAY_URL` is reachable from the machine running the webhook, including the relevant local port-forward lifecycle and post-refresh behavior (the rule's accompanying test-metrics annotation mentions `localhost:9091`, which must not be assumed to be the actual deployment publisher URL without checking configuration).
2. Read sanitized webhook logs around `5f5cff23` (up) and `b0e9616d` (down) for `metrics pushed`, `metrics push skipped`, missing configuration, or retry failures; compare producer metric samples against Prometheus scraped samples.
3. Query `k3dm_deployment_last_timestamp_seconds{action="up",provider="aws"}` and `k3dm_deployment_success{action="up",provider="aws"}` from Hostinger Prometheus and from the Grafana dashboard's chosen datasource, preserving `status` and `job_id` labels. Determine whether recent data reached a different destination, was lost when the ACG sandbox was destroyed, or is obscured by the hardcoded datasource UID.
4. Reconcile the contradictory-seeming observations: Prometheus alert sees an old `up/aws` series while Grafana displays `No data`. Investigate datasource, time range, and query errors before concluding the metric was never published.
5. Test the actual 14-day staleness behavior and explicitly cover **never-published / absent series**, which this particular expression alone will not alert on. Preserve `unknown` for unavailable data rather than manufacturing zero successes.

**Status:** Additional evidence appended; producer connectivity and active root cause remain unverified. No dashboard, rule, code, service or cloud changes made.


## Explicit additional finding — stale-series alert cannot detect never-published metrics

**Confirmed rule limitation (source review, 2026-10-15):** `DeploymentMetricsStale` uses `time() - k3dm_deployment_last_timestamp_seconds > 1209600`. PromQL evaluates this only for existing `k3dm_deployment_last_timestamp_seconds` series. If the publisher has **never** emitted a series for the required `action/provider` pair, the comparison yields **no result**, so this rule cannot fire for that missing pair. If an old series itself disappears due to retention or target removal, this expression likewise ceases to detect that pair.

**Operational impact:** A new or completely disconnected deployment telemetry stream can leave the dashboard empty with **no `DeploymentMetricsStale` alert**. The current screenshot's firing `up/aws` alert merely proves that one historical series exists in the alert evaluator's datasource, not that all expected lifecycle metrics are covered.

**Required remediation / acceptance tests:**
1. Define which `action/provider` series are **expected** in each deployment environment, and when they become expected (do not alert on AWS sandbox activity if no run has ever been scheduled and no freshness SLA applies). Keep this expected-series signal independently observable and persist it outside ephemeral AWS clusters.
2. Add an explicit absent-series / missing-telemetry check for *required* action/provider pairs (for example, carefully scoped `absent` or comparison against an expected-series inventory). Don't apply an unscoped `absent(k3dm_deployment_last_timestamp_seconds)` and incorrectly assume it validates every label combination.
3. Separate alert states and annotations: `stale existing series`, `expected series never published`, `telemetry publisher or scrape unavailable`, and `source not expected/temporarily inactive`. Do not represent missing telemetry as a failed deployment.
4. Test deterministic cases: fresh metric, stale metric, never-published required metric, series aged out, unsupported or intentionally inactive runner/provider, datasource failure, and recovery after publication. Verify expected alert firing and resolution with mocked/evaluation fixtures.
5. Preserve low-noise warnings and the 14-day threshold until the expected-series semantics and run cadence are agreed; do not invent an automatic freshness SLA for intentionally infrequent sandbox runs.

**Classification:** Observability coverage defect within this existing deployment-metrics issue, not evidence of an actual failed AWS deployment. No rule/config changes made by this documentation update.
