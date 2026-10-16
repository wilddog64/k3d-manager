# Bug: offline test failure visible in Grafana but no OfflineSuiteFailing email after alert window

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.44.0` (triage 2026-10-15, operator-approved placement)
**Status:** OPEN — needs live Prometheus and Alertmanager verification; root cause not established
**Priority:** P2 — failed offline test is visible on dashboard but expected warning notification is unconfirmed/missing; workaround is manual dashboard review
**Severity:** medium
**Origin:** operator screenshot 2026-10-15 ~05:35 PDT, K3DM Tests dashboard; operator reported no corresponding email

## Symptom

Grafana on 2026-10-15 ~05:35 PDT displayed:
- Last run: `2026-10-15 04:39:42`
- Failed cases: `1`
- Failing case: BATS #1006 `5 prune keeps recent exports and the last passing export`, target `test-all`
- Latest run classification: `failed_untriaged`
- Time since last successful run: `3.40 days`
- No new passing run is visible in the same screenshot.

Approximately 56 minutes had elapsed since the last failed run. The operator received other warning emails (`E2EVerificationFailing` and `DeploymentMetricsStale`) but did not see `OfflineSuiteFailing`; a connected Gmail search for `OfflineSuiteFailing` dated October 15 found no matching message at filing time. Absence of a matching inbox message alone does not establish where delivery failed.

## Expected behavior

`scripts/etc/prometheus/rules-acg/k3dm-tests.yaml` defines:

```yaml
- alert: OfflineSuiteFailing
  expr: k3dm_test_cases_failed > 0
  for: 30m
  labels:
    group: k3dm-tests
    severity: warning
```

`scripts/etc/prometheus/alertmanager.yaml.tmpl` routes `severity=warning` to `platform-warning` (Gmail email), with `group_wait: 10m`. If the **same monitored series remained >0 continuously**, the rule was selected and Alertmanager received it, expect delivery around 40+ minutes after first pending evaluation, subject to evaluation/scrape cadence and grouping.

## Known vs unknown

- **Confirmed in source:** BATS publisher emits `k3dm_test_cases_failed{target="test-all"}`; Grafana reads that series; PrometheusRule defines failure and Alertmanager template defines warning email routing.
- **Not yet verified live:** deployed `k3dm-tests` PrometheusRule/selection by Prometheus, per-instance metric visibility on the *evaluating* Prometheus, `ALERTS{alertname="OfflineSuiteFailing",alertstate=...}` state, active Alertmanager configuration, silence/inhibition, or notifier outcome.
- The test dashboard's Prometheus datasource and alert evaluator may differ in deployment/cluster. A dashboard displaying the series is **not sufficient proof** its alerting Prometheus evaluates it.
- A screenshot of a historical/retained failed run is not sufficient to infer that the alert was continuously pending for 30 minutes. Avoid declaring an email route bug until this is checked.

## Diagnostic checklist (read-only first)

1. On `ubuntu-hostinger`, inspect `kubectl --context ubuntu-hostinger -n monitoring get prometheusrule k3dm-tests -o yaml`. Verify rule exact expression, labels, and deployed age.
2. Inspect Prometheus Operator `ruleSelector`/namespace selectors and active `/api/v1/rules` on the Prometheus **that evaluates** the rule. Confirm the rule appears and has no errors.
3. Query that Prometheus for `k3dm_test_cases_failed{target="test-all"}`, series labels and samples across 04:39–05:40 PDT, including staleness/absence. Compare the Grafana datasource's result.
4. Query `ALERTS{alertname="OfflineSuiteFailing"}` and rule state `inactive|pending|firing`, and examine pending/firing transition timestamps. If missing, trace scrape target, Pushgateway publication, selector, or rule evaluation.
5. If firing, check Alertmanager's `/api/v2/alerts`, route tree, silence and inhibition, receiver, SMTP notification logs and Gmail delivery. Verify actual deployed config rather than source template alone.
6. Compare the timing with Prometheus evaluation and Alertmanager `for: 30m`, `group_wait: 10m`, and any preexisting notification group.
7. Document the root cause and add regression/contract coverage for the **end-to-end alert path**, including a controlled failed sample and warning route verification; avoid real emails or destructive mutation in automated tests.
8. Do not simply reduce the 30-minute threshold to force a notification. Preserve debouncing unless the operator separately approves new alert semantics.

## Acceptance criteria

- A continuously failing published offline suite produces `OfflineSuiteFailing` firing state after the configured duration and the expected warning notification in the configured route.
- Short-lived failures that recover within 30 minutes remain non-notifying.
- Dashboard and alert evaluation use the intended same authoritative metric/source, or document deliberate differences clearly.
- Missing rule, datasource mismatch, missing metric, or Alertmanager delivery failure gives actionable diagnostics rather than silently dropping alerts.
- Tests and staging/live verification recorded; no credentials leaked.

## Related

- `docs/bugs/2026-10-15-test-all-hub-data-prune-aging-fixtures.md` (actual BATS #1006 failure)
- `docs/bugs/2026-10-05-nightly-test-metrics-push-failure-is-silent.md` (previous missing push concern)
