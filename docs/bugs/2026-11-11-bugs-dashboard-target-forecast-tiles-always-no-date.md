# Bug Tracking: "Target forecast (earliest/latest)" tiles only say "no date — see table"

**Status:** OPEN — captured 2026-11-11 from the operator's report; not investigated (capture-first rule)
**Priority:** P2
**Classified:** P2 by gemini-4-argon-medium, 2026-11-11 ("degraded, and the Remaining releases table is the workaround"); Claude proposed P3 (cosmetic: the tiles duplicate the table). Higher stands until the operator decides.
**Waiting on:** dispatch — since 2026-11-13 (intent approval pending)
**Introduced by:** unknown (tiles from `401e4eca`, v1.43.5; when they stopped showing a date is not established)
**Should have been caught by:** unknown
**Prior art:** `docs/bugs/2026-11-07-forecast-milestones-drift-and-folded-releases.md` — read, different defect (that one
fixed the Remaining releases table going blank or overdue); `find-similar-docs` unavailable (vector store context missing)
**Approval:** operator, 2026-11-11 ("we don't need those two"); triage decision 2026-11-13: "both said no date -- see table, table is Remaining releases. this mean those two are no needed" → option 1 (remove)

## Symptom

On Bug Tracking → Release forecast, both stat tiles "Target forecast (earliest)" (panel 29) and "Target forecast
(latest)" (panel 30) show their `noValue` text, "no date — see table", which sends the reader to Remaining releases
(operator, 2026-11-11). The table already carries the low/mid/high forecast per release.

## What is known

- The tiles show the forecast for the single `"target": true` milestone in `docs/release-milestones.json`: `v1.61.0`
  (queries in `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml:2824` and `:2862`).
- No milestone in that file is `blocked` today, so the v1.43.5 design reason for no dates (target after a blocked
  milestone) does not explain it. Why the series is empty is not established.
- Since the 2026-11-08 grooming rule, only the open and next release carry numbers; a far numbered target such as
  v1.61.0 has little meaning, so the tiles may have no useful value even when fixed.

## Options for triage

1. **Remove panels 29 and 30** (operator's suggestion); the Remaining releases table is the forecast. Update the
   dashboard tests that name them (`scripts/tests/plugins/grafana_dashboard_bugs.bats`).
2. Re-point the tiles at the next release instead of a far target.
3. Investigate why the target series is empty and keep the tiles.

## Root cause of the empty tiles (2026-11-13)

Not a broken producer. Target state (panel 31) shows "blocked at v1.60.0" and the target is v1.61.0; the v1.43.5 design
gives no date to a target after a blocked milestone (`state=after_blocked`). The tiles were working as designed and can
never show a useful date while the far target sits behind a block.

## Fix (operator decision 2026-11-13: remove)

In `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (`k3dm-bugs.json`):

- Delete panel 29 "Target forecast (earliest)" (x 8, y 11) and panel 30 "Target forecast (latest)" (x 12, y 11).
- Move panel 31 "Target state" from x 16 to x 8 and widen it to w 8, so the row has no hole
  (Releases to target 0–4, Median gap 4–8, Target state 8–16). Panel ids 26, 27, 28, 31, 32 keep their ids; no other panel moves.
- No producer change: `k3dm_release_milestone_forecast_seconds` stays, because the Remaining releases table (panel 32) reads it.

In `scripts/tests/plugins/grafana_dashboard_bugs.bats`, test "release forecast panels align by version and map dates and states"
(~:52): expect 5 panels in ids 26–32 instead of 7, and check `noValue` on 28 and 31 only. Add a test that no panel titled
"Target forecast" exists and that panel 31 sits at x 8, w 8, y 11.

## Contract readers

Panel ids 29/30 and titles: grep 2026-11-13 found them only in `grafana-dashboard-bugs.yaml:2811-2886`, in
`grafana_dashboard_bugs.bats:65` (`for i in (28,29,30,31)`) and `:58` (`len(new)==7`), and in
`docs/plans/v1.43.5-release-forecast.md` (history, unchanged). No other dashboard, alert or script reads them.

## Acceptance

```yaml
must:
  M1: the Bug Tracking dashboard has no panel titled "Target forecast (earliest)" or "Target forecast (latest)"
  M2: Target state (id 31) sits at x 8, y 11, w 8, h 4 and overlaps no panel
must_not:
  N1: Releases to target (27), Median gap (28), Target state (31) or Remaining releases (32) change query, mappings or title
  N2: any other panel's id or gridPos changes
evidence:
  - {id: E1, proves: [M1, M2], kind: offline, intent: "You will see a test that finds no 'Target forecast' panel and finds Target state at x 8, width 8. It fails on today's dashboard."}
  - {id: E2, proves: [N1, N2], kind: offline, intent: "You will see a script compare every other panel with today's dashboard: same ids, queries, mappings and positions; the whole dashboard suite passes."}
  - {id: E3, proves: [M1, M2], kind: live, intent: "After a hub promote, you will see the Release forecast row show three tiles (Releases to target, Median gap, a wider Target state) above Remaining releases."}
interface:
  - "Grafana Bug Tracking dashboard, Release forecast row"
```

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` | delete panels 29, 30; move/widen 31 |
| `scripts/tests/plugins/grafana_dashboard_bugs.bats` | update the 7-panel test; add E1 |

## Worker definition of done

- Change only the files above. No network, no make target that touches the hub or a cluster. Show E1 red on today's
  dashboard, then green. For E2, diff every panel except 29, 30, 31 (and 31's gridPos) against `git show HEAD:<file>`
  and paste the empty diff. Run `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` from the repo root and paste
  command, rc and the ok/not ok count. Leave changes uncommitted.
