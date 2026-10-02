# Grafana Overview — Readable: Firing Alerts and Request Rate show "No data"; Build Info shows a truncated job and a pod IP

**Filed:** 2026-10-02
**Branch:** `k3d-manager-v1.40.0`
**Severity:** low. Two of the five Overview panels are empty, and the table answers "which Grafana" with a pod IP.
**Status:** FIXED (pending sync)
**Related:** `docs/bugs/2026-09-30-grafana-overview-no-data.md` (that fixed the scrape: the ServiceMonitor `release`
label; these are query defects), `docs/bugs/2026-10-01-grafana-overview-raw-series-labels.md` (the readable copy and
the Build Info contract this changes).

## Evidence (hub `k3d-k3d-cluster`, Prometheus `monitoring/prometheus-kube-prometheus-stack-prometheus-0`, 2026-10-02)

| Query | Result |
|---|---|
| `count(grafana_alerting_result_total)` | empty: the metric does not exist in Grafana 11.4.0 |
| `grafana_alerting_alerts{state="alerting"}` | present, value `0` |
| `count(irate(grafana_http_request_duration_seconds_count[1m]))` | empty |
| `count(rate(grafana_http_request_duration_seconds_count[5m]))` | `44` |
| `count by (status_code)(grafana_http_request_duration_seconds_count)` | `200`, `302`, `304`, `401`, `503`, `-1` |

The Request Latency panel works because it uses `[$__rate_interval]`. Request Rate hardcodes `[1m]` with a 1m step:
with the Grafana ServiceMonitor's scrape interval, a 1m window does not hold the two samples `irate` needs.

Build Info renders `11.4.0 | oss | kube-prometheus-sta… | 10.42.1.171:3000`. The Job column is the same for every
row and is cut off; the instance is a pod IP that changes on every restart.

## Fix (both copies, kept identical)

Files:
- `scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml` (app clusters)
- `scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml` (hub)

1. **Firing Alerts** (panel `id` 6):
   - `expr`: `sum(grafana_alerting_alerts{job=~"$job", instance=~"$instance", state="alerting"}) or vector(0)`
   - Keep `instant: true` and the legend.
   - Set `fieldConfig.defaults.noValue` to `"0"` in **both** copies; the hub copy lacks it today.
2. **Request Rate by HTTP Status** (the `timeseries` panel titled so):
   - `expr`: `sum by (status_code) (rate(grafana_http_request_duration_seconds_count{job=~"$job", instance=~"$instance"}[$__rate_interval]))`
   - Remove the target's `"interval": "1m"`.
   - The legend and description are unchanged.
3. **Build Info** (panel `id` 10): columns **Version, Edition, Pod**.
   - Include names `["version","edition","pod"]`, index order in the same order, and rename to `Version`, `Edition`, `Pod`.
   - Drop `job` and `instance`. The `pod` label is present on `grafana_build_info`.
   - Update the panel description to say "pod name" rather than "job and instance".
4. Change nothing else in either file: the other panels, the variables, the title, the labels/annotations.

## Tests (`scripts/tests/plugins/grafana_dashboard_appsets.bats`)

1. Update `_assert_build_info_contract` to the new columns: include `["version","edition","pod"]`, order
   `version,edition,pod`, renames `edition=Edition,pod=Pod,version=Version`. Keep its other checks.
2. A new `_assert_query_contract <file>`, checked against both copies:
   - The Firing Alerts expr contains `grafana_alerting_alerts` and `or vector(0)`, and does **not** contain
     `grafana_alerting_result_total`.
   - `noValue == "0"`.
   - The Request Rate expr contains `rate(` and `[$__rate_interval]`, and contains neither `irate(` nor `[1m]`.
   - The target has no `interval` key.
3. A byte-identity test: the Firing Alerts and Request Rate panels are identical across the two copies, like the
   existing Build Info identity test.
4. Mutation tests, in the existing snapshot style (`BATS_TEST_TMPDIR` copy, `yq -i`, `run`, expect failure):
   - put `[1m]` back → the query contract is red;
   - put `grafana_alerting_result_total` back → the query contract is red.

## Rules

- `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` is green.
- `yq` parses both files, and the embedded JSON passes `jq -e .`.
- No cluster, network or git commits. Leave the changes uncommitted. Do not touch `CHANGELOG.md`.
- Update this doc: Status FIXED (pending sync), plus a short Resolution section.

## Resolution

Both readable dashboard copies now use the available Grafana alert metric with a zero fallback, the adaptive rate interval, and Version/Edition/Pod Build Info columns. Tests enforce the query contract, panel identity, and regression mutations.

## Rollout

The hub copy syncs from the release branch through the platform-ops app. The app-cluster copy syncs through
`grafana-dashboards-acg`. Both pick up the change on ArgoCD's next sync. Check the Overview, where:

- Firing Alerts reads `0`;
- Request Rate shows `HTTP 200` and the other status series;
- Build Info shows the version, the edition and the pod name.

## Follow-up (2026-10-02): Build Info Pod column truncated

**Status:** FIXED (pending sync)

After the sync, Firing Alerts reads `0` and Request Rate shows series. Build Info shows
`11.4.0 | oss | kube-prometheus-stack-graf…`: the three columns share the panel width equally, and the pod name
(`kube-prometheus-stack-grafana-64756ff7c7-lvbz4`, 46 characters) does not fit a third of a `w: 12` panel.

### Fix (panel `id` 10, both copies, kept identical)

Set `fieldConfig.overrides` (empty today) to fix the two short columns' widths, so Pod takes the rest:

```json
"overrides": [
  {"matcher": {"id": "byName", "options": "Version"}, "properties": [{"id": "custom.width", "value": 90}]},
  {"matcher": {"id": "byName", "options": "Edition"}, "properties": [{"id": "custom.width", "value": 90}]}
]
```

The matcher names are the **renamed** column names. Change nothing else.

### Tests (`scripts/tests/plugins/grafana_dashboard_appsets.bats`)

1. Extend `_assert_build_info_contract`: the overrides set `custom.width` 90 for `Version` and for `Edition`, and
   there is no width override for `Pod`.
2. The existing Build Info byte-identity test covers both copies; keep it green.
3. One mutation in the existing snapshot style: delete the overrides (`yq -i`) → the contract is red.

### Rules

- `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` is green; `yq` parses both files and the
  embedded JSON passes `jq -e .`.
- No cluster, network or git commits. Leave the changes uncommitted. Do not touch `CHANGELOG.md`.
- Update this section's Status to FIXED (pending sync).

### Note: the HTTP 200 baseline

Measured on the hub 2026-10-02: the steady ~0.4 req/s is `/api/health` (kubelet probes, 240 per 10 min). The
small ripple is sampling: probe hits land in a 30s-scraped counter, so each `rate` window holds a whole number of
hits and alternates between neighbouring counts. The 12:00–13:30 bursts are real traffic: dashboard-sidecar
`/api/admin/provisioning/dashboards/reload` calls during the ArgoCD syncs, plus browser sessions.

## Follow-up (2026-10-02): Request Rate description names the health-probe baseline

**Status:** FIXED (pending sync)

The operator read the steady HTTP 200 line as unexplained load. It is kubelet `/api/health` probes (see the note above).

### Fix (panel `id` 2, "Request Rate by HTTP Status", both copies, kept identical)

Replace `description` with exactly:

```
Request rate grouped by HTTP status code. The steady ~0.4 req/s HTTP 200 baseline is kubelet /api/health liveness and readiness probes; bursts above it are real traffic (browser sessions, dashboard provisioning reloads). Status -1 means the request did not produce a normal HTTP response, usually because instrumentation recorded an internal failure before a response was available.
```

Change nothing else: not the title, the query, or the legend.

### Tests (`scripts/tests/plugins/grafana_dashboard_appsets.bats`)

1. Extend `_assert_query_contract`: the Request Rate description contains `kubelet /api/health` and `Status -1`.
2. The existing Request Rate byte-identity test keeps both copies identical.
3. One mutation in the snapshot style: restore the old description → the query contract is red.

### Rules

Same as the Build Info follow-up. Update this section's Status to FIXED (pending sync).

## Follow-up (2026-10-02): Firing Alerts counts Grafana-managed rules, of which there are none

**Status:** FIXED (pending sync)

The panel counts `grafana_alerting_alerts{state="alerting"}`. The hub has **no** Grafana-managed alert rules: every
`grafana_alerting_alerts` state (`alerting`, `pending`, `nodata`, `error`, `normal`) is `0`. So the panel reads `0`
by construction. Every real alert is a Prometheus rule routed through Alertmanager; on 2026-10-02 the hub had
`TrivyCriticalVulnerabilityDetected` ×48, `E2EVerificationFailing` ×3, `KubeHpaMaxedOut` ×2, `KubeJobFailed`,
`CPUThrottlingHigh` and `PrometheusOutOfOrderTimestamps` firing, plus the always-on `Watchdog` and `InfoInhibitor`.

### Fix (panel `id` 6, both copies, kept identical)

- `title`: `Firing Alerts (Prometheus)`
- `targets[0].expr`: `count(ALERTS{alertstate="firing", alertname!~"Watchdog|InfoInhibitor"}) or vector(0)`
  (no `$job`/`$instance` filter: those select the Grafana instance, not the alert source)
- `targets[0].legendFormat`: `Firing alerts`; keep `instant: true` and `refId`.
- `description`: `Prometheus alerts currently firing (the ALERTS series), excluding the always-on Watchdog and InfoInhibitor. Grafana-managed alert rules are not counted; none are defined. Open Alertmanager for the list.`
- `fieldConfig.defaults.thresholds.steps`: `[{"color":"green"},{"color":"red","value":1}]`. Keep `noValue: "0"`.
- Change nothing else in either file.

### Tests (`scripts/tests/plugins/grafana_dashboard_appsets.bats`)

1. Update `_assert_query_contract` for the Firing Alerts panel: expr contains `ALERTS{alertstate="firing"`,
   `Watchdog|InfoInhibitor` and `or vector(0)`; contains neither `grafana_alerting_alerts` nor
   `grafana_alerting_result_total`; `noValue == "0"`; title is `Firing Alerts (Prometheus)`; the red threshold
   step's value is `1`. Select the panel by `id == 6`, not by title. Keep the Request Rate checks unchanged.
2. The existing Firing Alerts / Request Rate byte-identity test stays green.
3. Mutations in the snapshot style, each red: put `grafana_alerting_alerts{state="alerting"}` back as the expr;
   remove the `alertname!~` exclusion. Keep the existing `grafana_alerting_result_total` mutation working (adjust its
   setup if it depended on the old expr).

### Rules

- `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` green; `yq` parses both files; embedded JSON passes `jq -e .`.
- Update `docs/guides/grafana-dashboards.md` only if it describes the Overview's Firing Alerts panel; if so, one
  sentence to match.
- No cluster, network or git commits. Leave changes uncommitted. Do not touch `CHANGELOG.md` or memory-bank.
- Update this section's Status to FIXED (pending sync).
