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

## Curated regression findings — follow-up in progress

The full curated run (`1..1895`) found these repository-wide guards:

```text
not ok 63 no bare '! cmd' assertions in BATS suites (set -e ignores them)
# (in test file scripts/tests/lib/bats_negation_lint.bats, line 6)
#   `[ "$status" -ne 0 ]' failed
not ok 130 grep-q guard: no non-allowlisted pipeline retains -q
# (in test file scripts/tests/lib/grep_q_pipe_guard.bats, line 13)
#   `[ "$status" -eq 1 ]' failed
```

Bare-negation violations were introduced by the batch in heartbeat/CVE BATS.
Replaced them with run+explicit status assertions. Review also found two token
checks concatenated log filenames into one nonexistent path, hiding grep errors;
corrected to separate existing files and require status1 (no match), not status2.
A first partial guard rerun still failed because CVE bare-negation assertions
remained; final affected-suite rerun is captured below once complete.

The grep-q guard's actual remaining match is unrelated existing code:

```text
bin/k3dm-orbstack-upgrade:168:forecast_ok=0; curl -fsS "$PUSHGATEWAY_URL/metrics" | grep -q '^k3dm_release_forecast' && forecast_ok=1
```

Confirmed the same line with `git show adf2af4e:bin/k3dm-orbstack-upgrade`,
before these three landings. Last file commit:

```text
2a729c11 feat(orbstack): coordinated upgrade with preflight, recovery and report
```

Recorded as out-of-scope follow-up; did not silently modify the OrbStack task.
The full curated run is not claimed green.

### Final affected BATS guard rerun

```text
1..29
ok 1 no bare '! cmd' assertions in BATS suites (set -e ignores them)
ok 2 heartbeat: dry run renders intent without provider calls
ok 3 heartbeat: templates contain no enrolled endpoint
ok 4 heartbeat: documented commands execute directly
ok 5 all-skipped run exits 1 with the fatal zero-match diagnostic
ok 6 vulnerable deployed image with vulnerable latest dispatches rebuild instead of promotion
ok 7 rebuild dispatched within the cooldown is skipped without notifying
ok 8 rebuild dispatched after the cooldown expires dispatches and records the time
ok 9 vulnerable deployed image with clean latest promotes exact digest via application patch
ok 10 COSIGN_VERIFY=1: signed clean candidate is cosign-verified then promoted
ok 11 COSIGN_VERIFY=1: unsigned clean candidate is refused (no promotion)
ok 12 COSIGN_VERIFY_ATTESTATION=1: signed + attested clean candidate is promoted
ok 13 COSIGN_VERIFY_ATTESTATION=1: signed but unattested candidate is refused (no promotion)
ok 14 registry-less trivy-operator repository form still matches and promotes
ok 15 digest resolution reads busybox-style indented lowercase headers
ok 16 clean frontend image is scanned and skipped
ok 17 clean payment image is scanned and skipped
ok 18 missing immutable candidate notifies without failing the batch
ok 19 rebuild dispatch failure notifies without failing the batch
ok 20 missing immutable sha candidate notifies without retrying the batch
ok 21 GHCR credential failure is classified and reported without exposing the token
ok 22 latest without a digest is classified no-latest
ok 23 unavailable tags endpoint is not classified as a genuine no-match
ok 24 manifest 404 is rejected even when it includes a digest header
ok 25 manifest 401 with GH_TOKEN is classified auth instead of no-match
ok 26 tags list 401 with GH_TOKEN is classified auth instead of no-match
ok 27 registry transport keeps credentials in a private curl config and scanner image contract is pinned
ok 28 candidate metric groups preserve two services and replace auth with ok per service
ok 29 real curl HEAD returns only the status and writes digest headers separately

```

Plain ShellCheck on the BATS file reported its existing SC2030/SC2031
BATS-subshell info diagnostics and SC2016 quoted-fixture info. The repository
warning-level gate `shellcheck -S warning scripts/tests/bin/heartbeat.bats
scripts/tests/plugins/app_cve_scan.bats` passed with no output (exit0).
Production scanner ShellCheck remains clean at default severity. These
BATS info findings do not indicate shared variable changes across test cases.

## Completed broad regression run (before final coordinator landing)

`./scripts/k3d-manager test all`: **1895 total; 1869 passed, 19 skipped,
7 failed**. TAP reports 1888 ok including skips. It is not a green gate.
[Full verbatim output](../assets/2026-10-27-six-bug-curated-tests.txt).

All failure output:

```text
not ok 63 no bare '! cmd' assertions in BATS suites (set -e ignores them)
# (in test file scripts/tests/lib/bats_negation_lint.bats, line 6)
#   `[ "$status" -ne 0 ]' failed
not ok 130 grep-q guard: no non-allowlisted pipeline retains -q
# (in test file scripts/tests/lib/grep_q_pipe_guard.bats, line 13)
#   `[ "$status" -eq 1 ]' failed
not ok 470 smoke test ESO wiring samples app and hub through helper
# (in test file scripts/tests/lib/webhook_hub_eso.bats, line 155)
#   `[ "$status" -eq 0 ]' failed
not ok 1261 recover B4-20: refused preflight prevents hub-recover
# (in test file scripts/tests/plugins/hub_data.bats, line 929)
#   `cp -R "$PWD" "$copy"' failed
# cp: cannot create special file '/tmp/bats-run-SPTKOs/test/1261/root/repo/-e': Operation not permitted
not ok 1272 recover B4-21: teardown precedes rebuild and resume
# (in test file scripts/tests/plugins/hub_data.bats, line 1070)
#   `chmod +x "$script" "$fake_make"; cp -R "$PWD" "$copy"; cp "$script" "$copy/scripts/k3d-manager"' failed
# cp: cannot create special file '/tmp/bats-run-SPTKOs/test/1272/root/repo/-e': Operation not permitted
not ok 1274 recover B4-22: teardown failure prevents rebuild and resume
# (in test file scripts/tests/plugins/hub_data.bats, line 1095)
#   `chmod +x "$script"; cp -R "$PWD" "$copy"; cp "$script" "$copy/scripts/k3d-manager"' failed
# cp: cannot create special file '/tmp/bats-run-SPTKOs/test/1274/root/repo/-e': Operation not permitted
not ok 1275 recover B4-23: keychain preflight refusal stops hub-recover-all before teardown
# (in test file scripts/tests/plugins/hub_data.bats, line 1113)
#   `chmod +x "$script"; cp -R "$PWD" "$copy"; cp "$script" "$copy/scripts/k3d-manager"' failed
# cp: cannot create special file '/tmp/bats-run-SPTKOs/test/1275/root/repo/-e': Operation not permitted
```

The batch's bare-negation defect was corrected and the affected suites plus
negation guard subsequently passed 29/29 (output above). The remaining six
failures are unchanged out-of-scope issues: OrbStack pipeline guard, one
Python3.15 ESO loader test, and four recursive-copy fixtures encountering the
operator's pre-existing Unix socket ./-e. Separate issue docs retain the cause
and recommendation. No socket was deleted or unrelated implementation changed.

The run also emitted BW02 for existing e2e_sandbox_preflight.bats line372
missing bats_require_minimum_version before run flags; full warning and all19
skips are retained in the full output. No live tests were substituted for
skipped/offline fixtures. Do not infer a clean whole-repository test gate
from the green scoped implementation checks.

## Final coordinator acceptance and batch implementation closeout

Coordinator landed `9424c32a9f0032797c7c803a9a7fc3d1d1651ab5` through dispatcher, after independent review and
full post-rebase gates. The only snapshot scope exception was
`scripts/tests/plugins/agent_dispatch_dashboard.bats`, explicitly documented
in the canonical bug before landing. All13 changed files were reviewed.
Luna corrections covered visible numeric columns, missing-vs-zero cost,
normalized metric deduplication, metadata validation before task side effects,
repeated handoffs, human landing, provenance and review-pending fixtures.
Staged audit/lint passed; legitimate assertion replacements for normalized
models/new columns were reported under the existing assertion-replacement
marker; no hook bypass. New helpers remained within the audit threshold.

The first coordinator landing encountered a CHANGELOG-only rebase conflict:

```text
error: could not apply 520d5604... checkpoint: before reviewed-primary-coordinator-handoffs
[codex-dispatch] ERROR: rebase of task/v1.43.9/primary-coordinator-handoffs-luna onto k3d-manager-v1.43.9 failed; resolve it in /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/primary-coordinator-handoffs-luna
```

Resolved on its isolated branch by retaining both independent additions, then
reran dispatcher land successfully. No shared branch rewrite.

### Actual full post-rebase coordinator gate output

```text
........................................................................ [ 52%]
................................................................         [100%]
136 passed in 12.50s
1..124
ok 1 codex dispatch: explicit primary, handoff, and landing actor are separate ledger facts
ok 2 codex dispatch: omitted primary stays unknown and invalid handoff reason is rejected
ok 3 codex dispatch: primary identity retains runtime-reported provenance
ok 4 codex dispatch: invalid primary and handoff identity or provenance do not append
ok 5 codex dispatch: start records spec size snapshot
ok 6 codex dispatch: spec stats failure does not block dispatch or add a field
ok 7 codex dispatch: land records commit and categorized change size
ok 8 codex dispatch: numstat failure does not block land or record change size
ok 9 codex dispatch: agy runs in its worktree with default model and ledger identity
ok 10 codex dispatch: uncommitted agy work can be reviewed and landed
ok 11 codex dispatch: unknown agy model fails before worktree creation
ok 12 codex dispatch: agy model matching uses only exact model IDs
ok 13 codex dispatch: explicit agy and Codex models are recorded and passed
ok 14 codex dispatch: missing agy usage is recorded as null without token counts
ok 15 codex dispatch: agy commit is a scope violation and cannot land
ok 16 codex dispatch: default Codex command is unchanged and start identity is explicit
ok 17 codex dispatch: runtime model is recorded for each attempt without copying other log text
ok 18 codex dispatch: invalid runtime model and coordinator are rejected safely
ok 19 codex dispatch: declared coordinator is recorded on start
ok 20 codex dispatch: agy resume requires and uses its stored conversation
ok 21 codex dispatch: network is refused for agy
ok 22 codex dispatch: only one same-spec slug lands without explicit superseding
ok 23 codex dispatch: start refuses a non-release branch
ok 24 codex dispatch: start refuses changed spec and ahead HEAD
ok 25 codex dispatch: start isolates operator checkout
ok 26 codex dispatch: start records the spec path in the ledger
ok 27 codex dispatch: piped start returns before Codex exits
ok 28 codex dispatch: detached worker survives launcher SIGHUP
ok 29 codex dispatch: detached worker survives launcher process-group SIGKILL
ok 30 codex dispatch: plain background worker is killed by launcher group
ok 31 codex dispatch: records nonzero Codex exit before bookkeeping
ok 32 codex dispatch: missing Codex is a terminal nonzero exit
ok 33 codex dispatch: bookkeeping failure does not hide the exit
ok 34 codex dispatch: land completes when the ledger is unwritable
ok 35 codex dispatch: a killed worker is unexpectedly terminated
ok 36 codex dispatch: a reused PID identity is not reported running
ok 37 codex dispatch: parallel starts isolate each edit
ok 38 codex dispatch: argv has sandbox worktree and run dir
ok 39 codex dispatch: state is isolated and HOME is unchanged
ok 40 codex dispatch: status marks memory-bank changes out of scope
ok 41 codex dispatch: land refuses running, out-of-scope, and dirty tasks
ok 42 codex dispatch: land refuses a dirty operator checkout
ok 43 codex dispatch: land fast-forwards without pushing
ok 44 codex dispatch: abandon without yes changes nothing
ok 45 codex dispatch: prune removes landed current and earlier release tasks and branch-only leftovers
ok 46 codex dispatch: prune keeps unsafe tasks and preserves run research data
ok 47 codex dispatch: prune rejects unknown options
ok 48 codex dispatch: scope uses the recorded spec, not a root markdown file
ok 49 codex dispatch: memory-bank is out of scope even when the spec lists it
ok 50 codex dispatch: edited spec cannot widen scope
ok 51 codex dispatch: records the release base at start
ok 52 codex dispatch: scope ignores commits pushed after dispatch
ok 53 codex dispatch: land refuses a missing recorded base
ok 54 codex dispatch: tests the rebased task before merging
ok 55 codex dispatch: land --no-test says the tests were skipped
ok 56 codex dispatch: cross-repo start snapshots the spec and land targets only the named branch
ok 57 codex dispatch: cross-repo start rejects incomplete and protected targets
ok 58 codex dispatch: cross-repo scope uses the saved spec and refuses memory-bank
ok 59 codex dispatch: cross-repo land refuses target rewritten since dispatch
ok 60 codex dispatch: cross-repo land refuses a different target checkout and local divergence
ok 61 codex dispatch: cross-repo land records a forward target move and catches movement during tests
ok 62 codex dispatch: land requires exactly one test selector
ok 63 codex dispatch: land test command sees isolated state
ok 64 codex dispatch: landing lock is released after refusal
ok 65 codex dispatch: network tasks are exclusive
ok 66 codex dispatch: resume continues the same session
ok 67 codex dispatch: resume accepts a dead worker whose PID identity is stale
ok 68 codex dispatch: resume passes the state root and runs in the worktree
ok 69 codex dispatch: resume refuses a landed task and a log without a session id
ok 70 codex dispatch: a refused networked resume leaves the task finished
ok 71 codex dispatch: ledger snapshots Codex output and restores the index
ok 72 codex dispatch: verify records pass tokens only for a landed task
ok 73 codex dispatch: verify refusals do not append ledger events
ok 74 codex dispatch: ledger records verifier lines before a release rebase
ok 75 codex dispatch: ledger records scope refusal and valid JSON
ok 76 codex dispatch: resume records the latest token total
ok 77 codex dispatch: ledger records a Codex exit with no token count
ok 78 codex dispatch: start records session token usage from CODEX_HOME
ok 79 codex dispatch: missing session usage warns but start succeeds
ok 80 codex dispatch: usage-backfill is idempotent
ok 81 codex dispatch: intervention records reason and starts explicit coverage once
ok 82 codex dispatch: intervention refuses unknown task invalid reason and worker self-report
ok 83 codex dispatch: metrics scheduling coalesces concurrent requests and preserves the last request
ok 84 codex dispatch: metrics scheduling takes stale lock and respects fresh lock
ok 85 codex dispatch: make codex-dispatch passes --branch only when BRANCH is given
ok 86 codex dispatch: make targets pass a declared coordinator
ok 87 codex dispatch: release-merged records one merge timestamp idempotently
ok 88 codex dispatch: invalid release-merged args leave ledger unchanged
ok 89 commits with the spec's message, lands, pushes and marks the spec review pending
ok 90 never marks a task verified or fixed
ok 91 refuses a task that has not exited successfully, before committing or landing
ok 92 refuses when the checkout is not on a release branch
ok 93 refuses a dirty main checkout
ok 94 refuses a spec with no commit line
ok 95 requires --test
ok 96 rejects invalid landing metadata and missing values before task side effects
ok 97 reads the 'Commit message:' form too
ok 98 agent dispatch dashboard: valid ConfigMap JSON and datasource
ok 99 agent dispatch dashboard: every queried metric is exported
ok 100 agent dispatch dashboard: Claude context and compaction row panels exist below existing rows
ok 101 agent dispatch dashboard: landing success aggregates both sides
ok 102 agent dispatch dashboard: panel rectangles do not overlap
ok 103 agent dispatch dashboard: Codex API cost shows priced total and excluded sessions
ok 104 agent dispatch dashboard: per-spec panels use readable units and grouped targets
ok 105 agent dispatch dashboard: final exit gap and operator coverage are exposed
ok 106 agent dispatch dashboard: window is a query over the exported scopes and defaults to 7d
ok 107 agent dispatch dashboard: rework rate stat reads the selected window
ok 108 agent dispatch dashboard: verified delivery stats use exported metrics without overlap
ok 109 agent dispatch dashboard: stat and bar gauge panels use explicit colours
ok 110 agent dashboards: panel ids exactly match the pre-split dashboard and assigned groups
ok 111 agent dashboards: panel targets, fieldConfig and options match the pre-split fixture
ok 112 agent dashboards: each dashboard has unique panel ids and no overlapping rectangles
ok 113 agent dashboards: all dashboards have the tag-based Agents link
ok 114 agent dashboards: Activity has three time windows and Dispatch and Cost keep the query variable
ok 115 agent activity: Claude row fills the width and bar gauge names read beside each bar
ok 116 agent dispatch: run outcomes read beside each bar, first-pass verification bars with fixed fonts sit beside per run evidence, and each slug links to its spec
ok 117 agent dispatch: per spec shows which agent landed each spec
ok 118 agent dispatch dashboard: Log opens the filtered run log dashboard
ok 119 agent cost: Claude tokens by kind splits the selected window by cache kind
ok 120 agent cost: daily Claude tokens and cost panels split by kind
ok 121 agent dashboards: labels and titles stay readable and release-only stats say why they are empty
ok 122 agent dispatch dashboard: Per spec exposes unknown worker and coordinator identities
ok 123 agent dispatch dashboard: Per spec shows handoff and measured cost fields within width budget
ok 124 agent dispatch dashboard: Per spec spans the full width and its columns fit without scrolling
All checks passed!
```

ShellCheck command was `shellcheck -x -S warning bin/k3dm-codex-dispatch
bin/k3dm-codex-land-pending`; clean exit0. Ruff printed All checks passed.
Final dispatcher test result passed; independent verify pass recorded.

### Current state (supersedes earlier running/queued notes)

| Selected item | Implementation | Live evidence |
|---|---|---|
| Probe-age colors |74d2d4e2, independently verified/landed/pushed|LIVE-VERIFIED, operator11.6h green|
| Plans Live verified column |9893651f, independently verified/landed/pushed|LIVE-VERIFIED, positive/unknown screenshots|
| GHCR diagnostics/transport |0cd39eb8 plus assertion fix78073617, independently verified/landed/pushed|Pending operator credential/remediation check|
| Independent heartbeats |79bd9eb5/233a4b11 plus assertion fix78073617, independently verified/landed/pushed|Pending enrollment and controlled failure/recovery alerts|
| Primary coordinator/handoffs |9424c32a, independently verified/landed; push follows this record|Pending operator E3|
| Webhook doctor |e4f6823e, independently verified/landed/pushed|Next live check3: operator `bin/k3dm-webhook-doctor --check`; no recovery until result reviewed|

All six implementation deliverables are accepted. This is not a claim that
all six underlying bugs are live-resolved: two are LIVE-VERIFIED, three are
VERIFIED offline, and the original webhook incident remains OPEN although its
diagnostic deliverable is verified. The full curated gate remains non-green
for the explicitly recorded unrelated failures; the introduced assertion
issue is corrected and affected29 tests pass. No deployment, enrollment,
credential rotation or assistant-run live diagnosis was performed.

Separate new ask-docs routing and startup Log-link bugs are filed OPEN; they
were not part of the selected six and were not silently implemented here.

## Operator live check3 — current webhook/Slack passed

Corrected doctor local health is healthy on7443; operator Slack job
`a13d5831` queued/started/succeeded with returned fix list in the same thread.
Screenshot/full details: `docs/issues/2026-10-27-webhook-doctor-live-port-mismatch.md`.
No restart warranted/performed. This confirms the current local/Slack path,
not the historical outage cause, operator credential context or a separate
cloud-bridge probe. Historical incident remains OPEN; bounded diagnostic
deliverable/current functional verification passed.

Next live item4 is GHCR; start by inspecting deployed scanner image read-only,
then choose rollout/diagnostic steps based on observed state. Do not rotate
credentials blindly or trigger a scan before prerequisites are reviewed.

## GHCR live check4 — deployment prerequisite pending

Operator main-container image read returned aquasec/trivy:0.63.0, exit0.
The accepted main image alpine/k8s:1.31.4 is not deployed. This is partial
verification, not a failed corrected-scanner run. Exact output and rollout
command source review: docs/issues/2026-10-27-ghcr-live-check-old-scanner-image.md.
Next user step only make platform-ops; no assistant rollout, blind credential
rotation or scan trigger. All subsequent live checks remain queued.

## GHCR operator runtime result — partial, rejected dedicated PAT

Job app-cve-scan-manual-1793141593 completed, new log product-catalog
reason=auth/promotion skipped and per-service metric auth=1. Historical
promotion records do not show new remediation. Dedicated local PAT retrievable
(exit0), but GHCR token403 and GitHub auth401. Needs operator-owned credential
replacement; no source/registry/cluster credential values disclosed. Email/
PagerDuty notices skipped for missing config. Success path still pending.
Full output docs/issues/2026-10-27-webhook-doctor-make-target-and-ghcr-live-auth.md.

User-requested make webhook-doctor /DRY_RUN=1 wrapper47b4d740 implemented,
help/docs updated, Make expansions/real plan/5 adjacent BATS and hooks pass.
Only next operator credential replacement step requested; no second scan
started, no broad gh token reused, no credential rotated by coordinator.

## GHCR live auth recovery passed; new scan-gate issue outside batch

Operator1793149530 new scan resolves candidate, reasonauth->ok metric replacement,
Git pin e35525bc persisted, ArgoSynced/Healthy/Succeeded, runningpod1/1 at target
digest. Auth P2 LIVE-VERIFIED with E3 evidence. Fresh report0Critical/4HIGH
with fixes: do NOT call image clean. Independent no-network Trivy-error
fixture reports scan_count0 despite failure; same pre-batch helper logic.
New bounded P2 scan-gate spec filed, no implementation/dispatch authorization
inferred and no cause of exact live discrepancy asserted. Full outputs
docs/issues/2026-10-27-app-cve-scan-auth-recovery-and-gate-followup.md.
Operator scope choice pending before new fix; remaining live items queued.
