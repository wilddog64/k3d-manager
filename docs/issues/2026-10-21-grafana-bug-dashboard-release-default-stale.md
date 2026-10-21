# Grafana Bug Tracking dashboard release selector default is stale

**Date:** 2026-10-21
**Area:** `k3dm-bugs` dashboard regression suite
**Status:** observed during investigation; unrelated to the live bug-row link failure

## What was tested

Ran `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` on branch
`k3d-manager-v1.43.5` while rechecking the existing bug-link fix.

## Actual output

```text
1..22
ok 1 bug dashboard is valid JSON with uid and Prometheus datasource
ok 2 bug dashboard has a release variable
ok 3 bug dashboard has a repo variable and scopes every bug selector
ok 4 bug dashboard has a verified filter
not ok 5 bug dashboard opens on the release branch's version
# (in test file scripts/tests/plugins/grafana_dashboard_bugs.bats, line 77)
#   `[ "${status}" -eq 0 ]' failed
ok 6 release dropdown and table use version-order labels
ok 7 release filters status summary stats and table
ok 8 bug dashboard separates filed-in and fixed-in release views
ok 9 every bug metric queried by dashboard is emitted
ok 10 bug dashboard panels have non-overlapping positions inside 24 columns
ok 11 bug dashboard bar charts blank the labels of empty segments
ok 12 bug dashboard pins one colour per priority and state, independent of data order
ok 13 bug dashboard stacked bars give counts in the tooltip, not on-bar labels
ok 14 open bugs table links each title to its doc on the scanned branch
ok 15 bug dashboard separates verified and live-verified summary and table
ok 16 Verified column reads verified, and only Live-verified reads live
ok 17 open bugs table sorts by sort_key before hiding it
ok 18 open bugs table sits in row 22 under the stats, with the time series moved below
ok 19 bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified (at), Live-verified (at)
ok 20 open bugs table shows age in days, not a duration that rolls up to weeks
ok 21 bugs table shows a dash, not a missing column, for an open bug's Fixed in and verification
ok 22 bugs table pairs each verification column with its timestamp
```

## Finding

The failing assertion expects the dashboard release variable's default to match the current
release branch. The source currently sets its default to `v1.43.4` while this branch is
`k3d-manager-v1.43.5`. The failure is separate from the Bug-column data-link issue and was not
changed during this verification-only turn.

## Follow-up

Review whether the dashboard's current release default should advance with the release branch,
then update the default and regression test under a separately scoped change.
