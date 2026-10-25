# Bug: Agent Activity titles and bar labels are truncated, and the Claude row starts with a gap

**Status:** FIXED — `979dbdb7`. offline-verified: dashboard BATS 17/17 (new layout test red on the pre-fix file), pytest 81 passed, validate-manifests 83 valid. Live check pending the hub sync.
**Fix commit:** 979dbdb7
**Priority:** P3
**Severity:** low — the numbers are correct; the operator cannot read which panel or bar they belong to
**Release:** v1.43.6 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-24, by Claude, from the operator's screenshot 221 ("can we make table caption readaable")
**Approval:** explicit 2026-10-24 (the request above). Not critical (one dashboard ConfigMap), fixed by Claude.
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
**Related:** `docs/plans/v1.43.6-agent-dashboards-split.md` (the split left row 33's panels at their old `x` after 34 moved out), `docs/bugs/2026-10-19-bug-dashboard-verification-tile-labels-clipped.md` (same class on Bug Tracking)

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/guides/grafana-dashboards.md`

## Problem

On k3dm Agent Activity:

1. The five `Claude context and compaction` panels (35–39) are `w: 4` starting at `x: 4`. Panel 34
   used to sit at `x: 0`; the split moved it to Agent Cost and left a 4-column hole. At `w: 4` the
   titles cut off: `Compactions per ve…`, `Compactions by trig…`, `Re-read share after …`,
   `Auto-compact thres…`.
2. The bar gauges (36, 38, 54, 55, 56, 69, 70) use the default orientation. Grafana picks vertical
   bars when the panel is wider than tall, which prints each series name under a narrow bar:
   `k3d-…`, `othe…`, `shop…`, `missing-con…`, `resumption-…`.

## Fix

1. Row 33: panels 35, 37, 39 at `y: 1`, `w: 8`, `x` 0/8/16; panels 36 and 38 at `y: 7`, `w: 12`,
   `x` 0/12. Every panel below row 33 moves down by 6. No other `gridPos` changes.
2. Every bar gauge on Agent Activity gets `options.orientation: "horizontal"` and
   `options.namePlacement: "left"`, so each name gets the panel's width instead of one bar's.
   No query, unit, threshold or colour changes.
3. The pre-split fixture test allows exactly those two `options` keys to differ on bar gauges.
4. Guide: one sentence in the Agent Activity section that bar names read left of each bar.

## Acceptance

```yaml
must:
  - id: M1
    text: Row 33 has no horizontal gap; its stats are at least 8 columns wide and its bar gauges 12.
  - id: M2
    text: Every Agent Activity bar gauge is horizontal with names on the left.
must_not:
  - id: N1
    text: No query, fieldConfig or other option may change (the fixture test still guards them).
  - id: N2
    text: No panel may overlap or leave a vertical gap.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2]
    text: agent_dispatch_dashboard.bats green; the new layout test red on the pre-fix file; make validate-manifests passes.
  - id: E2
    kind: live
    proves: [M1, M2]
    text: After the hub syncs, the operator's screenshot shows full titles in the Claude row and full repo, mode and kind names beside each bar.
interface:
  - Grafana /d/k3dm-agent-activity
```

## Recurrence (2026-10-25)

Operator screenshots 261 and 262: names still truncated after `979dbdb7` (`shopping-cart-fro…`,
`k3d-manager inter…`, `intera…`, `missing-conte…`, `resumption-fai…`). Left placement shares a quarter-width
panel's width between the name and the bar, and Grafana's auto-sized text grows to fill tall rows.
Fix: every bar gauge gets fixed `text` sizes and `minVizHeight: 8`; gauges narrower than 12 columns
(54, 55, 56, 69, 70) put names on top, where they get the full width; 36 and 38 stay left at 14/24 px.
Test 18 now requires top placement below 12 columns and fixed sizes, red on the previous file.

Second pass (2026-10-25, operator screenshot 264): names now read in full, but Untracked by repo's six
rows cropped their values at 6 units high. Rows holding a narrow gauge (54–57, 66–69, 70–71) are now 8
high, panels below shift down; test 18 requires h ≥ 8 for top-placed gauges, red on the previous file.
