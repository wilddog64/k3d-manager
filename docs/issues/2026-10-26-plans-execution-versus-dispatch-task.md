# Plans screenshot: document execution versus ledger task outcome

**Status:** Diagnosis confirmed; existing P3 remains open
**Priority:** P3

Operator supplied a Plans screenshot showing five landed tasks, while Execution
is proposed for drift/CNI/complexity, implemented for retrieval, and ready for
OrbStack. All Dispatch cells show unknown. Reproduced from the current exporter,
five plan files, dashboard query, and M4 dispatch ledger. This extends
`docs/bugs/2026-10-26-release-plans-dispatch-approval-unknown-despite-landed.md`.

## Cause and interpretation

- Execution is the normalized leading keyword of the plan's `**Status:**` header,
  parsed by `bin/k3dm-vectordb-metrics:_plan_state`. Three files still start
  PROPOSED; OrbStack still starts READY. Retrieval starts LANDED, mapping to
  implemented. Subsequent words such as offline VERIFIED do not override that
  leading keyword, so retrieval verification is unknown.
- Dispatch is the ambiguous display name for `dispatch_approval`. `_plan_dispatch`
  reads only a dedicated `**Dispatch:**` header beginning go, needed, or not
  required. None of these five plans has that header; the approval and dispatch
  prose elsewhere in the files is not parsed. Unknown means missing structured
  approval metadata, not a failed worker or proof of absent operator permission.
- Dispatch task is `k3dm_dispatch_plan_state` from `bin/k3dm-dispatch-metrics`,
  joined on plan in dashboard panel 107. All five tasks have a land event and
  passed landing-test result. This records code integration, not live acceptance.
- The dispatcher does not revise plan headers at land. Retrieval got a separate
  status update in f5c1a745; the others retain old headers. OrbStack's code landing
  does not establish that its operator-run hub upgrade has occurred.
- Blocked by is also computed from document metadata. It can misleadingly say
  dispatch approval unknown for an already landed task. The source mismatch is
  real; it is not explained by a browser refresh or by failed landing.
- The previous dashboard presentation fix was reverted in 915c55f4 at operator
  request. This investigation preserves that decision: no exporter, dashboard,
  plan Status, Approval, or Dispatch headers were changed.

Recommended follow-up: reconcile the four stale plan Status headers against
accepted implementation/verification evidence; explicitly record dispatch
approval separately where appropriate; agree a clearer column label with the
operator/Claude before altering the reverted table design. Do not infer live
verification from ledger landing or silently invent approval records.

## Actual evidence

Machine:

```text
m4-air.local
m4-air.local
```

Invoked the current exporter's `_status_value`, `_plan_state`, `_plan_header`, and
`_plan_dispatch` functions against the five current plan files:

```text
Plan | Status-derived execution | verification | Dispatch header | dispatch approval
v1.43.9-cni-ipam-reclaim-visibility | proposed | n/a | <missing> | unknown
v1.43.9-dispatch-spec-and-change-complexity | proposed | n/a | <missing> | unknown
v1.43.9-orbstack-upgrade-coordinated | ready | n/a | <missing> | unknown
v1.43.9-vectordb-drift-kinds-and-age | proposed | n/a | <missing> | unknown
v1.43.9-vectordb-retrieval-quality-probe | implemented | unknown | <missing> | unknown
```

Invoked current `read_ledger` and `_dispatch_state` functions, selecting v1.43.9
events by each plan slug:

```text
Ledger malformed lines: 0
cni-ipam-reclaim-visibility | landed | land test_result=passed
dispatch-spec-and-change-complexity | landed | land test_result=passed
orbstack-upgrade-coordinated | landed | land test_result=passed
vectordb-drift-kinds-and-age | landed | land test_result=passed
vectordb-retrieval-quality-probe | landed | land test_result=passed
```

`bats scripts/tests/plugins/grafana_dashboard_bugs.bats` exited 0:

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
ok 18 plan names link to the plan doc on the scanned branch, and bug tiles say bugs
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
ok 38 Plans table retains the original single verification column and dispatch labels
```

One ancillary source search used an unmatched unquoted Zsh glob and reported:

```text
zsh:2: no matches found: scripts/lib/*dispatch*
```

The ledger location was then obtained directly from `bin/k3dm-dispatch-metrics`
and read successfully as shown above. No live Prometheus query or deployment was
attempted; evidence is the screenshot, current code/documents, and local ledger.
ShellCheck is not applicable because this investigation changes Markdown only.

The initial closeout staging/push ran inside the restricted sandbox and returned:

```text
fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted
running under bash version 5.3.20(1)-release
running under bash version 5.3.20(1)-release
running under bash version 5.3.20(1)-release
fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted
ERROR: Failed to stage files for checkpoint
ssh: Could not resolve hostname github.com: -65563
fatal: Could not read from remote repository.

Please make sure you have the correct access rights
and the repository exists.
```

Retry uses the required filesystem/network permission rather than changing hooks
or bypassing the audit. These errors are environment restrictions, not evidence
of a dashboard/ledger defect.
