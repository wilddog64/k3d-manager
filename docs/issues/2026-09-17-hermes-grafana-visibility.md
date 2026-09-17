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
and exporter `service`). Its remaining `Namespace` field is the Prometheus
scrape namespace (`platform-ops` for this exporter); Hermes does not currently
publish an application target namespace, so the dashboard does not mislabel
that field as a target namespace.

The live snapshot also contained a legacy `updated_at: "now"` value from the
initial manual publication. That parsed as Unix epoch zero and produced a
misleading `56.7 years` age. The exporter now suppresses the age metric when
the timestamp is invalid, so Grafana shows no data instead of a false age until
Hermes publishes a valid ISO-8601 timestamp.
