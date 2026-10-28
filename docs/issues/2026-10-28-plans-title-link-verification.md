# Plans Title link cleanup verification

Operator explicitly requested keep Title, link it to the plan and remove Plan
from view to reduce crowding. Filed P3 bug 2026-10-28-plans-table-redundant-plan-column.
Only panel107 field overrides changed: Plan custom.hidden replaces width,
existing Open plan document link moved to Title. Plan is retained in organize
for URL interpolation, with branch. Other fields, widths, queries, transforms,
sort and layout unchanged. No cluster writes, screenshot export or new panels.

## Initial suite output

Old width contract treated custom.hidden as visible. Updated it to account for
Grafana hidden overrides while retaining width budget and visible-column checks.
Actual initial output:
```text
1..38
ok 1 bug dashboard is valid JSON with uid and Prometheus datasource
ok 2 release forecast panels align by version and map dates and states
ok 3 release cadence panel names the median tag gap and explains cadence
ok 4 target state names the blocked milestone and reason
ok 5 remaining releases table shows a not-before column
ok 6 bug dashboard has a release variable
ok 7 bug dashboard has a repo variable and scopes every bug selector
ok 8 bug dashboard has a verified filter
ok 9 bug dashboard defaults to Auto current release and keeps Manual selection
ok 10 Auto bug filtering follows the repo-scoped current-release metric
ok 11 release dropdown and table use version-order labels
ok 12 Auto and Manual modes filter every filed-in bug summary and the table
ok 13 release summary tiles follow mode while repository-wide tiles do not
ok 14 bug dashboard separates filed-in and fixed-in release views
ok 15 every bug metric queried by dashboard is emitted
ok 16 bug dashboard panels have non-overlapping positions inside 24 columns
ok 17 release forecast sits between the plan tiles and the Plans table, and lists only unshipped milestones for the selected release
ok 18 plan titles link to the plan doc with redundant Plan hidden, and bug tiles say bugs
ok 19 bug dashboard release plans row shows joined plan state without not-started inference
ok 20 bug dashboard Plans table orders plans numerically and shows dependencies
ok 21 bug dashboard bar charts blank the labels of empty segments
ok 22 bug dashboard pins one colour per priority and state, independent of data order
ok 23 bug dashboard stacked bars give counts in the tooltip, not on-bar labels
ok 24 open bugs table links each title to its doc on the scanned branch
ok 25 bug dashboard separates verified and live-verified summary and table
ok 26 Verified column reads verified, and only Live-verified reads live
ok 27 open bugs table sorts by sort_key before hiding it
ok 28 open bugs table sits in row 22 under the stats, with the time series moved below
ok 29 bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified (at), Live-verified (at)
ok 30 open bugs table shows age in days, not a duration that rolls up to weeks
ok 31 bugs table shows a dash, not a missing column, for an open bug's Fixed in and verification
ok 32 bugs table pairs each verification column with its timestamp
ok 33 Plans Dispatch links to the release in Agent dispatch
ok 34 priority tiles say they count open bugs
ok 35 bugs table columns fit a laptop-width panel without horizontal scrolling
not ok 36 plans table columns fit a laptop-width panel without horizontal scrolling
# (in test file scripts/tests/plugins/grafana_dashboard_bugs.bats, line 766)
#   `[ "${status}" -eq 0 ]' failed
ok 37 remaining releases table shows forecast dates only and fits a laptop-width panel
ok 38 Plans table separates verified and live-verified status indicators

```

## Regression against old dashboard

```text
1..2
not ok 1 plan titles link to the plan doc with redundant Plan hidden, and bug tiles say bugs
# (in test file scripts/tests/plugins/grafana_dashboard_bugs.bats, line 383)
#   `[ "${status}" -eq 0 ]' failed
not ok 2 plans table columns fit a laptop-width panel without horizontal scrolling
# (in test file scripts/tests/plugins/grafana_dashboard_bugs.bats, line 768)
#   `[ "${status}" -eq 0 ]' failed

```

## Full focused suite

```text
1..38
ok 1 bug dashboard is valid JSON with uid and Prometheus datasource
ok 2 release forecast panels align by version and map dates and states
ok 3 release cadence panel names the median tag gap and explains cadence
ok 4 target state names the blocked milestone and reason
ok 5 remaining releases table shows a not-before column
ok 6 bug dashboard has a release variable
ok 7 bug dashboard has a repo variable and scopes every bug selector
ok 8 bug dashboard has a verified filter
ok 9 bug dashboard defaults to Auto current release and keeps Manual selection
ok 10 Auto bug filtering follows the repo-scoped current-release metric
ok 11 release dropdown and table use version-order labels
ok 12 Auto and Manual modes filter every filed-in bug summary and the table
ok 13 release summary tiles follow mode while repository-wide tiles do not
ok 14 bug dashboard separates filed-in and fixed-in release views
ok 15 every bug metric queried by dashboard is emitted
ok 16 bug dashboard panels have non-overlapping positions inside 24 columns
ok 17 release forecast sits between the plan tiles and the Plans table, and lists only unshipped milestones for the selected release
ok 18 plan titles link to the plan doc with redundant Plan hidden, and bug tiles say bugs
ok 19 bug dashboard release plans row shows joined plan state without not-started inference
ok 20 bug dashboard Plans table orders plans numerically and shows dependencies
ok 21 bug dashboard bar charts blank the labels of empty segments
ok 22 bug dashboard pins one colour per priority and state, independent of data order
ok 23 bug dashboard stacked bars give counts in the tooltip, not on-bar labels
ok 24 open bugs table links each title to its doc on the scanned branch
ok 25 bug dashboard separates verified and live-verified summary and table
ok 26 Verified column reads verified, and only Live-verified reads live
ok 27 open bugs table sorts by sort_key before hiding it
ok 28 open bugs table sits in row 22 under the stats, with the time series moved below
ok 29 bugs table shows Release, Bug, Priority, Filed, Open for, Status, Fixed in, Verified (at), Live-verified (at)
ok 30 open bugs table shows age in days, not a duration that rolls up to weeks
ok 31 bugs table shows a dash, not a missing column, for an open bug's Fixed in and verification
ok 32 bugs table pairs each verification column with its timestamp
ok 33 Plans Dispatch links to the release in Agent dispatch
ok 34 priority tiles say they count open bugs
ok 35 bugs table columns fit a laptop-width panel without horizontal scrolling
ok 36 plans table columns fit a laptop-width panel without horizontal scrolling
ok 37 remaining releases table shows forecast dates only and fits a laptop-width panel
ok 38 Plans table separates verified and live-verified status indicators

```

YAML/JSON valid; only Plans panel107 field overrides changed; queries,
transformations, layout and sorting unchanged. git diff --check clean.
ShellCheck not applicable: no shell implementation changed. Full curated suite
not rerun for display-only edit; existing unrelated failures remain recorded.
Operator next applies only grafana-dashboard-bugs.yaml, then reloads and clicks
Title to verify document navigation and absence of visible Plan column.

## Commit and required gates

Fix commit b543cb91. Staged gates actual output (both exit0):
```text
$ ./scripts/k3d-manager _agent_lint
running under bash version 5.3.20(1)-release
$ ./scripts/k3d-manager _agent_audit
running under bash version 5.3.20(1)-release
check-doc-links: 4 file(s) OK
[k3d-manager-v1.43.9 b543cb91] checkpoint: before fix: link plan titles and hide redundant Plan column
```
