# Bug: Agent Dispatch "Per spec" shows a blank Agent when the spec is not under `docs/plans/` or `docs/bugs/`

**Status:** OPEN
**Priority:** P3
**Waiting on:** dispatch — since 2026-11-08 (batch with the Acting coordinator P3; both edit the Per spec panel)
**Introduced by:** `d0c247dc` (v1.43.7, Agent read from the spec series)
**Should have been caught by:** offline test
**Severity:** low — display only; the ledger records the agent correctly
**Approval:** operator, 2026-11-08 ("let's do 1 and 2")
**Filed:** 2026-11-08
**Detected by:** operator, reading the Per spec table on the Agent Dispatch dashboard; cause traced by Claude
**Affected:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (Per spec, target `E`, `:659`), `bin/k3dm-dispatch-metrics` (`:1712`)
**Branch:** `k3d-manager-v1.43.16` (operator, 2026-11-09)

## Symptom

In the Per spec table, four rows have an empty Agent cell while every other column is filled. They are
`p0-s1-dispatcher`, `p0-s1-metrics` and two S1 review briefs (`2026-11-06-s1-spec-*-brief`), all v1.43.14.

## Root cause

The Agent column comes only from target `E`, `max by (version, slug, spec, agent, repo) (k3dm_dispatch_task_spec)`.
The exporter emits `k3dm_dispatch_task_spec` only when the spec path matches
`SPEC_PATH_RE = ^docs/(?:plans|bugs)/...\.md$` (`bin/k3dm-dispatch-metrics:38`, `:1712`). The four tasks were
started from briefs in `docs/issues/`. The ledger (`~/.local/share/k3d-manager/worktrees/ledger.jsonl`, read
2026-11-08) records their start events with `agent: codex` and `agent: agy`.

Every other per-task series already carries the `agent` label, so the agent is known; only the panel's single
source for it is gated on the spec path.

## Fix direction

Take Agent from a series emitted for every task, for example `k3dm_dispatch_task_handoff_count`, whose labels
include `agent`. Keep `k3dm_dispatch_task_spec` gated on `SPEC_PATH_RE`: the Spec link should stay off for
paths it cannot link. An Acceptance block is written before dispatch.
