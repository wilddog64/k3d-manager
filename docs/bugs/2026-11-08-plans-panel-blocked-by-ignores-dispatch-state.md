# Bug: Plans panel Blocked by says "ready to dispatch" for a plan already dispatched or held by the dispatch rules

**Status:** OPEN — filed 2026-11-08
**Priority:** P3
**Waiting on:** fix running — since 2026-11-08
**Introduced by:** pre-existing (Blocked by has always been computed from the plan doc alone; `ready to dispatch` dates from `d95afbfe`)
**Should have been caught by:** spec
**Severity:** low — display only; the operator read `ready to dispatch` on a plan Luna had already run, and on a plan the
one-dispatch-per-file rule was holding back
**Approval:** operator, 2026-11-08 ("and blocked by column set to ready to dispatch seems to misleading")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** operator, M5 hub Grafana Plans panel screenshots, 2026-11-08
**Affected:** Plans panel in `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`, `bin/k3dm-vectordb-metrics`
(`_plan_metrics` blocked_by)
**Branch:** `k3d-manager-v1.43.15`
**Related:** `docs/bugs/2026-11-08-plans-panel-blocked-by-repeats-dispatch-approval.md` (LANDED `ed56bb6a`, same column)

## Symptom

On the M5 hub (Grafana 11.4.0), 2026-11-08, Plans panel, release v1.43.15, both proposed plans read
`ready to dispatch` in **Blocked by**:
- `v1.43.15-control-node-linux` had a dispatch record (Dispatch task `awaiting land`): it was already dispatched.
- `v1.43.15-checkout-auto-sync` (Dispatch task `no record`) could not be dispatched: it edits `Makefile`, which the open
  control-node-linux dispatch also edits (CLAUDE.md: at most one open dispatch per file), and its
  `**Intent approved:**` header does not end at a date (its 2026-11-08 amendment needs the intents approved again), so
  `bin/k3dm-codex-dispatch start` would refuse it.

## Root cause

`_plan_metrics` computes `blocked_by` from the plan doc's branch, dependency, wave and Dispatch headers only. It does
not read the dispatch ledger (which `bin/k3dm-dispatch-metrics` already exports as `k3dm_dispatch_plan_state`, and the
panel already joins for the Dispatch task column), and it does not apply the intent-header check that `start` applies
(`scripts/lib/spec_intent.py`).

## Fix

For a plan that is not landed, Blocked by shows, in this order of precedence:
1. `dispatched` when the ledger has an open dispatch for it (running, or exited and not landed).
2. Otherwise the real blockers, joined: branch not cut, dependency not landed, wave note (as today), plus
   `intents need approval` when the `**Intent approved:**` header fails the same check `start` uses, plus
   `waits on <slug> (<file>)` when another open dispatch edits a file in this plan's `## Files`.
3. Otherwise `ready on your go` or `ready to dispatch`, as today.

Where each piece is computed (exporter label, or the panel's PromQL join on `k3dm_dispatch_plan_state`, which already
overrides Blocked by for `landed; documentation stale`) is the implementer's choice; the panel must not show
`ready to dispatch` while any of 1–2 holds.

## Files

- `bin/k3dm-vectordb-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "a proposed plan with an open dispatch (running, or exited and not landed) shows 'dispatched' in Blocked by"
  - id: M2
    text: "a proposed plan whose Intent approved header fails the dispatcher's intent check lists 'intents need approval' in Blocked by"
  - id: M3
    text: "a proposed plan with a file in its Files section that another open dispatch edits lists 'waits on <that slug>' in Blocked by"
  - id: M4
    text: "a proposed plan with a go, a valid intent header, no open dispatch of its own and no file overlap still reads 'ready to dispatch' (paired control for N1)"
must_not:
  - id: N1
    text: "Blocked by reads 'ready to dispatch' or 'ready on your go' for a plan in any M1–M3 situation"
  - id: N2
    text: "a landed plan's Blocked by changes (it stays '-', or 'landed; documentation stale' as today)"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2]
    kind: offline
    intent: "tests feed the exporter small plan docs (one with a dated intent header, one without; two sharing a file) together with a stub dispatch ledger listing one open dispatch, and read the Blocked by value the panel would show for each"
  - id: E2
    proves: [M1, M3]
    kind: live
    intent: "after a promote, with one plan dispatched, the operator's Plans panel shows 'dispatched' for it and 'waits on <slug>' for a plan that shares a file with it"
interface:
  - "bin/k3dm-vectordb-metrics plan metrics (k3dm_plan_info blocked_by), run against a scratch repo root of plan docs"
  - "bin/k3dm-dispatch-metrics k3dm_dispatch_plan_state, or a stub ledger in the same format"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml Plans panel query and blocked_by mappings"
```

## Notes

- Fixtures assert first that the repo root and the ledger are scratch paths, not the real tree or
  `~/.local/share/k3d-manager`.
- The ledger stub must be captured from a real `bin/k3dm-dispatch-metrics` output (host, date beside it), not imagined.
- Same files as the landed Plans P3 and the open control-node work does not touch them, so it can be batched with any
  other Plans-panel P3 at Sunday planning.
