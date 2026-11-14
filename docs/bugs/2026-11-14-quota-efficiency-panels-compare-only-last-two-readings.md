# Bug: the quota-efficiency panels compare only the last two Codex quota readings, so they are almost always empty

**Status:** OPEN
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-14
**Severity:** low — four Agent Activity panels (Verified outputs, Observed quota delta, Outputs per percentage point, Quota efficiency coverage) show empty or 0 nearly all the time; nothing else depends on them
**Approval:** operator, 2026-11-14 ("yes, please", to "capture the quota-efficiency one as a P3 bug")
**Filed:** 2026-11-14
**Detected by:** operator (asked why the panels are empty and 0); root cause by Claude
**Introduced by:** v1.43.6 (`docs/plans/v1.43.6-dispatch-codex-solo-activity.md`)
**Should have been caught by:** review
**Prior art:** docs/bugs/2026-11-01-reread-share-ignores-bash-reads-and-file-changes.md (grep; vector search unavailable) — read, different metric
**Affected:** `bin/k3dm-dispatch-metrics` (`_quota_efficiency`, about `:2056-2118`); Agent Activity dashboard row "Quota efficiency (verified outcomes)"

## Symptom

On 2026-11-14 the three ratio panels were empty and coverage showed `0`. `bin/k3dm-dispatch-metrics --dry-run` gave
`k3dm_codex_verified_outputs nan` and `k3dm_codex_quota_efficiency_coverage 0`.

## Root cause

`_quota_efficiency` takes `valid[-2:]`, the two newest observations in
`~/.local/share/k3d-manager/worktrees/codex-quota-observations.jsonl`, and computes only when usage rose by more than
0.01 between them. Then it counts tasks whose passing verify falls inside that interval.

- The two newest readings were both 14.0% (2026-11-14 00:24Z and 03:04Z): delta 0, so every value is `nan`.
- Usage rose between only 106 of 633 consecutive pairs. When it does rise, the interval is minutes long, so the
  verified count is nearly always 0.
- The data for a real value exists: the current cycle (resets 2026-11-17T13:27Z) has 146 readings rising from 1% to
  14%, with several fixes verified in that time.

The plan allowed a "bounded" interval of the implementer's choosing (`v1.43.6-dispatch-codex-solo-activity.md:162`),
so this meets its letter. But the panels' own description says "within one secondary reset cycle", and the
two-sample interval almost never yields a value.

## Fix direction (not yet a spec)

Use the first and last valid observations of the current reset cycle (`resets_at` of the newest observation) as the
interval, keeping every existing N/A rule (no delta, reversed sample, reset change). Show the interval start and end
on the dashboard as now. Decide at triage whether the previous complete cycle should be shown too.
