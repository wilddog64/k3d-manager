# Bug: test-all fails on aging hub-data prune fixtures and omits actual BATS diagnostics

**Filed:** 2026-10-15
**Branch:** `k3d-manager-v1.43.2` (triage 2026-10-15, operator-approved placement)
**Status:** OPEN — investigation required; do not modify pruning behavior before diagnosis
**Priority:** P2 — blocks the canonical `test-all` release gate despite other tests passing; workaround is targeted investigation and rerun, not suppressing this test
**Severity:** medium
**Origin:** operator, 2026-10-15; `k3dm-test-all-1792063475.log` and Grafana “Failures in selected time range” screenshot

## Symptom and evidence

`./scripts/k3d-manager test all` ran 1,585 BATS cases and exited 1 with exactly one failed case:

```text
not ok 1006 5 prune keeps recent exports and the last passing export
# (in test file scripts/tests/plugins/hub_data.bats, line 443)
# `source_plugin; export DR_TEST_RESULT_EXPORT=20261002T120000Z; run hub_data_prune; [ "$status" -eq 0 ]; ...` failed
make[2]: *** [test] Error 1
```

The test fixture creates snapshot directories `20261009T120000Z`, `20261007T120000Z`, `20261004T120000Z`, `20261002T120000Z`, and `20260928T120000Z`; marks October 2 as the last drill-passing export; and expects:

| Export | Expected |
|---|---|
| 20261009T120000Z | keep (recent / newest) |
| 20261007T120000Z | keep (recent) |
| 20261004T120000Z | prune |
| 20261002T120000Z | keep (last drill-proven) |
| 20260928T120000Z | prune |

The observed BATS output only prints the entire chained assertion; it **does not identify which predicate failed**, nor does it include the actual `hub_data_prune` exit status or output. Adjacent tests for keeping the newest old export, refusing an unreadable results ref, force-pushing snapshots only, manifest validation, and dry-run behavior passed. The 428 blocked tripwire host-tool calls are expected isolation diagnostics, not separate test failures.

## Root-cause hypothesis (not yet confirmed)

In `scripts/plugins/hub_data.sh`, `hub_data_prune` calculates `now="$(date -u +%s)"` and `cutoff=$((now - K3DM_HUB_DATA_RETAIN_DAYS * 86400))`; a snapshot is kept only if newer than cutoff, newest, or the last passing export. The test uses **fixed October 2026 timestamps** while the runtime clock advances. On October 15, an October 7 fixture may have aged out of the configured retention window; that would make an expected `keep:` turn into `prune:`. Reproduce and inspect actual output before declaring this the cause.

A separate possibility is a return-code failure, snapshot verification failure, or changed retention behavior. Do not assume a production backup was pruned incorrectly based only on this failed unit test.

## Grafana evidence and diagnostics gap

The existing test observability pipeline successfully ingested and displayed:

- **Target / origin:** `test-all-local`
- **Target:** `test-all`
- **Test suite:** `bats`
- **Case:** `1006`
- **Test name:** `5 prune keeps recent exports and the last passing export`
- **Failure reason:** assertion source starting with `source_plugin; export DR_TEST_RESULT_EXPORT=20261002T120000Z; run hub_data_prune; ...`

This confirms attribution and failure ingestion work. However, “Failure reason” is effectively the test's shell source, not observed versus expected output. Investigate whether the test runner can collect **bounded, redacted** actual exit code, stdout/stderr and the specific failed predicate in the per-test failure artifact; surface useful context in the Grafana table or through a linked detail artifact without creating high-cardinality metrics or leaking secrets. Keep this as a **secondary diagnostic scope**; do not make the core prune-fixture fix dependent on a dashboard redesign.

## Investigation and proposed fix

1. Reproduce just the failing BATS test using the current release branch and capture its actual `status` and `output`, including each `keep:` and `prune:` line.
2. Confirm `K3DM_HUB_DATA_RETAIN_DAYS` defaults/overrides and identify precisely which assertion fails.
3. If aging fixtures are the cause, use a controlled/injected clock or compute fixture timestamps relative to a frozen reference date. Ensure the behavior is reproducible regardless of calendar date, timezone, and run time. Prefer controlling `now` in tests over changing production retention policy.
4. Preserve the safety invariants: newest export and last **verified drill-passing** export must never be pruned solely due to age; unverified or malformed retained exports fail closed; no unwanted branch push on error.
5. Split the one-line chained assertion or provide explicit expected/actual diagnostic output so subsequent failures identify the actual mismatch.
6. Validate Grafana per-case failure extraction and determine whether actual/expected details can be captured safely within the existing artifact and exporter contracts.
7. Run targeted `scripts/tests/plugins/hub_data.bats`, related mutation/negative cases, then full `make test` or `./scripts/k3d-manager test all` under tripwire.

## Acceptance criteria

- Test #1006 is repeatable on arbitrary dates; explicitly simulate clock movement across retention boundaries.
- Exact keep/prune expectations match documented five-day (or configured) policy, including protection for newest and last drill-proven snapshots.
- No production data export, pruning, retention, or deletion changes are performed to satisfy a brittle test.
- Failure reports expose an actionable predicate and expected-versus-actual data (redacted, bounded), with at least a demonstrated per-test diagnostic path; do not distort Prometheus cardinality.
- Hub-data test suite and full `test-all` pass, with no weakened or skipped safety assertions.

## Relevant files

- `scripts/tests/plugins/hub_data.bats` — case #1006 fixture and assertions
- `scripts/plugins/hub_data.sh` — `hub_data_prune` cutoff and protection logic
- Test-all BATS result collector / failure artifact exporter / Grafana K3DM Tests dashboard — diagnostic-depth investigation (identify exact paths before changing)

## Evidence location

Operator upload: `k3dm-test-all-1792063475.log`, run artifact `scratch/test-logs/all/20261015-042435.log`; Grafana “Failures in selected time range” screenshot 2026-10-15. No real backup export/prune was executed as part of this bug filing.
