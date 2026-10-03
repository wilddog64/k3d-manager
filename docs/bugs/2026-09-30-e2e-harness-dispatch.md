# Bug: e2e harness — dispatch

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30 by k3dm-hermes
**Status:** REOPENED 2026-10-03 — recurred in Hermes e2e run unknown
**Run:** `unknown`, runner `m2`, tier `vcluster`, 0 passed / 1 failed / 1 total
**Runner commit:** `unknown`

## Failing tests (1)
- …and 1 more

## Sample errors
- running under bash version 5.3.20(1)-release
reason=CPU idle 64.4%/31.92% below floor 35%
status=capacity_cpu
ERROR: [e2e-remote] runner m2 not available (status=capacity_cpu); not dispatching, no local fallback (rc=1)

## Triage hint
the run did not reach Playwright; read the dispatch transcript.

## Next step
A human (or Claude) verifies the root cause, then writes the fix spec here before any code change.

## Recurrence 2026-10-03 (run unknown)

1 failing test(s).
- …and 1 more

- running under bash version 5.3.20(1)-release
reason=CPU idle 71.74%/32.98% below floor 35%
status=capacity_cpu
ERROR: [e2e-remote] runner m2 not available (status=capacity_cpu); not dispatching, no local fallback (rc=1)
