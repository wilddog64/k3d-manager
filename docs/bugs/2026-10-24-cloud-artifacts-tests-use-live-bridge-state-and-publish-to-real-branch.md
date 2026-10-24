# Bug: `test_cloud_artifacts.py` uses the live bridge state dir, so the live bridge publishes test responses to the real `cloud-requests` branch

**Status:** FIXED (2026-10-24, Claude; offline-verified)
**Priority:** P2 — every pytest run leaks fake responses onto a live, shared branch, and since 744847f6 the suite fails 10 of 11; no credential leaked (the scrubber held).
**Severity:** medium
**Release:** v1.43.5 (bug; exempt from the plan cap)
**Filed:** 2026-10-24, by Claude, while triaging the pre-release `make test` reds
**Component:** `scripts/tests/bin/test_cloud_artifacts.py`
**Related:** `scripts/tests/bin/test_cloud_bridge.py` (already isolated), `docs/bugs/2026-10-23-cloud-bridge-reexecutes-request-when-response-push-fails.md` (744847f6), memory `feedback_pushgateway_tests_leak_to_real_hub` (same class)

## Symptom

- Solo `pytest scripts/tests/bin/test_cloud_artifacts.py`: 10 failed, 1 passed, about 50 s per test.
  Every response was `status: "error"`, reason "bridge restarted before the request completed;
  outcome unknown — file a new request".
- `~/.k3d-manager/cloud-bridge/claimed.txt`: 13 of 29 lines are the suite's fixed request IDs
  (`20261001T0000*Z-*`).
- `origin/cloud-requests`: 13 `responses/20261001T0000*` files, 5 `artifacts/20261001T0000*`
  files and their ledger lines were committed 2026-10-24 08:47–08:53 PDT, by the live bridge.
  Both `SYNTHETIC_*` credential strings were absent from those commits.

## Root cause

`bridge.STATE_DIR` defaults to `~/.k3d-manager/cloud-bridge`. `test_cloud_bridge.py` redirects it
with an autouse fixture; `test_cloud_artifacts.py` never did. So the tests wrote claims and outbox
files into the live state dir.

- The live bridge's `_publish_outbox` pushed the tests' outbox responses to the real branch.
- Since 744847f6, `_recover_orphaned_claims` reads the leaked claims: inside the test, every request
  ID already claimed by an earlier run is answered as orphaned, and the live bridge commits an error
  response for each one.

## Fix

The same autouse `isolated_bridge_state` fixture as `test_cloud_bridge.py`, setting `STATE_DIR` to
`tmp_path / "bridge-state"`.

## Verification

- `pytest -q scripts/tests/bin/test_cloud_artifacts.py`: 11 passed, 53.9 s.
- With `webhook_make_targets.py` and `test_cloud_bridge.py`: 148 passed.

## Leftovers (operator decision; not cleaned)

- The 13 test IDs in the live `claimed.txt`. They are already in the real ledger as processed, so
  the bridge does nothing further with them.
- The fake responses and artifacts on `origin/cloud-requests`. Removing them is a push to a shared
  branch, so it needs a go.
