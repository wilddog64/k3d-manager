# Offline test-all regression repair evidence

## Scope and source evidence

The 2026-10-28 source metrics identify the fourth visible-table failure as BATS
case 1194, `PR check duration legend uses a readable side layout without
changing its query`. The recorded assertion was
`table = next(panel for panel in data["panels"] if panel["id"] == 6)' failed`.
Its raw log and per-stage markers were unavailable, and its run checkout is not
established. A later focused PR Checks run passed six BATS cases and its
promtool checks; that does not establish the historical failure's cause or
resolve the incomplete full run. The regression repair does not modify those
dashboard tests.

The captured local baseline was 111 focused BATS cases: the repository grep-q
guard failed because `bin/k3dm-orbstack-upgrade:168` piped the forecast metrics
curl into `grep -q`; both previously named E2E cases passed locally, but their
fixtures did not protect all remote and credential boundaries. This isolated
pass does not establish the exact cause of either historical E2E failure. No
historical E2E precondition failure output was recovered. The exact scan
reported the forbidden line and returned 0 (match found). After the fix the
exact scan returns 1 (no non-allowlisted matches).

## Offline fixture guarantees

- The producer-drain regression emits 20,000 matching metric lines under
  `pipefail`; the consumer reads to EOF without `grep -q`.
- The repository guard and fixture cases call the same scanner. It detects a
  forbidden `curl | grep -q` source line, while standalone `grep -q` and a safe
  draining pipeline return no matches. Fixtures contain real newline bytes;
  the allowlist is unchanged.
- The OrbStack harness runs the actual upgrade script with fake commands and
  a metrics body containing the forecast followed by 20,000 trailing lines.
  A completion marker proves the fake curl finishes writing; the script's
  report must show forecast presence and no release-forecast regression.
  Reverting only the script's consumer to `grep -q` makes this test fail at
  the missing completion marker; the fixed consumer passes.
- E2E fixture Git, retry-preflight, SSH, SCP, token resolver, and result-copy
  boundaries are fakes. No real Git network operation, remote command, or
  credential lookup is used.
- The busy-lock test uses the real lock-acquisition path and permits only the
  fake read-only owner lookup after acquisition fails. It verifies no SSH
  dispatch, result copy, credential resolution, SCP, workload, or local
  fallback.
- Dispatch success and SSH exit 23 tests inspect the generated
  `e2e_verify_vcluster` then `e2e_runner_publish_back` chain. Both assert command order and retained remote rc, and verify lock
  release; the nonzero case also simulates result-copy failure and preserves
  the original SSH status.
- Six indirect fixture assignments have narrow, justified SC2034 annotations;
  raw ShellCheck runs without a global warning exclusion.

The actual-script mutation check produced this output when only the forecast
consumer was temporarily reverted to `grep -q`, then restored:

```text
1..1
not ok 1 orbstack upgrade: forecast probe drains large metrics producer to completion
# (in test file scripts/tests/bin/orbstack_upgrade.bats, line 315)
#   `[ -f "$TEST_CALLS.metrics-complete" ]' failed
old_consumer_exit=1
```

The fixed script's same test passes in the full focused BATS gate, including
the completion marker and actual JSON report assertions.

## Validation boundary

Run the focused BATS suites and metric-contract pytest files listed in the bug
spec, plus Bash syntax, ShellCheck, documentation links, and `git diff --check`.
The full `make test-all` run and fresh metrics publication are operator-owned;
no focused result establishes all three stage markers, complete status, or
alert resolution. The original fourth-case raw output and stage markers remain
unavailable.

## Landing environment follow-up

The first landing attempt exposed two additional fixture tests whose real Git
reads passed only when REPO_ROOT pointed to a pushed checkout. With
K3DM_REPO_ROOT set to the unpushed task commit, both stopped at the production
pushed-HEAD guard. Coordinator reused the safe dispatch fixture for the
preflight-refusal and remote-exit-7 cases; the former now stubs the actual retry
helper, proves no lock/SSH/credential/copy work, and the latter observes lock
release. Production guard unchanged. Both fail on the previous fixtures and
pass after this fixture-only repair in the same unpushed environment.
