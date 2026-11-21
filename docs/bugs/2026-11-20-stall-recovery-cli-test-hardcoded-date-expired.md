# Bug: `test_stall_recovery_cli_dry_run_uses_only_asserted_scratch_targets` fails on every run since 2026-11-21 00:00 UTC

**Status:** OPEN — captured 2026-11-20 (PST) while verifying dispatch 2e; reproduced on the release-branch HEAD with no 2e changes
**Priority:** P1 proposed by Claude, operator to confirm (test-only, but it fails on every run, so CI cannot go green on any push and no promote or merge can pass the gate)
**Introduced by:** 46ec5b36 (Release v1.44.0)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-20
**Prior art:** exact-slug glob none; grep for the test name and `1794614401` in docs/bugs and docs/issues none; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing on the M4)

## Symptom

`scripts/tests/bin/test_dispatch_metrics.py::test_stall_recovery_cli_dry_run_uses_only_asserted_scratch_targets` fails
at `:159`:

    assert 'k3dm_dispatch_stall_clean_approvals{window="7d",version="9.9.9"} 1' in result.stdout

Reproduced on m4-air, 2026-11-21 01:21 UTC, main checkout at `0e63c968` (branch `k3d-manager-v1.45.0`):
`python3 -m pytest -q scripts/tests/bin/test_dispatch_metrics.py -k test_stall_recovery_cli_dry_run_uses_only_asserted_scratch_targets`
→ `1 failed`. The 2e worker hit the same failure in its full gate.

## Cause

The test writes ledger rows at fixed epochs `1794614401`–`1794614406` (2026-11-14 00:00:01Z onward, `:133-138`) and
then runs the real CLI (`bin/k3dm-dispatch-metrics --dry-run`), which uses the wall clock as `now`. The `7d` window
held the approval only until about 2026-11-21 00:00:01Z. After that the clean-approvals series for `window="7d"`
is no longer 1, so the assertion fails on every run.

## Fix direction

Base the row timestamps on the wall clock, for example `base = int(time.time()) - 3600` and `base + 1` … `base + 6`,
so the rows always fall inside the 7-day window. Keep every other assertion as it is. Check the same file for other
fixed epochs passed to a CLI that reads the wall clock (the in-process `render(..., now=...)` tests pin `now` and are
safe).
