# Bug: Release forecast dates v1.43.7 before its live window, and Target state does not say what is blocked

**Status:** DISPATCHED to Luna 2026-10-25 (after `bug-dashboard-auto-release-selection` landed as `f6e92ffd`)
**Priority:** P3
**Severity:** low — the forecast is optimistic and one stat is ambiguous; no data is wrong
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the operator's review of the Release forecast row (screenshot 242)
**Approval:** explicit 2026-10-25 ("that works for me. go ahead with both", after Claude proposed items 1, 2 and 4 and declined item 3). Not critical (metrics script and one dashboard ConfigMap).
**Component:** `bin/k3dm-vectordb-metrics` (`_load_milestones`, `_forecast`, `_forecast_metrics`), `docs/release-milestones.json`, `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (panels 28, 31, 32)
**Related:** `docs/plans/v1.43.5-release-forecast.md` (the forecast design)

## Problem

On k3dm Bug Tracking, row **Release forecast**, on 2026-10-25:

1. **Median days per release** (panel 28) reads 0.676. It is the median gap between release tags over the
   last 12 releases (`k3dm_release_cadence_seconds{quantile="0.5"}`), not the effort a release takes. The
   title invites the second reading, and the panel has no description.
2. **Target state** (panel 31) reads "blocked upstream" while **Remaining releases** gives v1.43.7 dates.
   Both are correct: the target is v1.50.0, and v1.49.0 is blocked by "TwinkleAI app M1 near done", so
   v1.49.0 and everything after it get no date. The stat names neither the blocked milestone nor the
   reason, so it reads as if the selected release were blocked.
3. **Remaining releases** (panel 32) forecasts v1.43.7 for 2026-10-25 to 2026-10-27. v1.43.7 carries
   `docs/plans/v1.43.7-hub-argocd-pinned-upgrade.md`, whose live evidence is the upgrade itself in the
   2026-11-03 window (fallback 2026-11-10). A release here is the merged, tagged PR, and the PR gate needs
   live evidence, so v1.43.7 cannot ship before 2026-11-03. `_forecast` has no way to express a date
   floor: it only knows cadence and `blocked_by`.

The operator also asked whether the forecast should model incidents such as the 2026-10-25 OrbStack and
Vault recovery. It should not: the cadence is measured from real tag gaps, which already include past
incidents, and the latest bound is the 75th percentile. That item is out of scope.

## Fix

### F1. A milestone can carry a `not_before` date

`docs/release-milestones.json`: an optional `"not_before": "YYYY-MM-DD"` on a milestone, read as
00:00 UTC that day. Add `"not_before": "2026-11-03"` to v1.43.7, with an optional
`"not_before_reason"` (e.g. `"hub ArgoCD upgrade live window"`).

`_load_milestones`: reject a `not_before` that is not a valid `YYYY-MM-DD` date (raise `ValueError`, as
for a bad version).

### F2. `_forecast` honours the floor and pushes later releases back

For each bound (`low`/`mid`/`high`) keep a running value starting at the cadence's `last_ts`. For each
forecast row: `value = max(previous + gap, not_before_ts)`, then clamp to `now` as today (setting
`overdue` when clamped). The next row chains from this row's value, so every release after a floored
one moves back with it. Without any `not_before` the result must equal today's `last_ts + k * gap`
exactly. A shipped release ignores its `not_before`.

Also set `row["floored"] = True` when the floor raised the `mid` value.

### F3. Export the floor

`k3dm_release_milestone_info` gains `not_before="YYYY-MM-DD"` (empty when absent) and
`not_before_reason` (sanitised and truncated like `blocked_by`). No new metric name.

### F4. Dashboard

- Panel 28: title **Median days between releases**; description: "Median gap between the last 12
  release tags. A cadence, not the effort one release takes. Earliest and latest forecasts use the 25th
  and 75th percentile gaps."
- Panel 31: when the target is blocked or after a blocked release, show the **blocked milestone and its
  reason**, e.g. `blocked at v1.49.0: TwinkleAI app M1 near done`, from the `state="blocked"` series of
  `k3dm_release_milestone_info` (its `version` and `blocked_by` labels). Keep the other states as they
  are. Add a description naming the target version's source (`target: true` in
  `docs/release-milestones.json`).
- Panel 32: a **Not before** column from the new label, shown only when set.

### F5. Docs

`docs/guides/grafana-dashboards.md`, Release forecast section: what the median is, what Target state
names when blocked, and how `not_before` works and when to set it (a plan whose live evidence waits for
a scheduled window).

## Tests

Add to `scripts/tests/bin/test_vectordb_bug_metrics.py` (or the file that already tests `_forecast`):

1. No `not_before` anywhere: forecasts are identical to the pre-fix formula for every bound.
2. `not_before` later than the cadence date: that row's low, mid and high are each at least the floor.
3. The release after a floored one is later than the floored release's value for the same bound.
4. A `not_before` earlier than the cadence date changes nothing.
5. A shipped release with `not_before` stays `shipped`.
6. An invalid `not_before` (`2026-13-40`, `next week`) raises `ValueError`.
7. `_forecast_metrics` exports `not_before` and `not_before_reason` on `k3dm_release_milestone_info`.

Add to `scripts/tests/plugins/grafana_dashboard_bugs.bats`:

8. Panel 28's title is **Median days between releases** and it has a description.
9. Panel 31 has a query that selects `state="blocked"` and shows `version` and `blocked_by`.
10. Panel 32 shows a Not before column.

`scripts/tests/bin/test_release_milestones_drift.py` must stay green.

## Files

- `bin/k3dm-vectordb-metrics`
- `docs/release-milestones.json`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A milestone with not_before gets no forecast bound earlier than that date (00:00 UTC).
  - id: M2
    text: Every forecast release after a floored release is no earlier than the floored release, bound by bound.
  - id: M3
    text: v1.43.7 is floored at 2026-11-03 in docs/release-milestones.json and the forecast reflects it.
  - id: M4
    text: Target state names the blocked milestone and its reason when the target is blocked or after a blocked release.
  - id: M5
    text: The cadence panel is titled Median days between releases and says it is a cadence, not effort.
must_not:
  - id: N1
    text: With no not_before set, no forecast value may change from the pre-fix output.
  - id: N2
    text: A malformed not_before must not be silently ignored; loading fails as for a bad version.
  - id: N3
    text: A shipped release must not be re-forecast because of its not_before.
  - id: N4
    text: No new metric name and no change to existing label values other than the added labels.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, M5, N1, N2, N3, N4]
    text: K3DM_VECTORDB_PUSHGATEWAY_URL=http://127.0.0.1:9 pytest scripts/tests/bin/test_vectordb_bug_metrics.py scripts/tests/bin/test_release_milestones_drift.py green; bats scripts/tests/plugins/grafana_dashboard_bugs.bats green; tests 2, 3, 6, 8, 9 red on a temp copy of the pre-fix files; ruff 0.15.8 clean; make validate-manifests passes.
  - id: E2
    kind: live
    proves: [M3, M4, M5]
    text: After the hub syncs and Hermes pushes, the operator's screenshot shows v1.43.7 forecast on or after 2026-11-03, later releases after it, Target state naming v1.49.0 and its reason, and the renamed cadence panel.
interface:
  - bin/k3dm-vectordb-metrics (functions _load_milestones, _forecast, _forecast_metrics, as imported by test_vectordb_bug_metrics.py)
  - docs/release-milestones.json (milestones[].not_before, milestones[].not_before_reason)
  - k3dm_release_milestone_info{version,state,blocked_by,not_before,not_before_reason}
  - Grafana /d/k3dm-bugs, row Release forecast
```

## Definition of Done

- [ ] F1–F5 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] E1 green; paste the summaries.
- [ ] Tests 2, 3, 6, 8 and 9 shown red on a temp copy of the pre-fix files.
- [ ] Commit: `fix(forecast): floor releases at their live window and name the blocked milestone`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT model incidents or add a separate "code complete" series.
- Do NOT push to the real Pushgateway; tests use `K3DM_VECTORDB_PUSHGATEWAY_URL=http://127.0.0.1:9`.
- Do NOT change or remove existing tests or assertions, except where this spec changes the behaviour.
- Do NOT modify files outside the Files list.
