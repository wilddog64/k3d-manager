# Six selected bugs: GPT-6-Luna batch and sequential live verification

**Status:** Two fixes landed/offline VERIFIED; three workers running; incident doctor queued
**Priority:** P2

Operator selected all six screenshot rows on 2026-10-27, requested GPT-6-Luna
implementation, independent verification and operator live checks one at a time.
The GHCR security requirement conflicts with the intentional BusyBox wget
header-argv tradeoff; operator explicitly approved a compatible transport/image
change to satisfy N1. No scan, credential rotation, account provisioning, restart
or production deployment is delegated to workers.

Scopes are the existing bug docs, not new release plan files. Scope commits
0510c5d3 (three dashboard/registry tasks) and 5dae466f (heartbeat, attribution,
incident-doctor scopes) were pushed before starts. All five started workers
report runtime model gpt-6-luna. A temporary K3DM_CODEX_BIN wrapper also forces
that explicit model on resume to work around the separately recorded dispatcher
resume-model bug.

| Item | Task | Current result |
|---|---|---|
| Probe-age color | vectordb-probe-age-thresholds-luna | landed 74d2d4e2; first live check pending |
| Live verified column | plans-live-verification-column-luna | landed 9893651f; live check queued |
| GHCR diagnostics/transport | ghcr-candidate-auth-diagnostics-luna | running |
| Independent heartbeats | independent-heartbeats-luna | running |
| Primary/acting/landing attribution | primary-coordinator-handoffs-luna | running |
| Webhook incident doctor | webhook-incident-doctor-luna | scoped, queued to bound active workers |

The webhook item remains an undiagnosed incident. Its bounded implementation
prepares read-only diagnostic tooling; offline tests cannot establish historical
root cause or satisfy operator-run E1/E2. Heartbeat reporting stays unconfigured
until operator enrollment and protected secret provisioning. Healthchecks.io
[official docs](https://healthchecks.io/docs/autoprovisioning/) currently list
20 free checks; actual account limits/notification delivery must be checked at
enrollment. Sender behavior follows the [HTTPS ping API](https://healthchecks.io/docs/http_api/)
and documented [state/grace contract](https://healthchecks.io/docs/).

## Historical exit-127 rows checked at operator request

These are abandoned startup attempts for a later-successful fix, not outstanding
implementation failures. Actual startup log output:

```text
vectordb-retrieval-key-cache:
env: codex: No such file or directory

vectordb-retrieval-key-cache-retry:
env: node: No such file or directory
```

Ledger evidence: first attempt exited 127 at 2026-10-26T23:36:38Z and was
abandoned at 23:36:56Z; first retry exited 127 at 23:37:14Z and was abandoned at
23:37:25Z. Retry2 exited 0 at 23:38:59Z and landed with passed tests at 23:40:00Z
as 8237c54d92af251584b29821d00d0af0a660f434, confirmed in remote release ancestry.
The later product-catalog critical alert matches the application/condition
recorded in the selected GHCR bug; its text alone does not prove the current
credential failure. No duplicate bug was filed.

## Live-column audit recovery

The staged audit correctly noticed replacement of the old assertion forbidding
source verification in the single-column query:

```text
WARN: Agent audit: assertions removed from Python test files (add '# agent-audit: allow assert-removed <reason>' on an added line in that file if intended):
WARN: scripts/tests/bin/test_vectordb_bug_metrics.py:
-    assert 'label_replace' in query and '\"verification\"' not in query
```

The new explicit column scope requires reading that source field. Two projection
assertions and exact-label Prometheus fixtures replace the obsolete ban. Added
`# agent-audit: allow assert-removed replace single-column ban with projection checks and exact raw-label fixtures`
at the replacement. Audit passed afterward; no hook was skipped and no raw
verification is inferred or changed.

## Offline results

Only dashboard YAML, tests, guide and changelog change in these two fixes.
ShellCheck passed for the touched BATS; no plugin shell code was changed.
Staged audit/lint/doc-link/diff gates passed. Promtool 3.2.1 under /tmp executes
the actual query tests; neither engine case was skipped in coordinator gates.
The full VectorDB and dashboard BATS outputs below are post-rebase dispatcher
gates. Pre-fix checks temporarily restored the original panel in exited worker
worktrees and restored fixed bytes in finally blocks; no live APIs were used.

## Probe-age pre-fix regression

```text
1..1
not ok 1 retrieval probe age panel keeps a daily probe green and matches the stale alert boundary
# (in test file scripts/tests/plugins/vectordb_rules.bats, line 250)
#   `[ "${status}" -eq 0 ]' failed
```

## Probe-age dispatcher landing

```text
scope: in-scope
target moved: +1 commits since dispatch (0510c5d3c08db913b25e8d197925322405909205..5dae466f2a8741e5b3595675fea5d82dbdae7b5f)
Rebasing (1/1)
Successfully rebased and updated refs/heads/task/v1.43.9/vectordb-probe-age-thresholds-luna.
tests: passed
landed: vectordb-probe-age-thresholds-luna
push: git -C /Users/cliang/src/gitrepo/personal/k3d-manager push origin k3d-manager-v1.43.9
```

## Probe-age post-rebase gates

```text
1..18
ok 1 vectordb rules target the hub prometheus stack
ok 2 vectordb alerts are present
ok 3 automatic indexing alerts use the requested windows
ok 4 drift alert uses kind counts and first-seen age
ok 5 drift dashboard panels show kind counts and oldest age without overlaps
ok 6 VectorDBMetricsStale watches push age, not absence alone
ok 7 VectorDBMetricsStale still covers the never-published case
ok 8 absence alone is not the whole staleness expression
ok 9 VectorDBIndexStale keeps the seven-day index threshold
ok 10 dashboard has six ingestion panels using emitted metrics
ok 11 rows and corpus panel formats document counts as whole documents
ok 12 rows and corpus remain distinguishable when their values overlap
ok 13 vectordb dashboard is no longer in the app-cluster dashboard folder
ok 14 every rule keeps string labels and its own annotations
ok 15 dashboard has four ordered rows and unique panel ids
ok 16 retrieval alerts use the specified expressions and windows
ok 17 retrieval probe age panel keeps a daily probe green and matches the stale alert boundary
ok 18 existing dashboard panel queries and presentation are unchanged
```

## Live-column post-rebase gates

```text
........................................................................ [ 64%]
.......................................                                  [100%]
111 passed in 10.80s
All checks passed!
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
ok 38 Plans table separates verified and live-verified status indicators
```

## Live-column dispatcher landing

```text
scope: in-scope
target moved: +2 commits since dispatch (0510c5d3c08db913b25e8d197925322405909205..74d2d4e2054aa52a162525fe0456df30ac5cd7d3)
Rebasing (1/1)
Successfully rebased and updated refs/heads/task/v1.43.9/plans-live-verification-column-luna.
tests: passed
landed: plans-live-verification-column-luna
push: git -C /Users/cliang/src/gitrepo/personal/k3d-manager push origin k3d-manager-v1.43.9
```

## Live-column pre-fix actual-query regression

```text
scripts/tests/bin/test_vectordb_bug_metrics.py:290: AssertionError
=========================== short test summary info ============================
FAILED scripts/tests/bin/test_vectordb_bug_metrics.py::test_release_plans_query_evaluates_lifecycle_fixtures[0]
FAILED scripts/tests/bin/test_vectordb_bug_metrics.py::test_release_plans_query_evaluates_lifecycle_fixtures[1]
2 failed, 109 deselected in 0.73s
```

Live check 1 is the only current operator question: refresh VectorDB Health
after normal dashboard sync and report green for an age under 24 hours. No
forced retrieval probe. Hold all later live checks until that evidence is
resolved. No PR created.

## Operator live checks 1 and 2 — accepted 2026-10-27

1. Probe-age E2 passed: refreshed VectorDB Health shows **11.6 hours green**,
   below the daily threshold. [Screenshot](../assets/2026-10-27-probe-age-green-live.png).
   Fix: `74d2d4e2054aa52a162525fe0456df30ac5cd7d3`. No forced probe was requested.
2. Plans E2 passed: v1.43.9 unknown/n/a rows show dashes in both indicators
   ([screenshot](../assets/2026-10-27-plans-unknown-live.png)); Manual v1.43.8
   shows two rows checked in both Verified and Live verified, two implemented-only
   rows with dashes, and the summary Live-verified count is 2
   ([screenshot](../assets/2026-10-27-plans-positive-live.png)).
   Fix: `9893651f4fd4127db692bf2d1743e070a7683284`.

Both canonical bugs are now LIVE-VERIFIED. Remaining live checks stay queued
until independent review of their implementations completes. GHCR and heartbeat
workers were resumed with concrete review findings and the Luna wrapper; the
webhook doctor worker has completed and awaits independent review. No assistant
live deployment/restart was performed.

## Remaining-task independent review and landings — 2026-10-27

All four workers exited successfully before final independent review. Worker
exit alone was not accepted as completion. GHCR landed/pushed `0cd39eb8`;
heartbeat landed/pushed `79bd9eb5` plus CLI permissions `233a4b11`; doctor
landed/pushed `e4f6823e`. Dispatcher verify pass recorded for all three.
Coordinator correction resume remains pending.

Review findings corrected before acceptance:
- GHCR: real curl HEAD stdout, HTTP404 digest rejection, bounded transport
  timeouts, per-service metric replacement/clearing. Real-curl fixture passed.
- Heartbeat: dry-run side effects, deceptive URLs/redirects, role separation,
  per-entry failures, locks across attempts, interpreter/path handling and
  producer fixtures. Documented direct commands originally lacked executable
  bits; corrected them and added a direct CLI BATS check (3/3 passed).
- Doctor: quick mode, redirect/proxy protection, diagnostic unknown states and
  body/command bounds; regression reproduced an additional production-path
  crash before fixing the dictionary contract:

```text
AttributeError: 'dict' object has no attribute 'returncode'
```

Doctor also rejected malformed service rows lacking ok instead of raising
KeyError. No real Keychain values were accessed by the review/tests.

Container compatibility used cached public image IDs
`sha256:6d56ed8aeae1c994932c5c4461193e48dc1b39ba02986fad799167a92b4c885b`
(alpine/k8s:1.31.4) and
`sha256:c686ab04db37acf145f52e19190fd737ec913c486c770b78107b84f4594cd93c`
(trivy:0.63.0), UID/GID65534 and **--network none**, without credentials or
cluster mounts. All shell tools/curl/kubectl were present and /tmp writable.
The init-image copy into a temporary tools mount succeeded; the copied Trivy
binary ran inside alpine/k8s and printed:

```text
Version: 0.63.0
```

The isolated heartbeat rebase hit a CHANGELOG-only conflict:

```text
error: could not apply 817c34bd... checkpoint: before reviewed-independent-heartbeats
[codex-dispatch] ERROR: rebase of task/v1.43.9/independent-heartbeats-luna onto k3d-manager-v1.43.9 failed; resolve it in /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/independent-heartbeats-luna
```

Retained both release entries, continued the isolated rebase, then repeated
dispatcher landing and its tests successfully. No shared-branch rewrite.

The earlier sandboxed status falsely showed workers terminated because ps was
restricted; an approved read-only process check confirmed all were running at
that time. Later actual exits were checked with permitted process visibility.

### Actual independent focused gate output

ghcr-candidate-auth-diagnostics-luna:

```text
1..36
ok 1 all-skipped run exits 1 with the fatal zero-match diagnostic
ok 2 vulnerable deployed image with vulnerable latest dispatches rebuild instead of promotion
ok 3 rebuild dispatched within the cooldown is skipped without notifying
ok 4 rebuild dispatched after the cooldown expires dispatches and records the time
ok 5 vulnerable deployed image with clean latest promotes exact digest via application patch
ok 6 COSIGN_VERIFY=1: signed clean candidate is cosign-verified then promoted
ok 7 COSIGN_VERIFY=1: unsigned clean candidate is refused (no promotion)
ok 8 COSIGN_VERIFY_ATTESTATION=1: signed + attested clean candidate is promoted
ok 9 COSIGN_VERIFY_ATTESTATION=1: signed but unattested candidate is refused (no promotion)
ok 10 registry-less trivy-operator repository form still matches and promotes
ok 11 digest resolution reads busybox-style indented lowercase headers
ok 12 clean frontend image is scanned and skipped
ok 13 clean payment image is scanned and skipped
ok 14 missing immutable candidate notifies without failing the batch
ok 15 rebuild dispatch failure notifies without failing the batch
ok 16 missing immutable sha candidate notifies without retrying the batch
ok 17 GHCR credential failure is classified and reported without exposing the token
ok 18 latest without a digest is classified no-latest
ok 19 unavailable tags endpoint is not classified as a genuine no-match
ok 20 manifest 404 is rejected even when it includes a digest header
ok 21 manifest 401 with GH_TOKEN is classified auth instead of no-match
ok 22 tags list 401 with GH_TOKEN is classified auth instead of no-match
ok 23 registry transport keeps credentials in a private curl config and scanner image contract is pinned
ok 24 candidate metric groups preserve two services and replace auth with ok per service
ok 25 real curl HEAD returns only the status and writes digest headers separately
ok 26 app_cve_scan_trigger rejects an unsupported cronjob name
ok 27 app_cve_scan_trigger fails when the cronjob is absent
ok 28 app_cve_scan_trigger creates a job from the cronjob
ok 29 app_cve_scan_trigger defaults to app-cve-scan with no argument
ok 30 app_cve_scan_trigger returns non-zero when the wait times out
ok 31 app_cve_scan_trigger honours K3DM_CVE_SCAN_WAIT
ok 32 missing Application logs a failed promotion and returns zero
ok 33 missing Application emits no remediation event
ok 34 successful Application patch emits one remediation event
ok 35 git-persisted promotion clears the live image override
ok 36 live-patch-only promotion keeps the live image override
```

independent-heartbeats-luna:

```text
........................................................................ [ 52%]
................................................................         [100%]
136 passed in 4.77s
1..2
ok 1 heartbeat: dry run renders intent without provider calls
ok 2 heartbeat: templates contain no enrolled endpoint
All checks passed!
```

webhook-incident-doctor-luna:

```text
.....................                                                    [100%]
21 passed in 0.41s
1..5
ok 1 restart-webhook reloads the plist with bootout then bootstrap, never kickstarting the webhook
ok 2 restart-webhook continues to bootstrap when bootout reports the job is not loaded
ok 3 restart-webhook still restarts the cloud bridge
ok 4 restart-webhook retries bootstrap twice then reports success
ok 5 restart-webhook fails after five bootstrap attempts and skips cloud bridge
All checks passed!
{"mode": "dry-run", "probes": ["launchd job state and last exit code", "webhook process PID", "TCP/9000 listener", "bounded redacted log summary", "reader-authenticated loopback /api/v1/health?quick=1"], "recovery": "No recovery is performed. Operator may run make restart-webhook once only when local evidence warrants it; it also restarts cloud-bridge.", "timestamp_utc": "2026-10-27T11:56:55.604707+00:00"}
```

Additional heartbeat direct-command BATS:

```text
1..3
ok 1 heartbeat: dry run renders intent without provider calls
ok 2 heartbeat: templates contain no enrolled endpoint
ok 3 heartbeat: documented commands execute directly
```

ShellCheck on GHCR scanner: clean (exit0). Heartbeat/doctor production code
is Python; Ruff clean. All three staged _agent_lint/_agent_audit passed
(exit0), normal hooks enabled. Curated `test all` is still running; no final
claim for that gate yet. Live credentials, provider enrollment, deployment,
alerts and original incident recovery remain unverified.
