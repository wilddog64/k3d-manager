# Bug: Agent Dispatch dashboard shows landing success but not how often a landed spec needed rework

**Filed:** 2026-10-18 (Claude, from an operator request)
**Status:** VERIFIED — 2026-10-18: Claude fix; pytest 10/10 with all 3 new tests red on the pre-fix exporter (N1 included); BATS 7/7; make validate-manifests 81/81; dry-run on the real ledger differs from pre-fix only by added rework lines (30d: 14 of 22, 64%). E3 live pending (dashboard sync + next metrics push)
**Priority:** P3 — missing measurement; no workload is affected
**Severity:** low
**Approval:** approved — operator, 2026-10-18: "go ahead" (rework rate as a P3 on v1.43.4, built by Claude; verified delivery cost goes to a v1.43.6 plan)
**Release:** v1.43.4 (bug; exempt from the plan cap)
**Component:** `bin/k3dm-dispatch-metrics`, `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`, `docs/guides/grafana-dashboards.md`
**Related:** `docs/plans/v1.43.6-dispatch-verified-delivery-cost.md` (the second metric the operator asked for)

## Problem

The operator asked for a **rework rate**: how many Codex specs needed correction after review or a
failed integration gate. The dashboard shows **Landing success** (a ratio of land attempts) and the
per-spec run count, but nothing says what share of landed specs needed a second pass. The ledger
already records everything needed:

- `codex_exit` events per run — more than one run means Codex was sent back (`resume`).
- `land_refused` with `reason=tests` — the integration gate failed at least once.
- `land.verifier_lines` — lines Claude changed between Codex's finished tree and what landed.

In the ledger on 2026-10-18, 22 specs had landed: 2 with more than one run, 2 with a tests refusal
and 13 with Claude edits. `land_refused reason=rebase` and `reason=scope` are not rework — a rebase
refusal means `main` moved, and a scope refusal is the dispatcher's own guard.

The independent verifier's verdict is not in the ledger, so a correction it caused counts only
through the re-run or Claude edit that followed. The guide says so.

## Fix

`bin/k3dm-dispatch-metrics`, for each window, over the same landed set as the other per-landed
metrics (latest `land` per spec within the window):

- `k3dm_dispatch_rework_landed{window,cause}` for `cause` in `rerun` (more than one `codex_exit`),
  `tests` (any `land_refused reason=tests` at or before the land), `claude_edit`
  (`verifier_lines > 0`) and `any` (at least one of these). A spec can count under several causes.
- `k3dm_dispatch_rework_ratio{window}` = `any` / landed, emitted only when at least one spec landed.

Dashboard: a **Rework rate** stat panel (id 13, `percentunit`) in the free slot below
**Time since last dispatch update** (`x 0, y 18, w 5, h 4`), reading
`k3dm_dispatch_rework_ratio{window="$window"}`. Its description names the three causes and the
`k3dm_dispatch_rework_landed` series for the split. Guide: one paragraph in the dispatch section.

## Acceptance

```yaml
must:
  - id: M1
    text: For a landed spec with two codex_exit events, rework_landed counts it under cause rerun and any.
  - id: M2
    text: A landed spec with a land_refused reason=tests before its land counts under tests and any; one with verifier_lines > 0 counts under claude_edit and any.
  - id: M3
    text: rework_ratio equals any / landed for each window; with no landed spec in a window, rework_ratio is not emitted and every rework_landed count is 0.
  - id: M4
    text: The dashboard has a stat panel titled "Rework rate" reading k3dm_dispatch_rework_ratio{window="$window"}, its rectangle overlaps no other panel, and every metric it queries is exported.
  - id: M5
    text: The guide's k3dm Agent Dispatch section defines the rework rate, its three causes, and says the independent verifier's verdict is not recorded.
must_not:
  - id: N1
    text: A landed spec with one run, no tests refusal and verifier_lines 0 must not count as rework, even when it had a rebase or scope refusal (red on pre-fix, which exports no rework series at all).
  - id: N2
    text: No existing metric name, label or value changes; no existing panel's targets, ids or gridPos change.
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    text: pytest scripts/tests/bin/test_dispatch_metrics.py; N1 red against the pre-fix exporter from git show; dry-run output of the pre-fix and fixed exporter on the same ledger differs only by added rework lines.
  - id: E2
    proves: [M4, M5, N2]
    kind: offline
    text: bats scripts/tests/plugins/agent_dispatch_dashboard.bats plus make validate-manifests.
  - id: E3
    proves: [M3, M4]
    kind: live
    text: After ArgoCD app hub-grafana-dashboards syncs and the next dispatch metrics push, the Rework rate panel shows a value at Spec window 30d (operator screenshot).
interface:
  - bin/k3dm-dispatch-metrics render(events, bad_lines, now) and --dry-run
  - ledger events start, resume, codex_exit, land_refused(reason), land(verifier_lines)
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml (agent-dispatch.json)
```
