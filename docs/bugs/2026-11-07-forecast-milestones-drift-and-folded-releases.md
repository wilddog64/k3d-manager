# Bug: Release forecast drifts from the roadmap unnoticed, and releases that will never ship make every row overdue

**Status:** VERIFIED 2026-11-07 offline — landed `11982d31` (Luna, corrections by Claude); independent Acceptance-only verifier 17/17 on the fix, 13 red on pre-fix `d02fc28e` (the 4 passes are paired controls); verify recorded. Live E2 pending (after `make platform-ops`).
**Priority:** P3
**Waiting on:** live check — since 2026-11-07
**Fix commit:** `11982d31`
**Severity:** low — the Remaining releases panel was blank or showed every row overdue; no data is lost
**Branch:** `k3d-manager-v1.43.14`
**Release:** v1.43.14 (bug; does not count toward the five-plan cap)
**Filed:** 2026-11-07, by Claude, from the operator's screenshot of Bug Tracking → Release forecast → Remaining releases ("No data")
**Approval:** operator 2026-11-07: "go ahead to file your suggestion as a P3 bug and dispatch to Luna"; v1.43.10 and v1.43.11: "mark them fold". Not critical (metrics script, one test, the pre-commit hook).
**Component:** `bin/k3dm-vectordb-metrics` (`_load_milestones`, `_forecast`, `_forecast_metrics`), `docs/release-milestones.json`, `scripts/tests/bin/test_release_milestones_drift.py`, `.githooks/pre-commit`, `Makefile`
**Related:** [`2026-10-25-release-forecast-ignores-live-window-and-unnamed-blocker`](2026-10-25-release-forecast-ignores-live-window-and-unnamed-blocker.md) (added `not_before`; a different defect), `docs/plans/v1.43.5-release-forecast.md` (the forecast design)

## Problem

1. **Drift goes unnoticed.** `docs/release-milestones.json` listed releases only up to v1.43.12 while the
   release branch was `k3d-manager-v1.43.14`. Remaining releases showed "No data" until Claude added
   v1.43.13–v1.45.0 by hand (`5bc19ecc`). `test_release_milestones_drift.py` should have caught it, but it
   reads only `### Candidate milestone — vX.Y.Z` headings. Patch releases are headed
   `### Patch release — vX.Y.Z` in `docs/roadmap.md`, so no patch release is ever checked. It also ignores
   `docs/plans/vX.Y.Z-*.md` file names, and it runs only in CI, after the commit.
2. **Releases that will never ship.** v1.43.10 and v1.43.11 have no tag and never will: their work was
   folded into later releases (operator 2026-11-07: "mark them fold"). `_forecast` treats every untagged
   milestone as still to come, so they show as rows with dates and count as remaining releases.
   (Correction 2026-11-07, after Luna stopped on the first dispatch: these rows do **not** cause the
   overdue rows. Each row adds one cadence step to the one before it, so an extra row pushes later rows
   *later*. The overdue rows come from item 3.)
3. **The release being built, and every row after it, shows as overdue.** The chain starts at the last
   tag (v1.43.13, 2026-11-01) and adds the median gap (about 0.7 days) per row. Once more time than that
   has passed, the current release and the next few rows all fall before now and are flagged overdue,
   while work on the current release is still going. That says nothing useful.

## Fix

### F1. A milestone can be `folded`

- `docs/release-milestones.json`: an optional `"state": "folded"` on a milestone. Claude set it on
  v1.43.10 and v1.43.11 in this change.
- `_load_milestones` accepts only `"folded"` as a `state` value (anything else raises `ValueError`), and
  refuses a folded milestone that is the `target`.
- `_forecast` skips folded milestones: they get no row, do not advance the chain, and do not count in
  `k3dm_release_milestones_remaining`. Folding is exactly equivalent to deleting the entry from the file
  for every forecast output.

### F2. The release being built is `in_progress`

- In `_forecast`, the untagged milestone equal to `_current_release` gets `state="in_progress"`. Its
  low/mid/high bounds are each `max(now, previous + cadence quantile)`, it is never `overdue`, and later
  rows chain from its bounds. It emits `k3dm_release_milestone_forecast_seconds` like a forecast row.
- `not_before` and `blocked_by` keep their current meaning and take precedence as they do today.
- If the Remaining releases panel (`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`) filters
  or colours by `state`, add `in_progress` there so the row still shows with dates. Change nothing else on
  the dashboard.

### F3. Drift is refused at commit time

- `scripts/tests/bin/test_release_milestones_drift.py` also reads `### Patch release — vX.Y.Z` headings
  and the versions in `docs/plans/vX.Y.Z-*.md` file names. Every such version that is later than the newest
  release tag and not later than the target must have a milestone (older untagged plan versions, such as
  v1.41.1, are history and are ignored). Every untagged, non-folded milestone must appear in the
  roadmap (as today).
- `make check-release-milestones` runs that test alone.
- `.githooks/pre-commit` runs it when `docs/roadmap.md`, `docs/release-milestones.json` or a
  `docs/plans/*.md` file is staged, and refuses the commit on failure, printing the missing versions and
  `make check-release-milestones`. Follow the existing guard pattern in the hook, including a skip
  variable (`K3DM_SKIP_RELEASE_MILESTONES=1`) like `K3DM_SKIP_DOC_LINKS`.

## Files

- `bin/k3dm-vectordb-metrics` (`_load_milestones`, `_forecast`, `_forecast_metrics` only)
- `scripts/tests/bin/test_vectordb_bug_metrics.py`
- `scripts/tests/bin/test_release_milestones_drift.py`
- `.githooks/pre-commit`
- `Makefile` (`check-release-milestones` and its help line)
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (Remaining releases panel, only if F2 needs it)
- `CHANGELOG.md` (one `### Fixed` bullet under `[Unreleased]`)

## What NOT to Do

- Do not generate `docs/release-milestones.json`. It holds hand-entered facts (`not_before`,
  `blocked_by`, `target_reason`) that the repo cannot derive.
- Do not change cadence (`_cadence`), the `not_before` floor, the blocked chain, or any bug-tally metric.
- Do not add, remove or retag git tags. Do not run anything against the hub or the Pushgateway; tests use
  `127.0.0.1:9`.
- Fixtures build a scratch git repo with their own tags, roadmap, plans and milestones file, and first
  assert they are not pointed at the real tree. The drift test itself runs on the real tree.
- Write the must_not tests first and show them red on the pre-fix tree.
- Do not edit CLAUDE.md, `memory-bank/` or `docs/roadmap.md`. Do not commit to `main`, create a PR or skip
  hooks.

## Acceptance

```yaml
interface:
  - "python3 bin/k3dm-vectordb-metrics forecast functions: _load_milestones(root, ref), _forecast(milestones, tags, cadence, now), _forecast_metrics(root, ref, now)"
  - "docs/release-milestones.json milestone field: state (only 'folded')"
  - "make check-release-milestones; .githooks/pre-commit with staged docs/roadmap.md, docs/release-milestones.json or docs/plans/*.md"
  - "env: scratch git repo with tags, docs/roadmap.md, docs/plans/, docs/release-milestones.json and a release branch name; fixed now"
must:
  - id: M1
    text: "A folded milestone produces no k3dm_release_milestone_info row, is not counted in k3dm_release_milestones_remaining, and the next milestone's bounds are the same as if the folded one were absent from the file."
  - id: M2
    text: "The untagged milestone equal to the current release branch has state in_progress, bounds >= now, and overdue false; the milestone after it chains from its bounds."
  - id: M3
    text: "The drift check fails, naming the version, when a version later than the newest release tag and not later than the target appears in a '### Patch release — vX.Y.Z' heading or a docs/plans/vX.Y.Z-*.md file name but not in the milestones file; it passes on the real tree after this change."
  - id: M4
    text: "make check-release-milestones runs the drift check alone and exits nonzero on drift."
must_not:
  - id: N1
    text: "A folded milestone never appears as a forecast row or in the remaining count (paired control: the same fixture without state folded does produce a row for it and counts it)."
  - id: N2
    text: "The current release, and the milestones chained after it, are never flagged overdue (paired control: the same fixture with no matching release branch flags them overdue)."
  - id: N3
    text: "_load_milestones refuses a state value other than folded, and refuses a folded target."
  - id: N4
    text: "The pre-commit hook does not let a commit through that stages docs/roadmap.md with a new untagged '### Patch release' version missing from the milestones file (paired control: the same commit passes once the milestone is added, and a commit that stages none of the three paths does not run the check)."
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    kind: offline
    what: "pytest scripts/tests/bin/test_vectordb_bug_metrics.py scripts/tests/bin/test_release_milestones_drift.py and the hook test, with must_not tests red on the pre-fix tree; ruff clean."
  - id: E2
    proves: [M1, M2]
    kind: live
    what: "Claude or the operator, after make platform-ops: Bug Tracking → Remaining releases shows no v1.43.10 or v1.43.11 row, v1.43.14 as in progress with dates from today, and later rows not overdue."
```
