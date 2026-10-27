# Bug: Release plans confuses dispatch approval with task state and leaves landed execution stale

**Status:** FIXED — offline implementation landed; live dashboard verification pending
**Priority:** P3
**Severity:** low — misleading Release plans metadata; Codex dispatch/landing is not blocked by this display issue
**Release:** v1.43.9 (bug; does not count toward the five-plan cap)
**Branch:** `k3d-manager-v1.43.9`
**Filed:** 2026-10-26, at operator request following v1.43.9 Grafana screenshot
**Approval:** explicit operator 2026-10-26: "go ahead to file a P3 dashboard enhancement bug?"
**Component:** `bin/k3dm-vectordb-metrics` (`_plan_dispatch`, plan state metadata), `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (panel 107 Plans), `docs/guides/grafana-dashboards.md`
**Related:** `docs/plans/v1.43.5-release-plan-tracking.md`, `docs/bugs/2026-10-23-release-plans-table-hides-order-and-dependencies.md`, `bin/k3dm-dispatch-metrics`, `docs/howto/codex-dispatch.md`

## Problem and verified code-level diagnosis

On the v1.43.9 **Release plans** Grafana table, four `Dispatch task` rows show `landed`, one shows `awaiting_land`, yet **every row's `Dispatch` column reads `unknown`**. Several landed rows still show `Execution = proposed` or `ready`, with `Verified = n/a`. The operator reasonably reads `Dispatch unknown` as missing worker/ledger state or failed dispatch.

This is **not** a failed join and is not evidence of a Codex failure:

- In `bin/k3dm-vectordb-metrics`, `_plan_dispatch(text)` reads **only** the plan's `**Dispatch:**` header and matches `go|needed|not required`; no recognizable header returns `unknown`.
- The metric label is already correctly named `dispatch_approval`, but panel 107 renames that label to the ambiguous display name **`Dispatch`**.
- `Dispatch task` is the separate `dispatch_state` joined from `k3dm_dispatch_plan_state` in the dispatch ledger. That field correctly yields `landed` and `awaiting_land`.
- `Execution` and `Verified` are derived independently from the plan document's `**Status:**` line; a landed ledger event does not rewrite a status still beginning `PROPOSED` or `READY`.
- The existing `Status lags dispatch` stat is intended to call out these mismatches, but the table does not plainly explain the two axes and makes `unknown` seem like a task result.
- The dashboard's `Blocked by` column can continue to say `dispatch approval unknown` on a **landed** task because blockers are calculated from stale plan execution plus missing `**Dispatch:**` header.

This is an **information architecture and reconciliation gap**, not permission to edit the underlying plan's approval or status text automatically.

## Requested enhancement

1. Rename the panel 107 `dispatch_approval` display column from **Dispatch** to **Dispatch approval** (or `Dispatch authorization`). Keep `Dispatch task` as the ledger outcome field. Its description/tooltips must state the distinct sources.
2. Render missing/nonstandard `**Dispatch:**` as **`not recorded`** or `approval unknown` rather than generic `unknown`; do not call it `approved` simply because a task was dispatched. Keep the underlying parse/mapping semantically distinct from `**Approval:**`, which authorizes a spec document.
3. Explicitly present a **documentation/dispatch mismatch** when `dispatch_state=landed` but `execution=proposed|ready|in_progress`; preserve the actual document state and actual ledger outcome. Do not silently convert execution to `implemented` or verification to `verified`.
4. Once a task is confirmed landed, `Blocked by` must not imply it is still waiting for dispatch approval. A readable display such as `landed; documentation stale` should take precedence over pre-dispatch blockers. Do not weaken real prerequisite blocks on tasks that have not landed.
5. For `awaiting_land`, show `awaiting land` without conflating Codex exit 0 with integration or independent verification; future entries `land_refused`, `codex_failed`, `running`, `no record` continue to be accurate.
6. Keep a single row for every versioned plan including Claude-implemented plans without ledger events, consistent with the docs-inventory-as-authority contract. Preserve repo/release selection, order/dependency/wave columns, field widths and links.
7. Update Grafana guide to explain `Spec approval`, `Dispatch approval`, `Dispatch task`, `Execution`, `Verified`, and `Status lags dispatch`, including the v1.43.9 screenshot case.

## Files

- `bin/k3dm-vectordb-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

Avoid modifying plans just to make a dashboard go green. Inspect producer/consumer compatibility before changing any exporter label value, since `Blocked by` and other consumers may rely on `unknown`.

## Acceptance

```yaml
must:
  - id: M1
    text: Panel 107 labels the plan-header dispatch decision as Dispatch approval, separately from the ledger-derived Dispatch task.
  - id: M2
    text: Missing or malformed plan Dispatch headers display as not recorded/approval unknown without implying failed dispatch or inferred approval.
  - id: M3
    text: A landed ledger task with a proposed/ready/in-progress plan Status retains truthful raw source states and clearly reports status lags dispatch.
  - id: M4
    text: Landed tasks do not show stale pre-dispatch approval blockers; awaiting_land and refused tasks remain distinguishable from delivered/verified work.
  - id: M5
    text: The guide explains all five axes, source-of-truth precedence, and how to reconcile documentation after landing.
  - id: M6
    text: Plans without a dispatch ledger entry remain visible with a truthful no record task state and independent plan authorization status.
must_not:
  - id: N1
    text: Do not mark any task verified, LIVE-VERIFIED or implemented solely from a dispatch event.
  - id: N2
    text: Do not synthesize plan Dispatch approval from Codex ledger start/exit/land or from spec Approval.
  - id: N3
    text: Do not remove pre-dispatch dependency, wave, overlap or approval guards for tasks that have not landed.
  - id: N4
    text: Do not break Auto/Manual release selection, repo filters or plan-to-ledger joins.
  - id: N5
    text: Do not mutate any v1.43.9 plan docs, ledger events or runtime services in order to fix this dashboard.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M5, N2]
    text: Stub plans with missing, go, needed, not required and malformed Dispatch headers; assert panel rename and source semantics, with tests red on pre-change code.
  - id: E2
    kind: offline
    proves: [M3, M4, M6, N1, N3, N4]
    text: Fixture-based landed+proposed, landed+ready, awaiting_land+proposed, land_refused+ready and no-ledger Claude-task rows test mismatch and blocker behavior, preserving filters and no false verification.
  - id: E3
    kind: live
    proves: [M1, M2, M3, M4, M6]
    text: After approved dashboard sync and metrics refresh, operator screenshot on v1.43.9 shows distinct Dispatch approval/task columns, truthful missing approval, landed documentation mismatch and awaiting-land status without misleading blocked-by text.
interface:
  - bin/k3dm-vectordb-metrics — k3dm_plan_info dispatch_approval/execution/verification/blocked_by
  - bin/k3dm-dispatch-metrics — k3dm_dispatch_plan_state dispatch_state
  - scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml — panel 107 Plans and Status lags dispatch
  - docs/guides/grafana-dashboards.md
```

## Definition of Done

- [x] Producer/consumer semantics reviewed; exact implementation approach preserves historical compatibility.
- [x] E1/E2 offline tests green with fixture coverage; no live host side effects.
- [x] `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` and `pytest scripts/tests/bin/test_vectordb_bug_metrics.py` pass.
- [x] Grafana guide and CHANGELOG updated; scoped change reviewed.
- [ ] Approved live dashboard verification captured and E3 recorded before LIVE-VERIFIED.
- [x] Landed commit: `78ffa7d5` (`checkpoint: before operation`; contains the reviewed task changes)

## What NOT to Do

- Do not change plan **Status**, **Approval**, or **Dispatch** headers just to make the table appear consistent.
- Do not re-dispatch, land or independently verify Codex tasks as part of this P3 dashboard enhancement.
- Do not create a PR, commit to `main`, skip hooks or change runtime/Hostinger services.

## Offline implementation record — 2026-10-27

- Commit `78ffa7d5` landed via `bin/k3dm-codex-dispatch land` and was pushed to `origin/k3d-manager-v1.43.9`.
- The Plans panel now names `Dispatch approval` separately from ledger-derived `Dispatch task`, maps missing approval to `not recorded`, and reports landed tasks with stale plan execution as `landed; documentation stale` in Blocked by. The source Status/verification values remain unchanged.
- Verification after rebase: `pytest scripts/tests/bin/test_vectordb_bug_metrics.py -q` — 108 passed; `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` — 38/38 passed; Python compilation and `git diff --check` passed; `_agent_checkpoint`, `_agent_lint`, and `_agent_audit` passed.
- E3 remains pending a dashboard sync/metrics refresh and operator screenshot; no live service was changed by this task.

## Follow-up diagnosis — stale execution statuses for three landed v1.43.9 plans

Investigated 2026-10-27 after the operator noticed that the Release Plans table marked only the retrieval-quality plan implemented, although three other dispatch tasks had landed.

The three documents retain their pre-dispatch/pre-implementation `**Status:**` text:

| Plan | Current document status | Landed implementation |
|---|---|---|
| `v1.43.9-vectordb-drift-kinds-and-age` | `PROPOSED — spec only` | `dd53c17c` |
| `v1.43.9-cni-ipam-reclaim-visibility` | `PROPOSED — spec written ...; not dispatched` | `c292d69d` |
| `v1.43.9-dispatch-spec-and-change-complexity` | `PROPOSED — ... not dispatched or implemented` | `8d7e00cd` |

M4's dispatch ledger has `start` and `land` events for each slug. The implementation commits changed the code, tests, and guides but did not include their plan documents. `bin/k3dm-codex-dispatch land` records task integration in the ledger; it does not revise the source plan. The exporter `_plan_state()` reads only the plan's `**Status:**` line to produce execution and verification. The dashboard separately joins the dispatch ledger for `Dispatch task`; it does not turn `landed` into `implemented` or `verified`.

The retrieval-quality plan is the contrasting case: a separate documentation follow-up, commit `f5c1a745`, changed its Status to `LANDED`, checked off its DoD, and recorded verification. No equivalent post-land documentation commit was made for these three plans. This is a missing post-land status reconciliation, not an intentional dashboard distinction and not evidence that the implementations failed to land.

No plan Status headers were changed during this investigation; the operator is confirming with Claude whether to reconcile them.
