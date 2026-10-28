# Bug: test-all has four failing BATS cases and stops before completing the offline suite

**Filed:** 2026-10-28 (operator screenshot of Grafana Offline Tests dashboard and Alertmanager emails)
**Priority:** P2 — offline test gate failing and incomplete; security guard failure requires inspection
**Severity:** medium — confidence in test gate reduced; no established production or Hostinger outage
**Status:** OPEN — scoped fixes independently verified and pushed; fresh complete three-stage test-all and published metrics acceptance pending
**Release:** v1.43.9 bug (does not consume an enhancement plan slot)
**Branch:** `k3d-manager-v1.43.9`
**Approval:** operator 2026-10-28 explicitly requested review/dispatch to Luna; isolated focused implementation/testing authorized, full published rerun and live deployment remain operator-owned
**Component:** `scripts/tests/lib/grep_q_pipe_guard.bats`, `scripts/tests/plugins/e2e_remote.bats`, `scripts/plugins/e2e_remote.sh`, offline test metrics/Alertmanager
**Related:** `docs/bugs/2026-10-17-grep-q-pipeline-sigpipe-false-absent.md`, `docs/bugs/2026-10-10-offline-suite-count-floor-stale-and-partial-runs.md`, `docs/plans/v1.44.2-cloud-bridge-offline-test-run-diagnostics.md`

## Evidence / symptom

The operator's 2026-10-28 Grafana screenshot shows `Failed cases = 4` and three visible BATS failure entries for target `test-all`:
- case 130: `grep-q guard: no non-allowlisted pipeline retains -q` — `[ "$status" -eq 1 ] failed`.
- case 1015: `dispatch refuses and never falls back locally when the lock is held` — expected output containing `busy` absent.
- case 1016: `dispatch chains publish-back after the E2E and preserves the exit code` — `[ "$status" -eq 0 ] failed`.
- Follow-up Prometheus read and operator screenshot identify case 1194: `PR check duration legend uses a readable side layout without changing its query` — `table = next(panel for panel in data["panels"] if panel["id"] == 6)` failed. The historical checkout/raw log is still unavailable; current isolated and curated checks pass.

Alertmanager's firing email on 2026-10-28 13:21 UTC reported `OfflineSuiteFailing`, `target=test-all`, instance `test-all-local`, with **4 offline test case(s) failing**, and a simultaneous `OfflineSuiteRunIncomplete` email. Both alert rules use `for: 30m`; Pushgateway retains the most recently published values, so firing does not prove ongoing test execution.

`OfflineSuiteRunIncomplete` records absent completion markers for expected stages; these BATS failures can explain a downstream stage not executing, but the stage-completion log has not been retrieved.

## Static investigation findings (hypotheses, not live root causes)

### H1. grep-q guard (case 130)

`scripts/tests/lib/grep_q_pipe_guard.bats` executes a repository scan for `| grep -q` patterns in scripts/bin, excluding tests/foundation/node_modules, then excludes allowlisted lines. The assertion expects grep's exit 1 (no results). The screenshot indicates it instead received another status, but does not show the emitted match or any stderr. Possible causes include a newly introduced forbidden pipeline, stale allowlist, or scanning behavior. Capture the scanner's exact stdout/stderr and exit code **before changing code or relaxing the assertion**. If a real pipefail/SIGPIPE hazard is found, fix the implementation and keep a mutation-red guard.

### H2. E2E dispatcher tests (cases 1015–1016)

Both tests in `scripts/tests/plugins/e2e_remote.bats` stub `e2e_runner_preflight()`, `_e2e_remote_lock_acquire()` and `ssh()` and invoke `e2e_runner_dispatch "m2"`. However `scripts/plugins/e2e_remote.sh` runs these prerequisites **before** lock acquisition or SSH:
- `_e2e_remote_load_conf`
- `_e2e_runner_allowed`, digest and repository URL checks
- `git -C "$REPO_ROOT" rev-parse HEAD` and `git branch -r --contains "$sha"` (requires pushed HEAD)
- `_e2e_remote_preflight_with_retry` (the test stubs a different function)

Thus the tests may fail at preconditions before exercising the named behavior; case 1015 would not see `busy`, case 1016 would not reach its fake SSH or return 0. Determine which guard actually failed from captured `$output`, and avoid weakening real dispatch preconditions. Update tests to stub the true dependency boundary (or use a verified fixture repository and stubbed preflight), while retaining negative assertions that no remote execution or local fallback occurs on a busy lock.

The existing `_e2e_remote_lock_acquire` failure path attempts a read-only owner metadata lookup before reporting `busy`; the test's SSH stub alone may not intercept `_e2e_remote_ssh`. Verify the failure path with explicit spies.

**Do not assume these are all the same regression.** Guard scanning and dispatcher precondition setup are separate fault domains.

## Repair approach

1. Retrieve the source `test-all` log/structured failure metrics for the exact run timestamp; identify case four and the last completed stage. Do not rerun `make test-all` merely to overwrite the last run.
2. Reproduce case 130 in the branch using the guard's exact scan command; record matching file/line, rc and stderr; fix forbidden pipeline in the implementation, not via blanket allowlist expansion.
3. Reproduce 1015/1016 in an isolated offline BATS environment, including simulated pushed-HEAD and `_e2e_remote_preflight_with_retry` success; identify precondition stopping each test.
4. Retain test intent: a held lock yields busy/no local fallback/no SSH dispatch, while a successful dispatch invokes `e2e_verify_vcluster` and `e2e_runner_publish_back`, returning the original exit code.
5. Add direct negative test for remote failure exit-code preservation as well as success, if not already covered.
6. Run only focused offline BATS first; after root-cause corrections and operator approval, run full `test-all` to prove completion and alert resolution. Avoid live runner, SSH, cluster or credentials.

## Acceptance

```yaml
must:
  - id: M1
    text: All four failed test case names, failure assertions and run-stage markers are documented from one actual source run, or explicitly marked unavailable.
  - id: M2
    text: The grep-q guard passes with no non-allowlisted occurrences, and fails on a fixture adding a forbidden pipefail-sensitive grep-q pipeline.
  - id: M3
    text: Busy-lock test reaches the real lock-acquisition branch and proves busy/no local fallback/no remote dispatch.
  - id: M4
    text: Publish-back dispatch test reaches the SSH stub, verifies the remote command chain and original success/nonzero exit preservation.
  - id: M5
    text: Focused BATS and subsequently the authorized full offline suite pass with all three stage-complete markers and an updated fresh metric.
must_not:
  - id: N1
    text: Do not remove safety assertions, weaken lock protection, bypass pushed-HEAD checks in production or broadly expand grep-q allowlist.
  - id: N2
    text: No real SSH, Git push, cloud resource mutation, runner dispatch, secrets or live cluster calls from offline fixtures.
  - id: N3
    text: Do not attribute the fourth failure or classify the exact cause without source evidence.
  - id: N4
    text: Do not mark alert resolved based solely on a focused test; full fresh run and metrics needed.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N3]
    text: Captured exact failing-case output and guard scanner exit/matches; mutation fixture red.
  - id: E2
    kind: offline
    proves: [M3, M4, N1, N2]
    text: Fake-SSH/fixture-Git tests showing busy and publish-back paths reached, both success and failure exit statuses.
  - id: E3
    kind: live
    proves: [M5, N4]
    text: Operator-approved full test-all run finishes all stages, reports zero failed cases and complete=1 in fresh Pushgateway sample; both warnings resolve.
interface:
  - scripts/tests/lib/grep_q_pipe_guard.bats
  - scripts/tests/plugins/e2e_remote.bats
  - scripts/plugins/e2e_remote.sh
  - make test-all / k3dm-test-metrics / k3dm-tests PrometheusRule
```

## Definition of Done

- [ ] Identify fourth test and capture all four errors.
- [ ] Reproduce each affected test with isolated fixtures and preserve guard coverage.
- [ ] Show focused BATS passing and negative mutations red.
- [ ] Confirm full run is complete and fresh, with failed=0; live verification remains separate.
- [ ] Update alert documentation if needed and record commit SHA and test evidence.

## What NOT to Do

- Do not dispatch, rerun full suite or repair runtime infrastructure under this filing.
- Do not declare Hostinger down based on `cluster=ubuntu-hostinger`; this is where Prometheus sees the metrics, not the execution location.
- Do not create PR, commit to main or bypass release gates.

## Source metrics and coordinator reproduction — 2026-10-28

Read-only Prometheus currentgroup test-all-local identifies case4:
1194, PR check duration legend uses a readable side layout without changing
its query. Recordedreason: `table = next(panel for panel in data["panels"] if panel["id"] == 6)' failed.
Current source run timestamp1793191274 (2026-10-28T12:41:14Z), complete0,
laststep test. Original fullrawlog notfound in coordinator temporaryroots;
per-stage rawmarkersunavailable. These are currentpublishedterminalfacts,
not evidence of ongoingexecution. Do not invent a rawtrace or fourthcause.
Currentfocused PRChecks6BATS/promtoolpass; exactcauseofrecordedfailure/its
runcheckout identity is notestablished. Do not callhistoricalfourth resolved
solelyfromisolatedpass or makeanunnecessarynewPRdashboardpatch.

Exactgrepguardscan reproducesrc0 (found forbiddenline):
`bin/k3dm-orbstack-upgrade:168` curl -fsS metrics | grep -q forecastpattern.
Guardbaseline1failed/1passed. Fixproducer-drain implementation, notallowlist.
[Actual source and baseline](../issues/2026-10-28-two-new-p2-luna-batch.md).

## Files

- `bin/k3dm-orbstack-upgrade`
- `scripts/tests/lib/grep_q_pipe_guard.bats`
- `scripts/tests/bin/orbstack_upgrade.bats`
- `scripts/tests/plugins/e2e_remote.bats`
- `scripts/plugins/e2e_remote.sh`
- `docs/tests/offline-test-all-regressions.md`
- `scripts/tests/plugins/hub_data.bats` — 2026-10-28 operator rerun follow-up: isolate four Make recipe fixtures from the arbitrary workspace/socket; production recovery unchanged

## Rules — current authorized Luna task

Task offline-test-all-regressions-luna, gpt-6-luna. Existingfiling-only/no-dispatch
text is superseded for this boundedimplementation. No live fullsuite/metrics
publication, SSH/scp/Gitnetwork/provider/credential/runner/clusteroperations.
Only Files above; no spec/memory, stage/commit/push/PR/main/newplan; coordinator
reviews/commits/lands/pushesandlateroperatorfullfreshvalidation. Preserveguards,
assertions/DO_NOT_REMOVE, new/refactoredfunctions<=8ifs; reportlegacyconflicts.

1. Guard exactscanreadingonlyrepo and fixturemutations is safe. Removeactual
   curl|grep-q hazard inOrbStackforecastprobe; consumeproducer throughEOF and
   testlarge matchingpayloadunderpipefail without realcurl/upgrade/services.
   Do not broadenallowlist or removeassertions. Preserve existing guardtests
   and add fixture mutation rejecting a forbiddennonallowlistedpipe.
2. Before reproducingE2E tests, installfixturestubs/spies for all remote and
   credential boundaries (_e2e_remote_ssh, ssh, scp, resolver, copyresults,
   actualpreflighthelper), notjust e2e_runner_preflight. Existing fixtures can
   reach unintendedboundariesonceearlierguardsfixed. Allcalls mustbe fakes;
   fixtureGit orcontrolledGitstub simulatespushedHEAD, no realfetch/push.
3. Diagnose exactpreconditionfailure from capturedoutput safely. Fix test
   setup to reach realbusybranch and SSHdispatch. Keep productionpushedHEAD,
   repo/digestvalidation, preflight, locks, no-localfallback, credentialhandling
   and exitpreservation intact unless currentprovenimplementationbug requires
   minimalchange. Don't stub away behaviorundertest.
4. Busycase must allowonlyfakedreadonlyownerlookup whereexpected, andprove
   noSSHdispatch/noexecution/nolocalfallback. Success andnonzeroSSHexitcases
   provegeneratedremote E2E/publishback chain and originalexitcode survives
   printf/tee/publishfailures, lockreleaseobserved; no actualremotecommandruns.
   Stubcredentialresolver so no Keychain/ghauthread even in successfulpath.
5. Do not alterPRChecksYAML/tests (currentisolatedpass); document #1194 and
   currentpass pluslimits. If reproducibleorder/environmentfailure needsnew
   files, report concretelybeforeexpanding scope. Rawfourthdetails/stagemarkers
   unavailablemayremainexplicit. No quietnewfailurecauseclaims.
6. Focused gates: bats scripts/tests/lib/grep_q_pipe_guard.bats
   scripts/tests/plugins/e2e_remote.bats scripts/tests/bin/orbstack_upgrade.bats;
   Python pytest scripts/tests/bin/test_orbstack_metrics.py and
   scripts/tests/bin/test_k3dm_test_metrics.py to ensure reportcontractsunchanged;
   ShellCheckalltouchshell/Bashandbash-n, docslinks/diffcheck. Negativeguardand
   lock/exitfixtures redonoldbehavior, no weakerassertions/testcountreductions.
   Fullmake test-all not authorizedtoworker; don't overwrite recordedmetrics.
   Operator will runfreshfullpipelineafterindependentreview and check all3stage
   markers, failed0/complete1 andalertresolution separately. No falsecompletion.

## 2026-10-28 Luna implementation and independent review

Implementation commits on the remote release branch: `5a2a958f` (forecast
producer-drain fix and safe E2E fixtures) and `0514e9d9` (remaining fixture
checkout isolation found by native landing). Luna task
`offline-test-all-regressions-luna`, gpt-6-luna; coordinator independently
reviewed, strengthened command-order assertions and repaired two remaining
fixture-only dependencies. Production E2E guards and allowlists unchanged.

Final native landing gate: 116/116 BATS, 37/37 Python metric-contract tests,
raw ShellCheck, actual Bash-script syntax, lint/audit/hooks all pass. PR Checks
separate six-case BATS/promtool gate passes without skips. Broader curated stage:
1,892 passed, 20 skipped, one known Python3.15 ESO loader P3 failed; same ESO
case passes existing Python3.13.6. Full outputs, red/green checks and limitations
are in [batch review](../issues/2026-10-28-two-new-p2-luna-batch.md) and
[full curated output](../issues/2026-10-28-offline-p2-curated-verification.md).

The original four cases pass in the current curated checkout. This does not
establish the historical PR1194/E2E failure causes or complete all three
make test-all stages. Operator next: fresh full make test-all in the usual
Python3.13 shell, then confirm test/test-bin/test-python completion, failed0,
complete1 and fresh publication. Alert resolution remains unverified; retain
OPEN until those results are reviewed. No PR created; Claude owns PRs.

## Operator full rerun follow-up: recovery fixture socket copy

Operator supplied `/tmp/k3dm-test-all-1793208248.log`: 1,913 BATS cases,
four failures, test stage exit1; later stages not reached. Original four
cases pass. Current failures are recovery B4-20, B4-21 teardown order, B4-22
and B4-23. All fail while recursively copying PWD including untracked Unix
socket `./-e`, before their intended recovery assertions.

Coordinator scope communicated before implementation: only change these test
fixtures to copy the actual Makefile and create empty scripts/bin destinations
for existing fakes. Keep real Make recipe assertions, production guards, all
existing tests and socket untouched. Add scripts/tests/plugins/hub_data.bats
to this follow-up scope; no production, UI, Makefile or infrastructure changes.
Full raw operator log and red/green verification are recorded in
`docs/issues/2026-10-28-offline-rerun-hub-fixture-socket.md`.

## Current acceptance status after recovery fixture fix

Recovery fixture follow-up cfb60be0 is pushed; full116/116hub_data BATS,
rawShellCheck and audit/hooks pass. Status check finds no new test-all log
after1793208248. Prometheus still publishes the17:34:54UTC oldrun: failed4,
complete0,laststep=test. No post-fix full run is established. Keep OPEN pending
fresh operator full three-stage run/publication, rather than treating stale
published values as a new regression or declaring all stages green.

## Watched M2 rerun is an older branch, not current-fix acceptance

Screenshot identified M2; read-onlySSH/tmuxwatch found localmakepane%10
on k3d-manager-v1.43.1,HEAD71ef4dea(Oct11). Completed1583cases/23failed,
including missingPyYAML, then metrics publisher connectionrefused. No tests
or code in that oldcheckout modified. Fullactualoutput andhostmapping in
`docs/issues/2026-10-28-m2-old-checkout-test-all-watch.md`.
M2tmuxwindow2/%0SSHlatestpromptidentifiesM4, wherecurrentv1.43.9fixesexist.
Nextoperatorcurrent-fix test-all should runthere; P2acceptance stillpending.
