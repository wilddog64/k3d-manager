# Bug: the Alertmanager delivery dashboard mixes actionable, security and synthetic alerts in one count

**Filed:** 2026-10-09
**Branch:** `k3d-manager-v1.43.0`
**Status:** FIXED `42c4ac9a` 2026-10-09 (Codex via parallel worktree dispatch; Claude restored the routing paragraph, ran every new query against hub Prometheus, mutation red). Live in Grafana after the next `hub-grafana-dashboards` sync.
**Priority:** P3 — the dashboard is correct but misleading; the real signal is hidden
**Severity:** low
**Origin:** operator, 2026-10-09, from a ChatGPT review of the dashboard. Claude's evaluation kept
A, B and 4 and part of 5; the response-handling funnel (C, 2, 3) went into
`docs/plans/v1.45.0-alert-intake-draft-bugs.md`, and ownership grouping (1) was rejected (one operator).

## Symptom

`k3dm Alertmanager Delivery` (`k3dm-alertmanager-delivery`) showed **41 warning, 1 critical** on the
hub on 2026-10-09. What was actually firing:

| Count | Severity | Alert | What it is |
|---|---|---|---|
| 39 | warning | `TrivyCriticalVulnerabilityDetected` | one per image, all `tier="upstream"` |
| 1 | warning | `TargetDown` | `job="federate-acg"`, the ACG sandbox is down |
| 1 | warning | `HostDiskSpaceLow` | `job="k3dm-disk-smstest"`, a deliberate test alert |
| 1 | critical | `HostDiskSpaceCritical` | `job="k3dm-disk-smstest"`, the same test |
| 1 | info | `CPUThrottlingHigh` | `argocd-repo-server` in `cicd` |

The one actionable warning is lost among 39 vulnerability findings. The one critical is a test. The
single **Firing alerts** table has the same problem: a reader has to know which rows to ignore.

The dashboard also does not show:
- which alerts fire most often;
- whether the alerting pipeline itself is healthy. The rules exist in kube-prometheus-stack, but nothing on
  this dashboard surfaces them.

## Cause

The severity stat (panel 4) and the table (panel 9) both read every firing `ALERTS` series except
`Watchdog` and `InfoInhibitor`. Nothing separates the three kinds of alert.

## Fix

All changes go in the dashboard JSON inside
`scripts/etc/argocd/platform-ops/grafana-dashboard-alertmanager-delivery.yaml`. Keep the existing
datasource (`{"type": "prometheus", "uid": "prometheus"}`) on every new panel. Keep the panel `id`s
that already exist.

Definitions used below:
- `META = alertname!~"Watchdog|InfoInhibitor"`
- **security:** `alertname=~"Trivy.*"`
- **synthetic:** `job=~".*smstest.*"`
- **actionable:** everything firing that is neither of those:
  `ALERTS{alertstate="firing",alertname!~"Watchdog|InfoInhibitor|Trivy.*",job!~".*smstest.*"}`
  (a series with no `job` label matches `job!~…`, which is what we want).

### 1. Panel 4: count actionable alerts only

- Title: `Actionable alerts by severity`.
- Query: `count by (severity) (ALERTS{alertstate="firing",alertname!~"Watchdog|InfoInhibitor|Trivy.*",job!~".*smstest.*"})`.
- Description: keep the routing sentence, and add that Trivy findings and synthetic test alerts are
  counted in their own panels below.
- `gridPos`: `w` 5 (was 8). `x` stays 16.

### 2. New panel 13 (stat): `Alerting pipeline`

- `gridPos` `{"h": 6, "w": 3, "x": 21, "y": 1}`.
- Query:
  `count(ALERTS{alertstate="firing",alertname=~"Alertmanager.*|PrometheusNotConnectedToAlertmanagers|PrometheusErrorSendingAlerts.*|PrometheusNotificationQueueRunningFull|PrometheusRuleFailures|PrometheusMissingRuleEvaluations"}) or vector(0)`, instant.
- Thresholds: green at 0, red at 1. `colorMode` `background`. `noValue` `"0"`.
- Description: these are the kube-prometheus-stack rules that watch the alerting system itself
  (send failures, Prometheus not connected to Alertmanager, rule evaluation falling behind). 0 means
  none firing. Look at the alert names in Prometheus when this is red.

### 3. Panel 9: `Actionable alerts`

- Title `Actionable alerts`, query the **actionable** selector above. Everything else about the panel stays the same
  (table format, organize transformation, severity sort, count footer).
- `gridPos` `{"h": 8, "w": 24, "x": 0, "y": 7}`.
- Description: alerts firing now, excluding Trivy findings and synthetic tests.

### 4. New panel 10 (table): `Security findings by image`

- `gridPos` `{"h": 9, "w": 12, "x": 0, "y": 15}`.
- Query: `count by (tier, image_repository, alertname) (ALERTS{alertstate="firing",alertname=~"Trivy.*"})`,
  `format` `table`, instant.
- Organize: hide `Time`; rename `Value` to `findings`; order `tier`, `image_repository`,
  `alertname`, `findings`. Sort by `tier` ascending so our own images (`tier` not `upstream`) list
  before upstream ones.
- Description: one row per image. `tier="upstream"` is a third-party image we only consume; anything else is
  ours and has a remediation path through the CVE loop. This is a backlog, not a page.

### 5. New panel 11 (table): `Synthetic / test alerts`

- `gridPos` `{"h": 9, "w": 12, "x": 12, "y": 15}`.
- Query: `ALERTS{alertstate="firing",alertname!~"Watchdog|InfoInhibitor",job=~".*smstest.*"}`, table, instant,
  with the same organize transformation as panel 9.
- Description: deliberate test alerts (for example the `k3dm-disk-smstest` Pushgateway job used to
  check SMS delivery). They route like real alerts, so they do send texts. Delete the test job when the
  test is over.

### 6. New panel 12 (table): `Noisiest alerts (3d)`

- `gridPos` `{"h": 8, "w": 24, "x": 0, "y": 24}`.
- Two instant queries, `format` `table`, joined with a `merge` transformation on `alertname`:
  - A: `sum by (alertname) (count_over_time(ALERTS{alertstate="firing",alertname!~"Watchdog|InfoInhibitor"}[3d])) / 60`,
    renamed `firing series-hours`.
  - B: `sum by (alertname) (changes(ALERTS_FOR_STATE{alertname!~"Watchdog|InfoInhibitor"}[3d]))`,
    renamed `trips (pending or firing)`.
- Sort by `firing series-hours` descending.
- Description:
  - Why 3d: hub Prometheus keeps 3 days (`retention: 3d`).
  - `firing series-hours` is time spent firing, summed over series. It assumes the 60s rule
    evaluation interval (`evaluationInterval: 60s`).
  - `trips` counts how many times an alert started pending, including ones that cleared before
    firing. A high count with no firing hours is flapping.
  - Alertmanager does not label notification counts or latency by alert name, so this panel cannot
    show "notifications per alert".

### 7. Shift the per-integration row

Panel 5 (row) `y` 18 → 32. Panels 6 and 7 `y` 19 → 33.

### 8. Guide

Rewrite the `### k3dm Alertmanager Delivery` section of `docs/guides/grafana-dashboards.md`:
- the three alert categories and their selectors;
- the pipeline-health stat;
- the noisiest-alerts table and what `trips` means;
- that the 41-warning example was 39 Trivy findings.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-alertmanager-delivery.yaml` | items 1–7 |
| `scripts/tests/plugins/alertmanager_delivery_dashboard.bats` | regression tests |
| `docs/guides/grafana-dashboards.md` | item 8 |

## Tests

Add to `scripts/tests/plugins/alertmanager_delivery_dashboard.bats`, parsing the JSON with the
existing `_dashboard_json` helper or the same Python pattern:
1. Panel 4 and panel 9 queries contain `Trivy.*` and `smstest` exclusions; no panel other than
   10, 11, 12 and 13 reads `ALERTS` without excluding both.
2. Panel 10 queries `alertname=~"Trivy.*"`. Panel 11 queries `job=~".*smstest.*"`.
3. Panel 13's query names `AlertmanagerFailedToSendAlerts`'s prefix (`Alertmanager.*`) and
   `PrometheusNotConnectedToAlertmanagers`, and ends in `or vector(0)`.
4. Panel 12 has both queries and its range is `[3d]`. It must match the retention in
   `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`: read `retention:` there
   and assert the range equals it.
5. No two panels overlap: for every pair of non-row panels, their `gridPos` rectangles do not
   intersect.
6. Panel ids are unique.

The existing tests must stay green, including "every panel uses the hub Prometheus datasource".

Mutation checks. Paste the red output for each:
- Remove `|Trivy.*` from panel 9's query. Test 1 must fail.
- Change panel 12's range to `[7d]`. Test 4 must fail.
- Set panel 11's `y` to 7. Test 5 must fail.

## Rules

- `bats scripts/tests/plugins/alertmanager_delivery_dashboard.bats`: all green. Paste the output.
- The dashboard JSON stays valid: `_dashboard_json` succeeds.
- `make check-doc-links` is green on the staged `.md` files.
- Do not commit. `.git` is read-only in the sandbox.

## After landing (not Codex's job)

The ConfigMap is synced to the hub by ArgoCD app `hub-grafana-dashboards`, so it goes live with
the next sync of `k3d-manager-v1.43.0`. Claude checks every new panel in Grafana. On
2026-10-09 the actionable panel should show `TargetDown` (`federate-acg`) and `CPUThrottlingHigh`
only, and the pipeline stat should be 0.
