# Bug: e2e harness — deploying-substrate

**Branch:** `k3d-manager-v1.37.0`
**Filed:** 2026-09-23 by k3dm-hermes
**Status:** OPEN — Hermes rule-based triage; unverified
**Run:** `1790154235-20`, runner `m2`, tier `vcluster`, None passed / None failed / None total
**Runner commit:** `da47dff461f73aff82f903eda279a334acc0e627`

## Failing tests (1)
- …and 1 more

## Sample errors
- INFO: [e2e-remote] result 1790154235-20.json published to M4 hub
INFO: [e2e-remote] runner m2 available; dispatching E2E (digest=none)
INFO: [e2e-remote] runner source pinned to da47dff461f73aff82f903eda279a334acc0e627
INFO: [e2e-remote] result files: /Users/cliang/.k3dm/e2e/dispatch/m2-20260923T090354Z.summary.json /Users/cliang/.k3dm/e2e/dispatch/m2-20260923T090354Z.failures.json
INFO: [e2e-remote] dispatch exit 1; transcript: /Users/cliang/.k3dm/e2e/dispatch/m2-20260923T090354Z.log (rc=1)

## Triage hint
the run did not reach Playwright; read the dispatch transcript.

## Next step
A human (or Claude) verifies the root cause, then writes the fix spec here before any code change.
