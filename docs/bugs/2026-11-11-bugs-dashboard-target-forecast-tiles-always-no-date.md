# Bug Tracking: "Target forecast (earliest/latest)" tiles only say "no date — see table"

**Status:** OPEN — captured 2026-11-11 from the operator's report; not investigated (capture-first rule)
**Priority:** P2
**Classified:** P2 by gemini-4-argon-medium, 2026-11-11 ("degraded, and the Remaining releases table is the workaround"); Claude proposed P3 (cosmetic: the tiles duplicate the table). Higher stands until the operator decides.
**Waiting on:** fix running — since 2026-11-13
**Introduced by:** unknown (tiles from `401e4eca`, v1.43.5; when they stopped showing a date is not established)
**Should have been caught by:** unknown
**Prior art:** `docs/bugs/2026-11-07-forecast-milestones-drift-and-folded-releases.md` — read, different defect (that one
fixed the Remaining releases table going blank or overdue); `find-similar-docs` unavailable (vector store context missing)
**Approval:** operator, 2026-11-11 ("we don't need those two"); triage decision 2026-11-13: "both said no date -- see table, table is Remaining releases. this mean those two are no needed" → option 1 (remove)
**Dispatch go:** operator, 2026-11-13: "go ahead for forecast"
**Intent approved:** operator, 2026-11-13
**Intent approval words:** "go ahead for forecast", in reply to Claude's three intents (Earliest/Latest tiles, table removed)

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

## Fix (operator decisions 2026-11-13)

Operator, 2026-11-13, in order: "this mean those two are no needed"; "Remaining release seem to be missleading!"; "this is a
table that has only one row, and position seems to imply there should be more records?"; "probably remove the table and put
date back to Target forecast (earliest|latest)? what do you think?"; then "go ahead" to Claude's proposal: tiles show the open
release's dates labelled with its version, and the table goes. Since v1.43.7 (`d0c247dc`) the table was filtered to one release,
so Position, Kind and Plans repeated other panels; only the dates were new.

In `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (`k3dm-bugs.json`):

- Panel 29: title "Earliest"; expr
  `(max by (version) (k3dm_release_milestone_forecast_seconds{repo="$repo",bound="low"}) * 1000) and on(version) label_replace(k3dm_bug_current_release_info{repo="$repo"}, "version", "$1", "release", "(.*)")`;
  `fieldConfig.defaults.displayName` `${__field.labels.version}`; `options.textMode` `value_and_name`; unit stays `dateTimeAsIso`;
  `noValue` "-"; description "Earliest forecast date for the open release, from tagged release cadence. A range, not a commitment."
- Panel 30: the same with title "Latest", `bound="high"`, description "Latest forecast date for the open release, …".
- The tiles always follow the open release (the Auto meaning), not the Manual pick: a shipped release has no forecast.
- Delete panel 32 (the "Remaining releases" table, x 0, y 15, w 24, h 12). Move every panel with `y >= 27` up by 12, so no
  hole is left. Panels 26–31 keep ids, positions and (except 29/30 as above) contents.
- No producer change: `k3dm_release_milestone_forecast_seconds` and `k3dm_release_milestone_info` stay (tiles 29/30 and 31 read them).

In `scripts/tests/plugins/grafana_dashboard_bugs.bats`: update or remove the assertions on panel 32 (tests at ~:52 "release
forecast panels align…", ~:125 "remaining releases table shows a not-before column", ~:382 "release forecast sits between…",
~:878 "remaining releases table shows forecast dates only…") and any assertion on an absolute `y` of a panel that moved. Keep
every assertion that still applies to panels 26–31 and to the milestone queries. Add E1.

## Contract readers

Grep 2026-11-13 (`grep -rn "Remaining releases\|Target forecast"` and panel ids 29/30/32): `grafana-dashboard-bugs.yaml:2811-2886`
(29, 30) and the panel-32 block; `grafana_dashboard_bugs.bats:57-65, 130-131, 391, 882`; CHANGELOG.md:330/:517 and
`docs/plans/v1.43.5-release-forecast.md`, `docs/plans/v1.43.7-bug-dashboard-auto-release-selection.md` (history, unchanged).
No alert, script or other dashboard reads these panels. Writer of the series: `bin/k3dm-vectordb-metrics:958` (unchanged).

## Acceptance

```yaml
must:
  M1: no panel titled "Target forecast (earliest)", "Target forecast (latest)" or "Remaining releases" exists, and no table panel is in the Release forecast row
  M2: panels 29 and 30 are titled "Earliest" and "Latest", query bound low and high for the open release only, show the version as their name and dates as dateTimeAsIso
  M3: every panel that sat at y >= 27 sits exactly 12 higher, and no two panels overlap
must_not:
  N1: panels 26, 27, 28 or 31 change query, mappings, options, title or gridPos
  N2: any panel outside the Release forecast row changes anything but its y
  N3: tiles 29/30 follow the Manual release pick ($release or $release_mode in their expr)
evidence:
  - {id: E1, proves: [M1, M2, M3, N3], kind: offline, intent: "You will see a test that finds the two tiles titled Earliest and Latest reading the open release's low and high dates, finds no table in the forecast row, and finds every lower panel moved up 12 with no overlap. It fails on today's dashboard."}
  - {id: E2, proves: [N1, N2], kind: offline, intent: "You will see a script compare every other panel with today's dashboard: identical except the 12-row move; the whole dashboard suite passes."}
  - {id: E3, proves: [M1, M2], kind: live, intent: "After a hub promote, you will see the Release forecast row as one line of five tiles: Releases to target, Median gap, Earliest (v1.44.0, 2026-11-13), Latest (v1.44.0, 2026-11-16), Target state, with Plans directly below."}
interface:
  - "Grafana Bug Tracking dashboard, Release forecast row"
```

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` | re-point and retitle 29, 30; delete 32; move y >= 27 up 12 |
| `scripts/tests/plugins/grafana_dashboard_bugs.bats` | update panel-32 and moved-panel assertions; add E1 |

## Worker definition of done

- Change only the files above. No network, no make target that touches the hub or a cluster. Show E1 red on today's
  dashboard, then green. For E2, compare every panel except 29, 30, 32 against `git show HEAD:<file>` with y normalised
  (`y - 12` for panels that were at y >= 27) and paste the empty diff. Run `bats scripts/tests/plugins/grafana_dashboard_bugs.bats`
  and `PYTHONPATH=scripts/lib python3 -m pytest scripts/tests/bin/test_dashboard_queries.py -q` from the repo root and paste
  command, rc and counts. Leave changes uncommitted.
