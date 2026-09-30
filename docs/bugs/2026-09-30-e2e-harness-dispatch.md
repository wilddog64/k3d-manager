# Bug: e2e harness — dispatch

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30 by k3dm-hermes
**Status:** CLOSED — not a bug (Claude, 2026-09-30). The run never reached Playwright: `e2e-remote` refused to dispatch because runner `m2` was below its CPU idle floor (`status=capacity_cpu`, 31.92% idle < 35%). That is the capacity gate working as designed. Reopen only if m2 is refused for capacity repeatedly.
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
