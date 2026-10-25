# Bug Tracking "Release (filed in)" dropdown omits the current release until a bug is filed in it

**Status:** FIXED — fix on `k3d-manager-v1.43.6`; live once the v1.43.6 ApplicationSets are reapplied
**Priority:** P3
**Severity:** Low — the Release card and plan rows show v1.43.6; only the filter cannot select it
**Filed:** 2026-10-24, from the operator's screenshot of the k3dm Bug Tracking dashboard
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`

## Symptom

On 2026-10-24 the Release card read `v1.43.6`, but the "Release (filed in)" dropdown listed v1.50.1, v1.45.x,
v1.44.0, v1.43.5 and older, with no v1.43.6.

## Root cause

The `release` variable took its options from `label_values(k3dm_bug_info{repo="$repo"}, release_order)`, so a
release appeared only once a bug had been filed in it. v1.43.6 was cut that day and had no bug docs yet. Its
five plans are exported as `k3dm_plan_release_docs`, which carries the same `release_order` label, but the
dropdown did not read that metric.

A second, separate defect was found during the fix: the variable's saved default was still `v1.43.5`, which
fails the existing test that the dashboard opens on the release branch's version.

## Fix

- The dropdown reads `release_order` from both `k3dm_bug_info` and `k3dm_plan_release_docs`, so any release
  with plans or bugs is selectable. Selecting a release with no bugs shows zero bugs, which is correct.
- The saved default is `v1.43.6`. Following the current release automatically remains
  `docs/plans/v1.43.9-bug-dashboard-auto-release-selection.md`.

## Evidence

- `bats scripts/tests/plugins/grafana_dashboard_bugs.bats`: 28/28 pass on the fix.
- The updated query assertion (test 7) fails on the pre-fix dashboard, in a detached worktree at the pre-fix HEAD.
- Live check is pending: after `make appsets-reapply` on the v1.43.6 release, v1.43.6 appears in the dropdown.
