# Bug: the Undeclared plan overlaps tile sits at the bottom of the bug dashboard with no thresholds, so a nonzero count is easy to miss

**Status:** OPEN — not dispatched
**Priority:** P3
**Severity:** low. The count is correct; it reads 0 today. A nonzero count, which warns that two plans in a release could collide or land in the wrong order, would go unnoticed.
**Approval:** operator, 2026-11-06: "dispatch them in a batch base on dependencies or priority"
**Filed:** 2026-11-06
**Detected by:** Operator (dashboard screenshot, 2026-11-06)
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`, panel id 108
**Branch:** `k3d-manager-v1.43.14`
**Related:** `docs/plans/v1.43.8-plans-table-dispatch-waves-and-file-overlaps.md` (W3 introduced the tile)

## Observed failure

Read from the dashboard source on 2026-11-06:

- Panel 108 has `gridPos` `{x: 0, y: 70, w: 6, h: 4}`, the last row on the dashboard, below the bug tiles, the Bugs table and both trend panels.
- Its `fieldConfig` is null. The count takes Grafana's default colour at any value, so a nonzero count does not change colour.
- Plan W3 asked for "a small stat beside the Plans table so a nonzero count is visible without scrolling". The tile is not beside that table: Plans is at `y: 27`.
- Its neighbours `Status unknown` (105) and `Status lags dispatch` (106) do carry thresholds.

The operator suggested the Open P0 row. That row counts bugs and this tile counts plans, so it belongs with the plan tiles.

## Fix

In panel 108 of the dashboard, with no change to its query:

1. Move the tile into the Release plans row (`y: 6`, height 4), after `Status lags dispatch`.
2. Narrow the six existing tiles so all seven fill width 24 with no overlap. Keep the row's other tiles in their current order.
3. Add thresholds: green at 0, red at 1 or more.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "The Undeclared plan overlaps tile has the same y and height as Plans in release, and is the rightmost tile in that row."
  - id: M2
    text: "The seven tiles in the Release plans row together span x 0 to 24 with no gaps or overlaps, and no panel on the dashboard overlaps another."
  - id: M3
    text: "The tile's thresholds render green at 0 and red at 1 or more (paired positive control for N3)."
must_not:
  - id: N1
    text: "The tile must not remain below the Plans table or on the bug-count row."
  - id: N2
    text: "The tile's title, id and PromQL expression must not change."
  - id: N3
    text: "A count of 0 must not render red."
evidence:
  - {id: E1, proves: [M1, M2, N1, N2], kind: offline, text: "BATS parses the dashboard JSON and asserts gridPos of all seven tiles, no overlap across all panels, and the expression unchanged against the pre-fix commit. M1 and N1 shown red on the pre-fix commit."}
  - {id: E2, proves: [M3, N3], kind: offline, text: "BATS asserts the threshold steps in fieldConfig.defaults; red on the pre-fix commit, where fieldConfig is null."}
  - {id: E3, proves: [M1, M3], kind: live, text: "After hub-grafana-dashboards syncs from the release branch, Claude reads the dashboard through the Grafana API and the operator confirms the tile by eye."}
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml: the k3dm-bugs.json panels list, panel id 108, title Undeclared plan overlaps"
  - "Row tiles by title: Plans in release, Not yet implemented, Implemented, unverified, Live-verified, Status unknown, Status lags dispatch"
```

## Notes for the fixer

- This dashboard is synced by the Argo CD app `hub-grafana-dashboards` from the release branch, not by `make platform-ops`.
- `grafana_dashboard_bugs.bats:48` already checks panel overlap, and `:351` checks the forecast row sits below the plan tiles. Both must stay green.

## Not filed here

The empty "Open by priority, last 30 days (from git)" panel in the same screenshot is not a new bug yet. Its producer, `k3dm_bug_open_history`, is tracked in `docs/plans/v1.43.14-bug-open-history-from-git.md` with live E4 pending `make platform-ops`, and the M5 was still at `e94fbaac` when the screenshot was checked. If the panel is still empty after `make platform-ops`, file it then.
