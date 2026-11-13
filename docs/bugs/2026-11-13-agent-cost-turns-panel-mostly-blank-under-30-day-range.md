# Agent Cost "Turns" panel is mostly blank: 30-day range over a 3-day Prometheus history

**Status:** OPEN — captured 2026-11-13
**Priority:** P3 (Claude proposal: display only, numbers are correct)
**Classified:** pending (Argon, from this doc alone)
**Waiting on:** dispatch — since 2026-11-13 (batch with the next `grafana-dashboard-agent-cost.yaml` change)
**Introduced by:** pre-existing (panel 112 added without a `timeFrom`)
**Should have been caught by:** review
**Prior art:** `docs/bugs/2026-11-12-agent-cost-dashboard-misses-fable-5-2.md` (exact-topic read) — same dashboard, different defect; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing), exact-slug glob found no match
**Approval:** operator, 2026-11-13: "sounds good, go ahead to do what you suggest"

## Symptom

On the Agent Cost dashboard, panel 112 "Turns" (`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml`, `"id": 112`) draws three lines only in the last ~3 days; the left ~90% of the panel is empty. The operator's screenshot of 2026-11-13 shows data only from 11/10 onward under the dashboard default `now-30d`.

## Cause

- The three series (`k3dm_claude_turns_per_active_day`, and `k3dm_claude_context_turns / k3dm_claude_verified_specs`) are gauges that `bin/k3dm-dispatch-metrics` (:2315) recomputes for each `$window` on every export. The **window** is complete; only the **history** of the gauge is short.
- Hub Prometheus keeps 3 days (`retention: 3d`). The dashboard range is `now-30d` and panel 112 has no `timeFrom`, so 27 of 30 days are blank. A blank there means no stored sample, not zero, and readers can take it for an outage.
- The panel description does not say that each line is a rolling average over `$window`, so step changes (a day entering or leaving the window) read like activity changes.

## Fix

Follow the precedent in `grafana-dashboard-bugs.yaml:1603`:

1. Panel 112: add `"timeFrom": "3d"`.
2. Extend its description: each line is an average over the selected `$window`, recomputed at every export; the time axis is the 3-day hub retention (`retention: 3d`), so the panel always shows the last 3 days whatever range the dashboard is set to.

No query, gridPos or other panel changes.

## Acceptance

```yaml
must:
  - id: M1
    text: panel 112 has timeFrom "3d"
  - id: M2
    text: panel 112 description names the 3-day retention and says each line is an average over $window
must_not:
  - id: N1
    text: panel 112 targets (expr, legendFormat) or gridPos change
  - id: N2
    text: any other panel in grafana-dashboard-agent-cost.yaml changes
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    intent: The Turns panel fills its width with the 3 days of data that exist, and its description explains how to read the lines.
    command: bats scripts/tests/plugins/agent_dispatch_dashboard.bats (new test; red on pre-fix dashboard)
  - id: E2
    proves: [M1]
    kind: live
    intent: After a promote, the operator sees the Turns panel span 3 days edge to edge under the default 30-day range.
interface: scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml panel 112
```

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-cost.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`

## Open question (not part of the fix)

All three lines jump at about 2026-11-11 06:00Z (green from under 100 to about 1,000). Not yet explained: it may be when these series started exporting in their current form, or a `$window` change. Check the exporter history before reading anything into it.
