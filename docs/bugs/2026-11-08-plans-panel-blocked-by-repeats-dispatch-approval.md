# Bug: Plans panel repeats the dispatch go in Blocked by (in green) and shows landed plans' approval as a blank

**Status:** OPEN — dispatched 2026-11-08: Luna implements, Gemini 3.8 Flash verifies from the Acceptance block
**Priority:** P3
**Waiting on:** fix running — since 2026-11-08
**Introduced by:** `d95afbfe` (v1.43.15, the fix for `docs/bugs/2026-11-08-plans-panel-hides-plans-waiting-on-operator-dispatch-go.md`)
**Should have been caught by:** live check
**Severity:** low — display only; the operator asked whether three landed plans still need an approval, and could not
tell the two columns' purposes apart
**Approval:** operator, 2026-11-08 ("go ahead"; "should value be approved instead of -?")
**Intent approved:** operator, 2026-11-08
**Filed:** 2026-11-08
**Detected by:** operator, M5 hub Grafana Plans panel screenshot after the Grafana restart
**Affected:** `bin/k3dm-vectordb-metrics` (`_plan_metrics` blockers), Plans panel in
`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
**Branch:** `k3d-manager-v1.43.15`

## Symptom

On the M5 hub (Grafana 11.4.0), 2026-11-08, Plans panel, release v1.43.15:
1. The two proposed plans (`v1.43.15-control-node-linux`, `v1.43.15-checkout-auto-sync`) show `needs your dispatch
   go` in **Blocked by** and `⚠ needs your go` in **Dispatch approval**: one fact in two columns.
2. That Blocked by text is drawn **green**, although the panel has a regex mapping meant to colour it orange
   (`grafana-dashboard-bugs.yaml`, pattern `needs your dispatch`). Why the mapping does not apply on 11.4.0 is not
   proven; the fix below removes the text, so it no longer depends on that mapping.
3. The three landed plans (cost attribution, hub deploy ref, intent verification) show `-` under Dispatch approval.
   The exporter emits `dispatch_approval="n/a"` for a plan that is no longer proposed and has no `**Dispatch:**`
   header (`bin/k3dm-vectordb-metrics:467-469`); the panel maps `n/a` to `-`. The operator read the blank as
   "not approved yet".

## Fix

- Exporter: Blocked by lists only what stops a plan besides the operator's go (branch not cut, a dependency not
  landed, a wave note). Drop `needs your dispatch go` and `needs your dispatch decision` from it. A proposed plan
  with no other blocker reads `ready on your go` when its dispatch approval is `needed` or `unknown`, and `ready to
  dispatch` when it is `go` or `not required` (as today).
- Exporter: a plan whose execution is `implemented` and has no `**Dispatch:**` header emits
  `dispatch_approval="approved"` (it was dispatched, which required a go). Other non-dispatchable plans keep `n/a`.
- Panel: map `approved` to `approved` in the default text colour, matching the Spec approval column. Blocked by
  keeps no orange/green highlight for any text that names the operator's go; remove the `needs your dispatch` regex
  mapping.

## Files

- `bin/k3dm-vectordb-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`

## Acceptance

```yaml
must:
  - id: M1
    text: "a proposed plan whose only blocker is the operator's go has blocked_by 'ready on your go' and dispatch_approval 'needed'"
  - id: M2
    text: "an implemented plan with no Dispatch header has dispatch_approval 'approved', and the Plans panel shows that value as 'approved'"
  - id: M3
    text: "a proposed plan with a real blocker (branch not cut, or a dependency not landed) still lists that blocker in blocked_by"
must_not:
  - id: N1
    text: "blocked_by contains 'needs your dispatch' for any plan"
  - id: N2
    text: "a proposed plan with Dispatch: needed loses its 'needed' dispatch_approval (paired control for N1: the go still shows, in its own column)"
  - id: N3
    text: "a plan that is proposed, or one that was dropped or superseded, is shown as 'approved'"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2, N3]
    kind: offline
    intent: "tests feed the exporter small plan docs (proposed with and without a go, landed without a Dispatch line, blocked by a missing dependency) and read the plan metric's blocked_by and dispatch_approval labels; a dashboard test checks the panel maps 'approved' to 'approved'"
  - id: E2
    proves: [M1, M2]
    kind: live
    intent: "after a promote and a Grafana restart, the operator's Plans panel shows 'approved' for the three landed v1.43.15 plans and 'ready on your go' for the two waiting ones"
interface:
  - "bin/k3dm-vectordb-metrics plan metrics (k3dm_plan_info labels blocked_by, dispatch_approval), run against a scratch repo root of plan docs"
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml Plans panel field overrides (dispatch_approval mappings, blocked_by mappings)"
```

## Notes

- Fixtures assert first that the repo root is a scratch directory, not the real tree.
- Test the exporter's `n/a` path for dropped or superseded plans as well (N3).
