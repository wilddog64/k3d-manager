# Bug: Plans Dispatch shows `awaiting land` for a landed plan when bookkeeping follows the land

**Status:** FIXED 2026-10-25 — fix commit below; pytest `test_dispatch_metrics.py` green, three new state-table cases red on a temp copy of the pre-fix exporter. Live E2 PASSED 2026-10-25 14:40 PDT: after `make dispatch-metrics` (work:4.0, 14:37), Bug Tracking → Plans shows landed (code in) for v1.43.7-dispatch-landing-latency-human-interventions (operator screenshot 330).
**Priority:** P3
**Fix commit:** `6b847dd0`
**Severity:** low — one dashboard cell reads a wrong state; no dispatch or landing behaviour is affected
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the operator's Bug Tracking screenshot 327
**Approval:** not required — non-critical (operator rule: dispatch approval only for critical specs); fixed by Claude on the operator's instruction ("file a P3 bug and fix it if it is small enough").
**Component:** `bin/k3dm-dispatch-metrics` (`_dispatch_state`, series `k3dm_dispatch_plan_state`)
**Related:** `docs/plans/v1.43.7-dispatch-landing-latency-human-interventions.md` (added the `intervention*` events)

## Problem

Bug Tracking → Plans showed **awaiting land** for `v1.43.7-dispatch-landing-latency-human-interventions`,
although its Execution is `implemented` and Verification `live`. The ledger for that task on 2026-10-25:

- 11:11 `start`, 11:22 `codex_exit` (exit 0) + `codex_usage`, 11:34 `land` (tests passed)
- 11:43 `intervention_coverage_start`, 11:43 `intervention` (`continue_prompt`)

`_dispatch_state` took the newest event of any kind. The newest was `intervention`, so it skipped `landed`,
found a clean worker exit and returned `awaiting_land`. Any non-lifecycle event after `land` or `abandon`
(`intervention*`, `verify`, a late `codex_usage`) mislabels the plan the same way. The Agent Dispatch
awaiting-land count (`_task_state`) was unaffected: it checks for any `land`/`abandon`.

## Fix

`_dispatch_state` considers only dispatch lifecycle events (`start`, `resume`, `codex_exit`, `agent_exit`,
`land`, `land_refused`, `abandon`) and ignores bookkeeping events. The guide's Plans paragraph says so.

## Acceptance

```yaml
must:
  - id: M1
    text: A task whose last lifecycle event is land reads landed, whatever bookkeeping events follow it.
  - id: M2
    text: A task whose last lifecycle event is abandon reads abandoned, whatever bookkeeping events follow it.
must_not:
  - id: N1
    text: A bookkeeping event never turns a clean, unlanded worker exit into landed; it stays awaiting_land.
  - id: N2
    text: Existing state-table outcomes (running, codex_failed, awaiting_land, refused, landed, abandoned) do not change.
  - id: N3
    text: Tests never push to the real Pushgateway.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N2, N3]
    text: K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9 pytest scripts/tests/bin/test_dispatch_metrics.py green; the intervention, verify and late codex_usage cases red on a temp copy of the pre-fix exporter.
  - id: E2
    kind: live
    proves: [M1]
    text: After the next metrics push, Bug Tracking → Plans shows landed (code in) for v1.43.7-dispatch-landing-latency-human-interventions.
interface:
  - bin/k3dm-dispatch-metrics --dry-run, series k3dm_dispatch_plan_state
  - ledger.jsonl events per (version, slug)
```

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `docs/guides/grafana-dashboards.md`
