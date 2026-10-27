# Bug: Release plans confuses dispatch approval with task state and leaves landed execution stale

**Status:** VERIFIED — replacement landed in `608b90a1`; live dashboard E3 remains pending
**Priority:** P3
**Fix commit:** `608b90a16a01c2009ce9da26646878bfffd6667c`
**Severity:** low — misleading Release plans metadata; Codex dispatch/landing is not blocked by this display issue
**Release:** v1.43.9 (bug; does not count toward the five-plan cap)
**Branch:** `k3d-manager-v1.43.9`
**Filed:** 2026-10-26, at operator request following v1.43.9 Grafana screenshot
**Approval:** explicit operator 2026-10-26: "go ahead to file a P3 dashboard enhancement bug?"
**Dispatch:** go — explicit operator 2026-10-26: "can you dispatch this P3 bug by using GPT-6-Luna?" Model `gpt-6-luna`; fresh task `plans-dispatch-status-reconcile-luna`.
**Component:** `bin/k3dm-vectordb-metrics` (`_plan_dispatch`, plan state metadata), `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (panel 107 Plans), `docs/guides/grafana-dashboards.md`
**Related:** `docs/plans/v1.43.5-release-plan-tracking.md`, `docs/bugs/2026-10-23-release-plans-table-hides-order-and-dependencies.md`, `bin/k3dm-dispatch-metrics`, `docs/howto/codex-dispatch.md`

## Problem and verified code-level diagnosis

The initial v1.43.9 **Release plans** screenshot showed four `Dispatch task` rows as `landed` and one as `awaiting_land`. The latest operator screenshot and M4 ledger recheck show **all five tasks landed**, yet **every row's `Dispatch` column reads `unknown`**. Execution is `proposed` for three plans, `ready` for OrbStack, and `implemented` for retrieval quality. The operator reasonably reads `Dispatch unknown` as missing worker/ledger state or failed dispatch.

This is **not** a failed join and is not evidence of a Codex failure:

- In `bin/k3dm-vectordb-metrics`, `_plan_dispatch(text)` reads **only** the plan's `**Dispatch:**` header and matches `go|needed|not required`; no recognizable header returns `unknown`.
- The metric label is already correctly named `dispatch_approval`, but panel 107 renames that label to the ambiguous display name **`Dispatch`**.
- `Dispatch task` is the separate `dispatch_state` joined from `k3dm_dispatch_plan_state` in the dispatch ledger. That field correctly yields lifecycle states such as `landed` and `awaiting_land`; all five current rows are `landed`.
- `Execution` and `Verified` are derived independently from the plan document's `**Status:**` line; a landed ledger event does not rewrite a status still beginning `PROPOSED` or `READY`.
- The existing `Status lags dispatch` stat is intended to call out these mismatches, but the table does not plainly explain the two axes and makes `unknown` seem like a task result.
- The dashboard's `Blocked by` column can continue to say `dispatch approval unknown` on a **landed** task because blockers are calculated from stale plan execution plus missing `**Dispatch:**` header.

This is an **information architecture and reconciliation gap**, not permission to edit the underlying plan's approval or status text automatically.

## Requested enhancement

The latest operator instruction authorizes a fresh implementation of this P3's
existing requirements with GPT-6-Luna, superseding the earlier hold pending a
table-design decision. Keep the historical reversion and previous findings as
context. This authorization covers the files and acceptance below; it does not
authorize edits to source plan Status/Approval/Dispatch headers, changes to the
live ledger, deployment, or restoration of the separate Live verified column.
The prohibition on re-dispatching other Codex tasks below remains in force.

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

## Rules gates

- Implement only the Files/Acceptance scope above in the isolated task worktree.
- Run `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` and
  `python3 -m pytest scripts/tests/bin/test_vectordb_bug_metrics.py -q`; use an
  existing test virtualenv if the default Python lacks pytest. Report the actual
  interpreter and outputs. Do not install or restart live services to run tests.
- Show the new regression checks failing against the pre-fix behavior, then
  passing with the fix. Run `git diff --check` and the repository audit gates
  applicable without staging or committing. Leave all changes uncommitted for
  independent review; do not touch memory-bank, plan headers, or runtime services.

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

- [x] Producer/consumer semantics reviewed; raw exporter dispatch approval values are preserved. UI mapping handles missing approval.
- [x] E1/E2 offline tests green, including actual Prometheus lifecycle fixtures; no live host side effects.
- [x] Dashboard BATS 38/38 and focused pytest 111/111 pass, including both PromQL engine tests.
- [x] Grafana guide and current-release CHANGELOG updated; five-file change independently reviewed.
- [ ] Approved live dashboard verification captured and E3 recorded before LIVE-VERIFIED.
- [x] Reviewed replacement `608b90a1` landed after the explicitly authorized GPT-6-Luna redispatch. The earlier `78ffa7d5` reversion remains historical.

## What NOT to Do

- Do not change plan **Status**, **Approval**, or **Dispatch** headers just to make the table appear consistent.
- Do not re-dispatch, land or independently verify Codex tasks as part of this P3 dashboard enhancement.
- Do not create a PR, commit to `main`, skip hooks or change runtime/Hostinger services.

## Offline implementation record — 2026-10-27

- Commit `78ffa7d5` landed via `bin/k3dm-codex-dispatch land` and was pushed to `origin/k3d-manager-v1.43.9`.
- At that revision, the Plans panel named `Dispatch approval` separately from ledger-derived `Dispatch task`, mapped missing approval to `not recorded`, and reported landed tasks with stale plan execution as `landed; documentation stale` in Blocked by. Those presentation changes were subsequently reverted as recorded below. The source Status/verification values remained unchanged.
- Verification after rebase: `pytest scripts/tests/bin/test_vectordb_bug_metrics.py -q` — 108 passed; `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` — 38/38 passed; Python compilation and `git diff --check` passed; `_agent_checkpoint`, `_agent_lint`, and `_agent_audit` passed.
- E3 remains pending a dashboard sync/metrics refresh and operator screenshot; no live service was changed by this task.

## Reversion — 2026-10-28

The operator asked to restore the Plans table after finding the added lifecycle and verification fields confusing. Commit `915c55f4` reverted the dashboard changes from this task: the synthetic `landed; documentation stale` Blocked by text, Dispatch approval rename/mapping, and related guide/test/changelog edits are removed. The single-column verification presentation is also restored to its pre-change form while the operator checks the design with Claude. The earlier implementation and verification evidence above are historical; they do not describe the current dashboard. No plan document Status, Approval, or Dispatch headers were changed.

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

## Latest screenshot and five-task reconciliation

At the operator's request, the follow-up investigation in `48db4ad7` reproduced
the latest screenshot using the current parser functions, all five plan files,
and M4's local dispatch ledger. Full terminal evidence and the 38/38 dashboard
BATS result are in
[`2026-10-26-plans-execution-versus-dispatch-task.md`](../issues/2026-10-26-plans-execution-versus-dispatch-task.md).

| Plan | Source Status keyword | Execution | Dispatch header / display | Dispatch task |
|---|---|---|---|---|
| VectorDB drift kinds and age | PROPOSED | proposed | missing / unknown | landed |
| VectorDB retrieval quality | LANDED | implemented | missing / unknown | landed |
| CNI IPAM reclaim visibility | PROPOSED | proposed | missing / unknown | landed |
| Dispatch spec and change complexity | PROPOSED | proposed | missing / unknown | landed |
| Coordinated OrbStack upgrade | READY | ready | missing / unknown | landed |

This expands the earlier three-plan finding to **four stale Status headers**,
including OrbStack. Its ledger records implementation commit `2a729c11`; code
landing does not establish that the operator-run hub upgrade has occurred. All
five tasks have a land event with `test_result=passed`, and the ledger has zero
malformed lines. Those are landing-test results, not live acceptance evidence.

The column distinction is:

- **Execution:** normalized leading keyword of the plan's `**Status:**` header.
- **Dispatch:** approval metadata from a dedicated `**Dispatch:**` header beginning
  `go`, `needed`, or `not required`. All five headers are absent. Approval or
  dispatch instructions elsewhere in the prose do not populate this field;
  `unknown` means the structured metadata is missing, not that permission was
  necessarily absent. **Spec approval** independently reads `**Approval:**`.
- **Dispatch task:** lifecycle outcome from the ledger, joined on plan. Landing
  does not rewrite Status or approval headers.

Retrieval's `LANDED — offline VERIFIED ...` Status maps to Execution `implemented`
but Verified `unknown`, because `_plan_state` uses the leading keyword. That
explains the additional verification discrepancy without claiming that its
recorded offline evidence is absent.

The source metadata and ledger currently disagree; refreshing the browser alone
cannot reconcile them. The bug remains **OPEN / P3**. The previous presentation
fix remains reverted pending operator/Claude design agreement. This update
records findings only: it does not authorize redispatch, restoration of the
reverted dashboard changes, automatic approval inference, or edits to plan
Status headers. Source-document reconciliation should be reviewed against each
plan's accepted implementation and remaining verification evidence as a
separate scoped action.

## Replacement reviewed and landed

The operator-authorized replacement was completed in the Luna task, independently
reviewed, and landed through the dispatcher as `608b90a1`. It changes only five
of the original six allowlisted files. The exporter remains unchanged: raw
`unknown` approval is mapped to `not recorded` in Grafana, while the renamed
Dispatch approval and existing Dispatch task retain distinct sources.

Only a landed task with proposed/ready/in-progress source execution receives
`landed; documentation stale` in Blocked by. The actual plan Execution, Verified,
and approvals are preserved, as are blockers for non-landed tasks, no-ledger
rows, Auto/Manual/repo filters, links, and the single Verified column. Fixed
widths total 1,312 px against the 1,350 px budget. No separate Live verified
column, plan-header edit, or runtime deployment is included.

Coordinator replaced a test that copied display logic with actual Prometheus
query evaluation. Nine lifecycle cases run in both Auto and Manual modes with
exact expected labels and additional excluded repo/release inputs. Both engine
tests fail on the original query and pass on the replacement. Post-rebase gates:
111 Python tests passed, Ruff passed, dashboard BATS 38/38; staged audit/lint,
diff checks, and doc links passed. Promtool 3.2.1 was installed only under /tmp
and supplied with `PROMTOOL`; the two engine tests explicitly skip when promtool
is unavailable, and neither was skipped in this verification.

Full evidence, original partial-worker failures, and the corrected resume-model
issue are recorded in `docs/issues/2026-10-26-dispatch-closeout-review.md`.
The earlier OPEN/P3 findings describe the pre-replacement state. Current status
is VERIFIED offline. E3 requires approved rollout and an operator screenshot
showing Dispatch approval/task separation and stale-document blockers. No live
refresh, dashboard sync, restart, or screenshot verification was performed here.
