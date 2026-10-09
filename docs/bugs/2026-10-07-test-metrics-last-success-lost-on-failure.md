# Test metrics deletes the last-success timestamp after a failed run

**Status:** VERIFIED live 2026-10-09 — failed `make test-all` (19:09:08Z, exit 2) left `k3dm_test_last_success_timestamp_seconds` at the prior success 2026-10-08T03:21:26Z; the next passing run (20:01:33Z, 2664 cases, 0 failed) advanced it to 20:01:33Z (hub Prometheus, job `k3dm-tests`, `test-all-local-last-success`).
**Filed:** 2026-10-07
**Affected release:** v1.42.0
**Source:** Operator freshness-panel investigation
**Verified revision:** 8c345767644b42a2752a9f5d64c6076d90580d6a

## Observation and expected semantics

Operator screenshot image(20261007-164259).png shows both freshness panels at
3.41 hours. Both panels currently display elapsed time, not an absolute completion date.
Their numbers naturally grow at every dashboard refresh. If the most recent completed
run passed, both stored timestamps are equal and both displayed ages should be equal.
The screenshot alone does not demonstrate incorrect timestamp updates.

The last-success timestamp should change only on a new successful run. After a failure,
Suite freshness should reflect the newer failed run while Last successful run retains
the prior success and continues aging. If an absolute date is preferred, label and display
that separately from elapsed age.

## Confirmed separate defect

bin/k3dm-test-metrics.build_payload emits k3dm_test_last_timestamp_seconds on every run.
It emits k3dm_test_last_success_timestamp_seconds only when both parsed failures and
exit_code are zero. push_metrics now uses PUT to replace the entire target/origin group.

A failed payload omits last-success, so PUT deletes the earlier successful timestamp.
The dashboard uses instant queries time() - max(k3dm_test_last_timestamp_seconds) and
time() - max(k3dm_test_last_success_timestamp_seconds). Once the deleted series is stale,
a single-group deployment loses the last-success panel. With multiple groups, the global
max may instead fall back to an older success from another group.

This is a regression interaction with the intentional
[stale-failure replacement fix](2026-10-07-test-metrics-stale-failure-series.md).
It is separate from the fixed
[freshness aggregation bug](2026-10-07-test-dashboard-freshness-aggregation.md).

## Local reproduction

Loaded the exporter from the verified revision without editing it. Called build_payload
and push_metrics for success at time 1000, failure at 2000, and success at 3000. An in-memory
opener asserted PUT and modeled whole-group replacement; no live service was contacted.

Actual output:

```text
[k3dm-test-metrics] metrics pushed: test-all/local
passed: last_run=1000, last_success=1000
[k3dm-test-metrics] metrics pushed: test-all/local
failed: last_run=2000, last_success=ABSENT
[k3dm-test-metrics] metrics pushed: test-all/local
passed again: last_run=3000, last_success=3000
```

Expected middle state: last_run=2000, last_success=1000.

## Acceptance criteria

- Preserve the latest successful timestamp per target/origin across failed publications.
- New successes advance both timestamps; failures advance only the last-run timestamp.
- A run with zero parsed failures and nonzero exit code must not count as successful.
- Preserve PUT semantics for current-run metrics so stale failure labels remain cleared.
  Do not restore whole-payload POST as a workaround.
- Handle a publisher restart and multiple target/origin groups without fabricating a success.
  Select a bounded durable-state or separate-publication design explicitly.
- Before any recorded success, display an honest no-success/unknown state.
- Validate success -> failure -> success, repeated failures, and publisher restart with a
  Pushgateway replacement contract test and live Grafana confirmation.
- Explain elapsed age in panel titles/descriptions, or provide an absolute completion date
  separately; equal elapsed ages after a passing latest run are expected.

## Resolution

The exporter now publishes a separate `test-all-local-last-success` Pushgateway group only after
a successful run. Failed runs continue to replace the current target group with `PUT`, clearing
current failure labels without deleting the durable success marker. The dashboard's existing
`max(k3dm_test_last_success_timestamp_seconds)` query therefore retains the prior success age
through failed runs. The marker is stored in Pushgateway rather than process memory, so a publisher
restart does not fabricate or erase the last known success.

## Validation and scope

Deterministic offline reproduction confirmed the producer/publication contract defect. The fix has
focused regression coverage for marker construction and success/failure publication decisions;
live success -> failure Grafana verification remains pending.
Repository path/title dedup found related bugs with different causes; vector similarity
was not requested during this filing.
