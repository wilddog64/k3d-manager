# Hermes findings visibility design

**Date:** 2026-09-17
**Status:** Implemented; live dashboard deployed 2026-09-17

## Finding

Hermes was polling successfully, but its findings were visible only in the
local `~/Library/Logs/k3dm-hermes.log` and `~/.k3dm/hermes/state.json`. A
persistent finding could therefore remain open without a durable Grafana view.

## Scope

Publish a redacted Hermes status snapshot as a labeled `platform-ops`
ConfigMap. The existing vulnerability exporter reads that snapshot and emits
bounded Prometheus gauges. A dedicated Grafana dashboard displays current
sensor states, active incident state, finding age, and the detailed checks.
No credentials, bearer tokens, or raw local log lines are published.

The v1.34.0 milestone already contains its five permitted plan documents, so
this issue record is the design and acceptance record rather than a sixth plan.

## Acceptance

- Hermes publishes the latest status record when the scheduled status sensor runs.
- The publication also accepts the regular Hermes sensor records, so visibility
  is useful even while the optional `status_checks` interval is disabled.
- Prometheus exposes sensor status, incident state, last-poll age, and check details.
- Grafana has a `Hermes Status` dashboard with current findings and history-friendly panels.
- Existing Hermes and exporter tests remain green.

The first live publication exposed a label-application gap; the publisher now
labels the ConfigMap explicitly after applying it, and the existing snapshot
was relabeled during rollout.

## 2026-09-17 Grafana panel rendering follow-up

The first dashboard view showed Prometheus labels such as `endpoint`, `instance`,
`pod`, and `job` inside the top stat panels. Those panels were receiving a
multi-series result (or falling back to Grafana's series display), so Grafana
rendered the label set instead of a clean scalar value. The stat queries now
aggregate to one series, use instant evaluation, and clear the legend format.

The findings table now hides scrape metadata (`container`, `endpoint`, `pod`,
and exporter `service`). It displays a `Target namespace` scope derived from
the sensor (`platform-ops`, `cicd`, `external`, `node`, `hub-control-plane`, or
`github-actions`) instead of the exporter scrape namespace.

The live snapshot also contained a legacy `updated_at: "now"` value from the
initial manual publication. That parsed as Unix epoch zero and produced a
misleading `56.7 years` age. The exporter now suppresses the age metric when
the timestamp is invalid, so Grafana shows no data instead of a false age until
Hermes publishes a valid ISO-8601 timestamp.

The Hermes findings table keeps `Sensor` first and now orders columns as
`Finding`, `Status`, and `Target namespace`. The E2E failure-cause and top-spec
bar charts use instant aggregate queries so each category is rendered once;
range-query samples had previously produced dense overlapping bars and unreadable
timestamp labels.

The E2E table column order was also aligned for readability: Failure groups
now use `Run ID`, `Runner`, `Tier`, `Target`, `Service`, `Failure kind`; Failure
details use `Run ID`, `Runner`, `Tier`, `Service`, `Spec file`, `Test`, `Error`,
`Status`.

The Recent runs table now uses the triage order `Run ID`, `Runner`, `Tier`,
`Runner commit`, `Services under test`, `Failed tests`, `Total tests`, `Test
suite`, and `Run result`.

The Recent runs boolean has been replaced with `Failure ratio (failed/total)`;
for example, `33/102` means 33 failed tests out of 102 total.

The table filters out pre-ratio metric series left by the exporter rollout, so
legacy rows cannot appear with an empty ratio. New values include both forms,
for example `33/102 (32.4%)`.

The boolean Recent runs field is labeled `E2E run passed` so `false` clearly
means that one or more tests failed in that E2E run.

The final refinement places `Runner commit` before `Tier` and `Test suite`
before `Services under test`.

## 2026-09-17 Grafana responsiveness follow-up

The E2E dashboard was refreshing every minute over seven days while rendering
unbounded run, failure-group, and failure-detail series. That combination can
stall the Grafana browser even when Prometheus is healthy. The dashboard now
refreshes every five minutes over 24 hours, caps table queries at 100/200/300
rows, and lets the trend panel choose point density automatically.

Live checks found Grafana and Prometheus healthy, with 66 failure-detail and 20
failure-group series. Because the intermittent stall was browser-side rendering
during automatic refresh, E2E refresh is now manual (`off`) and failure details
are capped at 100 rows; use Grafana's refresh button after a new run.
