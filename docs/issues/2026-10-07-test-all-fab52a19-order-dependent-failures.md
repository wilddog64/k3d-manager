# `make test-all` job `fab52a19` has order-dependent test failures

**Date:** 2026-10-07  
**Job:** `fab52a19`  
**Scope:** Cloud `make test-all` result and local reproduction

## What was tested

The completed cloud job reported 1,386 test cases with six failures. The six failures
were one observability test and five hub-snapshot capture tests. The same observability
and hub-snapshot suites were then run locally, both directly and through the repository's
tripwire harness.

## Actual cloud output

```text
not ok 198 deploy_observability calls envsubst with $ARGOCD_NAMESPACE and $K3D_MANAGER_BRANCH
# (in test file scripts/tests/lib/observability.bats, line 82)
#   `[ "$status" -eq 0 ]' failed

not ok 972 hub snapshot: capture emits the restore layout
# (from function `capture_snapshot' in file scripts/tests/plugins/hub_snapshot.bats, line 100,
#  in test file scripts/tests/plugins/hub_snapshot.bats, line 105)
#   `capture_snapshot' failed
not ok 973 hub snapshot: tree names satisfy hub recovery claim tree
# (from function `capture_snapshot' in file scripts/tests/plugins/hub_snapshot.bats, line 100,
#  in test file scripts/tests/plugins/hub_snapshot.bats, line 113)
#   `capture_snapshot' failed
not ok 974 hub snapshot: node placement comes from the PV
# (from function `capture_snapshot' in file scripts/tests/plugins/hub_snapshot.bats, line 100,
#  in test file scripts/tests/plugins/hub_snapshot.bats, line 121)
#   `capture_snapshot' failed
not ok 976 hub snapshot: capture probes no remote free space
# (from function `capture_snapshot' in file scripts/tests/plugins/hub_snapshot.bats, line 100,
#  in test file scripts/tests/plugins/hub_snapshot.bats, line 133)
#   `capture_snapshot' failed
not ok 983 hub snapshot: staging directory is 0700
# (from function `capture_snapshot' in file scripts/tests/plugins/hub_snapshot.bats, line 100,
#  in test file scripts/tests/plugins/hub_snapshot.bats, line 192)
#   `capture_snapshot' failed

[k3dm-test-metrics] 1386 cases, 6 failed
make: *** [test-all] Error 2
```

The generated per-test artifact files for these cases were empty, so the cloud result
does not contain the command-level error that caused each assertion to fail.

## Reproduction evidence

The two affected suites pass when run together under the same tripwire protection:

```text
scripts/tests/tripwire.sh bats scripts/tests/lib/observability.bats scripts/tests/plugins/hub_snapshot.bats
1..32
ok 1 deploy_observability calls envsubst with $ARGOCD_NAMESPACE and $K3D_MANAGER_BRANCH
...
ok 32 hub snapshot: remote dir default survives single-quoting on the remote shell
[tripwire] blocked 120 call(s) to host tools; none reached a real binary:
```

The first 535 tests of a full-suite run also passed the case that was failing in
`fab52a19`:

```text
ok 198 deploy_observability calls envsubst with $ARGOCD_NAMESPACE and $K3D_MANAGER_BRANCH
```

In that same full-suite reproduction, the webhook fixture independently failed to start
or remain reachable, producing repeated curl status `000` failures:

```text
not ok 341 POST with wrong token returns 401
# Last output:
# 000
...
not ok 380 POST /cluster with response_url stored in job dir
# ... failed with status 7
```

This confirms that the aggregate suite has test-environment isolation/startup instability;
the six `fab52a19` failures are not currently reproducible as deterministic product
failures. The metrics Pushgateway connection-refused warning is non-fatal and does not
explain the BATS assertions.

## Root cause assessment

**Bug filed: yes — test harness / suite isolation.** The full suite can leak or lose
fixture state between unrelated BATS groups, and the current artifact collection does not
preserve stderr/output for failed tests whose `run` assertion fails. This leaves cloud
operators unable to distinguish a real regression from a fixture failure.

No product-code bug is proven for `deploy_observability` or hub snapshot capture by this
run. The existing webhook fixture startup issue should be tracked with this investigation,
because it is an independent source of misleading `make test-all` failures.

## Recommended follow-up

1. Make webhook fixture startup readiness explicit and fail with the process log instead
   of curl status `000`.
2. Reset or isolate environment, traps, PATH, and temporary state at every BATS file/test
   boundary.
3. Preserve command stderr and the captured `run` output in cloud per-test artifacts.
4. Re-run `make test-all`; only file product bugs if the focused suites fail with their
   diagnostics present.
