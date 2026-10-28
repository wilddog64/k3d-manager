# Bug: dispatch identity display hides a recorded vendor when model is absent

**Status:** OPEN — reproduced during screenshot investigation; bounded correction in progress
**Priority:** P3
**Filed:** 2026-10-27
**Branch:** k3d-manager-v1.43.9

The model-identity renderer emits displayunknown when either vendor or model
isunknown, even if vendoropenai is explicitly recorded. This hides a known
fact. Historical sourceunreported coordinator/landing fields are genuinely
absent and must not be guessed from worker identity or spending.

Operator questioned blanket unknown cells. Communicated correction before
editing: retain known vendor, label unrecorded identities as not recorded in
existing fields. No new table/panel, identity backfill, ledger/history edits,
model inference or cost attribution. Exact unknown model remains unknown.
Related blank run-log label and outcome wording addressed in the existing
startup-log P3; shared evidence is in the three-open-bugs investigation issue.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`

## Acceptance

Partial explicitly recorded vendor retained, missing model described without
inventing it. Completely unrecorded identity remains unrecorded. Preserve
bounded labels, runtime worker identities, allowlists, measurement state,
known actors, ledger/history and panel structure. Unit regression red on old
renderer; full metrics pytest, dashboard BATS, Ruff, syntax/diff and staged
lint/audit. GUI behavior stays pending operator deployment/reload.
