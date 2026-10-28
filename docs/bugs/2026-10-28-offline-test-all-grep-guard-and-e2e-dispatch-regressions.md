# Bug: test-all has four failing BATS cases and stops before completing the offline suite

**Filed:** 2026-10-28 (operator screenshot of Grafana Offline Tests dashboard and Alertmanager emails)
**Priority:** P2 — offline test gate failing and incomplete; security guard failure requires inspection
**Severity:** medium — confidence in test gate reduced; no established production or Hostinger outage
**Status:** OPEN / INVESTIGATED STATICALLY — exact runtime causes not yet reproduced; fourth failing case not visible
**Release:** v1.43.9 bug (does not consume an enhancement plan slot)
**Branch:** `k3d-manager-v1.43.9`
**Approval:** operator explicitly requested investigation and bug filing; implementation, live test rerun, and deployment not authorized by this filing
**Component:** `scripts/tests/lib/grep_q_pipe_guard.bats`, `scripts/tests/plugins/e2e_remote.bats`, `scripts/plugins/e2e_remote.sh`, offline test metrics/Alertmanager
**Related:** `docs/bugs/2026-10-17-grep-q-pipeline-sigpipe-false-absent.md`, `docs/bugs/2026-10-10-offline-suite-count-floor-stale-and-partial-runs.md`, `docs/plans/v1.44.2-cloud-bridge-offline-test-run-diagnostics.md`

## Evidence / symptom

The operator's 2026-10-28 Grafana screenshot shows `Failed cases = 4` and three visible BATS failure entries for target `test-all`:
- case 130: `grep-q guard: no non-allowlisted pipeline retains -q` — `[ "$status" -eq 1 ] failed`.
- case 1015: `dispatch refuses and never falls back locally when the lock is held` — expected output containing `busy` absent.
- case 1016: `dispatch chains publish-back after the E2E and preserves the exit code` — `[ "$status" -eq 0 ] failed`.
- Fourth failed case is below/beyond the captured table view; **do not invent its identity**.

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
