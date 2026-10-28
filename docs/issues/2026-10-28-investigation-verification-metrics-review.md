# Investigation verification metrics — Luna and independent review

Operator explicitly requested dispatch to correct recovered incident's misleading
Verified/Live-verified notyet cells. P3spec:
[typed investigation metrics bug](../bugs/2026-10-28-bug-tracking-ignores-investigation-verification.md).
Task investigation-verification-metrics-luna, modelgpt-6-luna, isolated worktree.
Existing CLOSED recovered incident and historicalcause uncertainty remain intact.
No extra table/panel, causal FixSHA, metadata rewrite, deployment/provider/Keychain/
service access or screenshot export. Coordinator independently reviews and lands.

## Independent baseline before implementation

```text
============================= test session starts ==============================
platform darwin -- Python 3.15.1, pytest-9.1.1, pluggy-1.7.0
rootdir: /Users/cliang/src/gitrepo/personal/k3d-manager
collected 234 items

scripts/tests/bin/test_prior_art.py .................................... [ 15%]
................................................                         [ 35%]
scripts/tests/bin/test_check_bug_evidence.py .......                     [ 38%]
scripts/tests/bin/test_vectordb_bug_metrics.py ......................... [ 49%]
..........ss............................................................ [ 80%]
..............                                                           [ 86%]
scripts/tests/bin/test_live_evidence_acceptance.py ....................  [ 94%]
scripts/tests/bin/test_bug_tally.py ............                         [100%]

======================= 232 passed, 2 skipped in 25.08s ========================
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
Two optional Plans-query tests skipped because promtool absent from defaultPATH;
final gates will set PROMTOOL to existing3.2.1binary and requirezero skips.

## First draft independent rejection

Actual in-memory publisher/helper probes using task code:
```text
malformed-calendar {"accepted_investigation": false, "fix_sha": "7ea1032f", "live_evidence": "missing", "live_verified": "true", "verified": "true"}
malformed-explicit-fix-header {"accepted_investigation": true, "fix_sha": "-", "live_evidence": "ok", "live_verified": "true", "verified": "true"}

```
Malformed calendar proof incorrectly retainedtrue verification flags because it
fell back to LIVE-VERIFIED status; malformed explicit Fixheader was accepted as
noheader. Typed proof must not bypass explicit causal-fix metadata or promote
invalid proof. Existing unrelated doc_meta assertions had also been removed/
changed; coordinator required restoration, not weaker tests. Requested actual
Git history/ref date/verification-record tests instead of injectedfakeSHA/time,
legacy/unassigned semantics, and marker/header shared consistency.
Luna resumedrun2 with bounded feedback. First draft not committed/landed/accepted.
No new runtime failure or live command is inferred from these offline fixtures.
