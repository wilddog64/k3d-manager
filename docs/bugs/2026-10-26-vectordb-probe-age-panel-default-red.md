# VectorDB probe-age panel turns red while the daily probe is fresh

**Status:** OPEN — Grafana panel color is misleading
**Priority:** P3
**Branch:** `k3d-manager-v1.43.9`
**Dispatch:** go — operator batch 2026-10-27; model `gpt-6-luna`; task `vectordb-probe-age-thresholds-luna`
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

## Additional operator screenshot

The operator's 2026-10-27 UTC VectorDB Health screenshot again shows the daily
retrieval probe age in red, this time at 3.25 hours, while ingestion reports
success and VectorDB is healthy. This supports the existing display-threshold
finding; it does not reopen the independently verified Hermes SSH fix. No age
threshold implementation was included in that SSH fix or the Plans P3. This
bug remains OPEN. Evidence: `docs/issues/2026-10-27-live-verification-hermes-and-plans.md`.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-vectordb.yaml`
- `scripts/tests/plugins/vectordb_rules.bats`
- `docs/guides/grafana-dashboards/k3dm-vectordb.md`
- `CHANGELOG.md`

## Acceptance

- M1: Panel 23 has absolute thresholds: base green, amber at 86400 seconds,
  red at 172800 seconds. A 3.25-hour daily probe remains green.
- M2: Preserve its query, seconds unit, last-success meaning and daily cadence.
  Preserve the 48-hour/30-minute alert rule unchanged.
- M3: Pin thresholds/boundaries and unchanged query/unit/alert behavior in the
  focused existing BATS suite; new tests fail on the original dashboard.
- N1: No forced retrieval/API call, no index mutation, and no live rollout.
- E1 offline: vectordb_rules BATS, dashboard JSON validation, diff check.
- E2 live: after approved rollout, operator refreshes VectorDB Health and shows
  the 3.25h/fresh probe age green. Coordinator checks provisioned thresholds.

## Dispatch rules — operator batch 2026-10-27

The operator explicitly selected this existing bug for implementation by
GPT-6-Luna, independent offline review, and operator live verification one fix
at a time. This is implementation authorization; no worker may deploy, restart
services, contact live clusters/registries/providers, create accounts, rotate
credentials, or run live tests. Work only in the isolated task worktree and the
Files allowlist. Do not edit this spec, memory-bank, or source plan statuses.
Do not stage, commit, push, or create PRs. Preserve DO NOT REMOVE comments.
Add meaningful regressions and show them red on the original behavior before
reporting green. Run focused tests, syntax/lint, and git diff --check; report
actual outputs and any unmet acceptance honestly. Use <=8 if blocks in new or
refactored functions. Report legacy budget conflicts instead of raising limits.
The coordinator will run audit/lint on staged changes before committing.
