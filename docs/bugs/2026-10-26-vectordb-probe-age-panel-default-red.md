# VectorDB probe-age panel turns red while the daily probe is fresh

**Status:** OPEN — Grafana panel color is misleading
**Priority:** P3
**Date:** 2026-10-26
**Branch:** `k3d-manager-v1.43.9`
**Approval:** explicit 2026-10-26 (operator: “also investigate this”)
**Related:** `docs/plans/v1.43.9-vectordb-retrieval-quality-probe.md`; `docs/guides/grafana-dashboards/k3dm-vectordb.md`

## Observed behavior

The *Time since last retrieval probe* stat displayed `5.32 mins` on a red background, while the
retrieval metrics were present. This panel reports elapsed seconds since the last successful
probe. The probe is intentionally run at most once per day (`bin/k3dm-hermes:_maybe_probe_retrieval`),
and the stale-probe alert only fires when its age exceeds 48 hours for 30 minutes.

## Root cause

Panel 23 in `scripts/etc/argocd/platform-ops/grafana-dashboard-vectordb.yaml` sets unit `s` and
`colorMode: background` but does not define thresholds. Grafana therefore uses its default absolute
threshold: base green, red at 80. At 5.32 minutes the raw value is about 319 seconds, so Grafana
colors an expected fresh daily probe red.

## Evidence

Panel configuration excerpt:

```json
{
  "id": 23,
  "title": "Time since last retrieval probe",
  "fieldConfig": { "defaults": { "unit": "s" } },
  "options": { "colorMode": "background" },
  "expr": "time() - k3dm_vectordb_retrieval_probe_last_success_timestamp_seconds"
}
```

The screenshot shows `5.32 mins` in red. Grafana's documented default threshold is base green and
80 = red. The configured alert is `time() - k3dm_vectordb_retrieval_probe_last_success_timestamp_seconds > 172800`
for `30m`; the guide calls the probe daily.

## Recommended fix

Set explicit thresholds for the age stat so normal daily operation is green, aging data is amber,
and data beyond the 48-hour stale-alert boundary is red. Add a dashboard regression assertion that
pins the query, unit, and threshold values. Keep the alert rule and daily probe cadence unchanged.

No Grafana configuration was changed or deployed during this investigation.
