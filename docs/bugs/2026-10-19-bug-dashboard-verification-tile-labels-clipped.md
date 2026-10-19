# Bug: Bug Tracking verification tile labels are clipped

**Status:** VERIFIED — 2026-10-19: dispatched implementation landed in `5819e236`; dashboard BATS 22/22 and `make check-doc-links` passed. Live Grafana verification is still pending.
**Priority:** P3
**Fix commit:** `5819e236`
**Branch:** `k3d-manager-v1.43.5`

## Summary

The Bug Tracking dashboard summary strip renders the `Verified` and `Live-verified`
stat tiles with narrower grid widths than the surrounding cards. Grafana truncates
the titles in the rendered dashboard (for example, `Ve...` and `Liv...`), making the
two verification counts ambiguous.

## Evidence

Operator screenshot on 2026-10-19 shows the row:

`Open P0 | Open P1 | Open P2 | Open P3 | Fixed | Ve... | Liv... | De... | Scan age`

The source dashboard currently gives panels 16 (`Verified`) and 24 (`Live-verified`)
`gridPos.w=2`, while the primary cards use wider widths. The affected dashboard is
`k3dm Bug Tracking` in `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`.

## Expected behavior

The `Verified` and `Live-verified` titles should be fully readable in the summary
strip. Rebalance the 24-column row without changing the PromQL, titles, value
semantics, or panel order.

## Acceptance criteria

- Panel 16 (`Verified`) and panel 24 (`Live-verified`) have sufficient width for
  their titles and remain adjacent.
- The summary strip remains within Grafana's 24-column grid with no overlap.
- Existing panel IDs, titles, queries, colors, and order remain unchanged.
- The dashboard test asserts the new grid positions.
- `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` passes.
- `make check-doc-links` passes.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` | Rebalance summary stat tile widths/positions |
| `scripts/tests/plugins/grafana_dashboard_bugs.bats` | Assert the updated grid layout |

## Rules

- Do not change PromQL, dashboard variables, panel IDs, or unrelated panels.
- Do not create a plan document; v1.43.5 already has five plan documents.
- Do not create a PR or run live dashboard mutations. Claude/operator handles deployment and live verification.
