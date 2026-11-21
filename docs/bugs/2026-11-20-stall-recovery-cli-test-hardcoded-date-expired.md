# Bug: `test_stall_recovery_cli_dry_run_uses_only_asserted_scratch_targets` fails on every run since 2026-11-21 00:00 UTC

**Status:** VERIFIED — landed 17815a2a on k3d-manager-v1.45.0 (2026-11-21); offline E1-E3 pass; CI run on the landing push owed (E4)
**Priority:** P1 (operator, 2026-11-20: "yes P1 is right"); test-only, but it fails on every run, so CI cannot go green on any push and no promote or merge can pass the gate
**Introduced by:** 46ec5b36 (Release v1.44.0)
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Waiting on:** live check — since 2026-11-21
**Prior art:** exact-slug glob none; grep for the test name and `1794614401` in docs/bugs and docs/issues none; `make find-similar-docs` unavailable (vector store context `k3d-k3d-cluster` missing on the M4)
**Approval:** operator, 2026-11-20: dispatch to Flash ("send to Flash"). P1, so it may exceed the WIP limit. Target branch `k3d-manager-v1.45.0`.
**Intent approved:** operator, 2026-11-20

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

## Fix

1. In `scripts/tests/bin/test_dispatch_metrics.py`, test
   `test_stall_recovery_cli_dry_run_uses_only_asserted_scratch_targets` (`:127-160`): before `rows = [...]` (`:133`),
   add `base = int(time.time()) - 3600`, and replace the six fixed epochs `1794614401` … `1794614406` with
   `base + 1` … `base + 6`, in the same order. `time` is already imported (`:12`).
2. Change nothing else in the test: every `assert` line stays byte-identical, including
   `'k3dm_dispatch_stall_clean_approvals{window="7d",version="9.9.9"} 1'` at `:159`.
3. Do not touch `STALL_BASE` (`:62`) or any other test: they call `render(..., now=...)` with a pinned clock and do
   not expire. Do not change `bin/k3dm-dispatch-metrics`.

## Contract readers

None. The change is inside one test function. Nothing reads its rows outside the test's own tmp ledger.

## Acceptance

```yaml
must:
  - id: M1
    text: test_stall_recovery_cli_dry_run_uses_only_asserted_scratch_targets passes when run at the current wall-clock time, because its ledger rows are dated relative to time.time() and contain no fixed epoch.
  - id: M2
    text: Every assert line in that test is byte-identical to a2b66a01, including the clean_approvals window="7d" assertion.
  - id: M3
    text: The diff touches only scripts/tests/bin/test_dispatch_metrics.py, inside that one test function; bin/k3dm-dispatch-metrics and STALL_BASE are unchanged.
must_not:
  - id: N1
    text: The test fails when it runs more than 7 days after the dates written into its ledger rows.
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    intent: The stall-recovery test passes today and on any future day, so it no longer turns CI red on every push.
    check: python3 -m pytest -q scripts/tests/bin/test_dispatch_metrics.py -k test_stall_recovery_cli_dry_run_uses_only_asserted_scratch_targets passes; grep shows no 10-digit epoch literal left in the test body. Pre-fix red - the same command on a2b66a01 fails at the clean_approvals assertion (reproduced 2026-11-21 01:21Z on m4-air).
  - id: E2
    proves: [M2]
    kind: offline
    intent: The test still really checks the 7-day window; it was fixed, not weakened.
    check: positive control in a scratch copy - set base = int(time.time()) - 8*86400 and the test fails on the clean_approvals assertion; restore and it passes. git diff a2b66a01 shows no changed assert line.
  - id: E3
    proves: [M3]
    kind: offline
    intent: No other test or exporter behaviour changes.
    check: python3 -m pytest -q scripts/tests/bin/test_dispatch_metrics.py passes in full; make lint (pinned ruff) clean; git diff --stat names only the test file.
  - id: E4
    proves: [M1]
    kind: live
    intent: The next CI run on the release branch has no failure from this test.
    check: Claude, after land and push - gh run view on the landing commit's CI; the pytest step shows this test passed (any other red is reported separately, not counted here).
interface:
  - none (test-only change)
```

## Files

- `scripts/tests/bin/test_dispatch_metrics.py` — the one test function only.

## Worker definition of done

- The test passes, and you show it failing on `a2b66a01`. Record the command and the output in your hand-off.
- `scripts/tests/bin/test_dispatch_metrics.py` passes in full, and pinned ruff is clean. Do not commit.

## Verification (Claude, 2026-11-21)

- Worker: Flash (agy gemini-3.8-flash-medium), 1 run, diff exactly as ## Fix (base = int(time.time()) - 3600, six rows base+1..base+6).
- E1: the test passes on the fix; pre-fix red reproduced on a2b66a01 (2026-11-21 01:21Z). No 10-digit epoch left in the test body.
- E2: positive control in a scratch copy (base = now - 8*86400) fails at the window="7d" clean_approvals assertion; zero assert lines changed.
- E3: full test_dispatch_metrics.py 225 passed in the worktree; git diff --check clean; only the test file changed.
- E4 (live): pending: CI on the push containing 17815a2a and d4d0f5d8.
