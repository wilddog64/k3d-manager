# Task: P0 S1, metrics half

**Status:** OPEN
**Waiting on:** fix running — since 2026-11-06
**Priority:** P0
**Approval:** operator, 2026-11-06: "go ahead to work on S1 spec then dispatch to Luna" and "so can we split task between two?". Hub dashboard change approved by the same go.
**Branch:** `k3d-manager-v1.43.14`

## Goal

Read slice S1 of `docs/plans/v1.43.14-dispatch-stall-detection-and-escalation-gates.md` in full, starting at its S1 heading, and implement only the **metrics half** it describes. The slice is the spec: its schema, output contract, fixtures in `scripts/tests/fixtures/dispatch-gates/`, What NOT to Do and Acceptance all apply to you, read for this half.

Another agent, on a different model, builds the other half from the same slice. Do not read its worktree, and do not implement its files. If a rule cannot be met from your half alone, say so in your final message rather than editing outside your list.

Do not edit the fixtures. If the fixtures and the slice disagree, stop and report it. Do not remove an existing assertion. Do not commit, push or create a PR; Claude reviews and commits.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
