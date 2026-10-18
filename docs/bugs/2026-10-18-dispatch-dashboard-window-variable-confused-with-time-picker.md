# Bug: Agent Dispatch dashboard has two "window" controls and the one that matters defaults to 7d

**Filed:** 2026-10-18 (Claude, from an operator session)
**Status:** LIVE-VERIFIED — 2026-10-18: fix `3ee4cd9d`; BATS 6/6, N1 red on pre-fix; E2 operator screenshot after sync: control reads "Spec window 30d" and hub-dr-drill (1.60 Mil) is the first Per spec row
**Priority:** P3 — cosmetic; the data is correct, the controls mislead
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "go for it" (option 1: default 30d + rename, fixed by Claude)
**Release:** v1.43.4 (bug; exempt from the plan cap)
**Fix commit:** 3ee4cd9d
**Live evidence:** 2026-10-18 · run hub-grafana-dispatch-spec-window-screenshot · env hub/k3d-k3d-cluster · scenario agent-dispatch/spec-window-default · commit 3ee4cd9d · proves E2
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`, `docs/guides/grafana-dashboards.md`

## Problem

The **k3dm Agent Dispatch** dashboard opens with the time picker on `Last 30 days` and the `Window`
variable on `7d`. Every ledger panel reads `{window="$window"}` from instant queries, so the time
picker changes nothing. On 2026-10-18 the operator set the picker to 30 days, still saw the 7d
**Per spec** table, and concluded that `hub-dr-drill` (v1.43.0, landed 7.8 days earlier) had been
lost. Prometheus held its `window="30d"` series throughout. Two controls both reading "30 days",
only one of which works, misled the operator twice in one session.

## Fix

In the `window` template variable: label `Spec window`, a `description` saying the Grafana time
picker does not affect these panels, and `30d` as the selected/current value (matching the
dashboard's default `now-30d` time range). The guide's dispatch section names the control and says
the time picker does not apply. No query, panel or exporter changes.

## Acceptance

```yaml
must:
  - id: M1
    text: The dashboard's window variable has current value 30d, exactly one selected option (30d), label "Spec window", and a description that mentions the time picker.
  - id: M2
    text: The guide's k3dm Agent Dispatch section names the Spec window control, its 30d default, and says the time picker does not change these panels.
must_not:
  - id: N1
    text: The dashboard must not open on the 7d window (red on pre-fix, where current is 7d).
  - id: N2
    text: No panel targets, panel ids, variable name (window) or variable values (1d,7d,30d) change; the exporter is untouched.
evidence:
  - id: E1
    proves: [M1, M2, N1, N2]
    kind: offline
    text: bats scripts/tests/plugins/agent_dispatch_dashboard.bats plus make validate-manifests; N1 shown red against the pre-fix dashboard from git show.
  - id: E2
    proves: [M1]
    kind: live
    text: After ArgoCD app hub-grafana-dashboards syncs, opening the dashboard without var-window shows "Spec window 30d" and hub-dr-drill in Per spec (operator screenshot).
interface:
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml (data key agent-dispatch.json, templating.list[window])
  - docs/guides/grafana-dashboards.md (k3dm Agent Dispatch section)
```
