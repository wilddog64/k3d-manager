# Bug: the Bug Tracking table drops Fixed in, Verified and Live-verified when a release has only open bugs

**Status:** LIVE-VERIFIED — 2026-10-16: operator's Bug Tracking dashboard, Release = v1.43.4 (7 bugs, all open), Hide live-verified: the table lists all 7 rows with Fixed in, Verified and Live-verified present and shown as "—". Was: FIXED — producer, dashboard and tests changed on `k3d-manager-v1.43.3` (PR #144)
**Priority:** P3
**Filed:** 2026-10-16
**Detected by:** operator (Grafana screenshot, Release = v1.43.4)
**Affected:** `bin/k3dm-vectordb-metrics` `_bug_status_metrics`, `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
**Branch:** `k3d-manager-v1.43.3`
**Approval:** explicit 2026-10-16 "we miss verifed and verify-live columns" (operator)

## Observed

With Release = v1.43.4 (seven bugs, all open) the table shows Release, Bug, Priority, Filed,
Open for and Status only. Fixed in, Verified and Live-verified are missing.

## Cause

`_bug_status_metrics` added `fixed_in`, `verified` and `live_verified` to `k3dm_bug_info` for fixed
bugs only; the v1.43.2 and v1.43.3 tests asserted the labels were absent on open bugs. Grafana
builds table columns from the labels present in the result, so when no row in the selected release
is fixed, the three columns do not exist and the organize transform has nothing to show.

## Fix

- `k3dm_bug_info` gives an unfixed bug `fixed_in="-"`, `verified="-"` and `live_verified="-"`.
  The `k3dm_bug_status_docs` aggregate is unchanged.
- Dashboard: the three columns map `-` to `—`; the Hide live-verified value becomes
  `^(false|-)?$`, otherwise it would hide every open bug.
- Tests: the open/deferred assertions now expect the placeholders; a new BATS test checks the
  `-` mapping on all three columns. Shown red on the pre-fix producer (3 pytest) and dashboard
  (2 BATS), then restored and `cmp`-proved.

## Live proof

After the release's `make appsets-reapply` (the bugs dashboard is Argo-tracked) and the next
Hermes metrics publish: Bug Tracking with Release = v1.43.4 shows the three columns with dashes.

## Live proof result (2026-10-16)

Operator screenshot, Release = v1.43.4, Verified fixes = Hide live-verified: 7 open rows, the three
columns present with "—". The first attempt showed an empty table because a stale browser value
`var-verified=^(false)?$` (the pre-fix filter) was still in the URL; it hides every `-` row. Re-selecting
Hide live-verified set `^(false|-)?$`. A saved bookmark from before v1.43.3 will reproduce the empty table.
