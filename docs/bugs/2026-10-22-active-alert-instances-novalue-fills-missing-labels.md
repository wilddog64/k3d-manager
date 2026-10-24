# Bug: Active Alert Instances shows "No firing instances…" in cells of a firing alert

**Filed:** 2026-10-22 (Claude, from the operator's Inspect → Data screenshot)
**Status:** LIVE-VERIFIED (promoted 2026-10-24; the live check below already passed) — was VERIFIED — `ad4c91dd` (Luna; Claude review: N1 red on pre-fix, PromQL unchanged, bats green); live E2 2026-10-22 17:49 PDT: hub app k3d-cluster-grafana-dashboards Synced at a1e2578f, operator Inspect → Data shows "—" in the TargetDown (acg) row app and group cells
**Fix commit:** `ad4c91dd`
**Priority:** P3 — misleading cell text; the row, count and timestamps are correct
**Severity:** low
**Approval:** approved — operator, 2026-10-22: "go ahead" to dispatch to Luna after bug-tally-implemented-deferred
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Component:** Grafana Health & Firing Alerts, panel "Active Alert Instances"
**Related:** `docs/bugs/2026-10-21-firing-alerts-dashboard-missing-start-time-and-age.md`

## Symptom

The firing `TargetDown` (cluster `acg`) row shows `No firing instances with active-state timestamps`
in its `app` and `group` cells. That alert has no `app` or `group` label, so the cells are empty.

## Root cause

The panel sets `fieldConfig.defaults.noValue` to `No firing instances with active-state timestamps`.
A field-level `noValue` applies to every empty cell, not only to a panel with no rows, so a missing
label on a real alert is rendered as a message saying nothing is firing.

## Fix

- **F1.** In both dashboard copies, set `fieldConfig.defaults.noValue` to `—` so an empty cell shows a
  dash.
- **F2.** Keep the empty-panel message by moving it to the panel description (one added sentence:
  "An empty table means no firing instance has an active-state timestamp.").
  Do not change the PromQL `expr`.
- **F3.** Add a bats assertion to `scripts/tests/plugins/grafana_dashboard_appsets.bats` that the
  panel's `fieldConfig.defaults.noValue` in both files does not contain `No firing`.
- **F4.** `CHANGELOG.md` entry.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml`
- `scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml`
- `scripts/tests/plugins/grafana_dashboard_appsets.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: An empty label cell on a firing row in Active Alert Instances renders as a dash, in both dashboard files.
  - id: M2
    text: The panel's PromQL expressions are byte-identical to the pre-fix files.
must_not:
  - id: N1
    text: The panel's fieldConfig.defaults.noValue must not contain "No firing" (red on the pre-fix code).
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1]
    text: bats scripts/tests/plugins/grafana_dashboard_appsets.bats green; the new test red against the pre-fix files; diff of the panel targets empty.
  - id: E2
    kind: live
    proves: [M1]
    text: After ArgoCD syncs, the operator's Inspect → Data on Active Alert Instances shows "—" in the TargetDown row's app and group cells.
interface:
  - Panel "Active Alert Instances" in scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml (key fieldConfig.defaults.noValue)
  - Same panel in scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml
```

## Definition of Done

- [ ] F1–F4 on `k3d-manager-v1.43.5`; only the Files above change.
- [ ] N1 shown red against the pre-fix code.
- [ ] Commit: `fix(grafana): show a dash, not "No firing instances", for empty alert label cells`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or use `--no-verify`.
- Do NOT edit the panel PromQL.

**Live evidence:** 2026-10-22 · run grafana-inspect-data-targetdown-row · env hub-grafana · scenario empty-label-cells-show-dash · commit a1e2578f · proves E2
