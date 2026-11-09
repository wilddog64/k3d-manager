# Bug: Split work panel says `pending` when there is nothing to merge, and does not name the agents

**Status:** OPEN — spec written; waiting for intent approval and the `k3d-manager-v1.44.0` branch
**Priority:** P3
**Waiting on:** operator decision — since 2026-11-08
**Introduced by:** v1.43.14 (`docs/plans/v1.43.14-dispatch-stall-detection-and-escalation-gates.md:299` defines the `pending` value)
**Should have been caught by:** spec
**Prior art:** not run (`make find-similar-docs` could not reach its vector store from the M4, 2026-11-08); exact-slug glob found nothing
**Severity:** low — misleading display, no effect on dispatch or landing; workaround: read the ledger
**Approval:** operator, 2026-11-08 (Option A: file as a bug, dispatch first in v1.44.0)
**Intent approved:** pending
**Filed:** 2026-11-08
**Detected by:** operator, reading the Agent Dispatch dashboard, 2026-11-08
**Affected:** `bin/k3dm-dispatch-metrics`, `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
**Branch:** `k3d-manager-v1.44.0` (first dispatch of the release; a bug spec, so outside the 5-plan cap)
**Related:** `docs/ideas.md` (row of 2026-11-08, "Make the Agent Dispatch Split work panel readable")

## Symptom

The Split work panel shows two parents, each with one builder (the parent task) and one read-only reviewer:

- `Combine` reads `pending`, which looks like outstanding work. With one builder there is nothing to merge, and one of
  the two parents is landed and verified.
- `Review` reads `1`, and the panel never says which agent built the task or which agent reviewed it.
- `Build` reads `0` although the parent built the fix: the column counts only child tasks with `--role build`.

## Root cause

- `bin/k3dm-dispatch-metrics:2583-2586`: any parent with no `combine` event gets `comb_res = "pending"`, whether or not
  it has anything to combine.
- `k3dm_dispatch_split_parent_parts` (`:2592`) carries only a role and a count. No split metric has an agent name, though
  each `start` event in the ledger records `worker_identity.model`.
- The panel (`grafana-dashboard-agent-dispatch.yaml:2032`, `renameByName`) titles the build-child count `Build`.

## Fix

1. `bin/k3dm-dispatch-metrics`:
   - Add `"n/a"` to `COMBINE_RESULTS` (`:48`). With no `combine` event: `n/a` when the parent has zero `build` members,
     otherwise `pending`. A recorded `combine` always shows its own result, including on a parent with no build members.
   - Add `k3dm_dispatch_split_parent_agents{version,parent,parent_display,build_agents,review_agents,verify_agents} 1`,
     once per exported parent, beside the existing split metrics. Do not change the labels of the existing metrics.
   - Agent name: take `worker_identity.model` from the task's latest `start` event. If the model id contains `luna`,
     the name is `Luna`; `flash`, `Flash`; `argon`, `Argon`; `sol`, `Sol`; `terra`, `Terra`; `astra`, `Astra`. A model
     that matches none uses the id itself if it passes `[A-Za-z0-9._:-]{1,64}`; anything else, or no start event for the
     parent, is `unknown`.
   - `parent_display` is `<parent> (<agent>)`. Each `*_agents` label is the distinct sorted member names joined by
     `, `, or `0` when there are no members for that role.
2. Panel `Split work`:
   - New target with `format: table`, `instant: true`, and
     `max by (parent, parent_display, review_agents, verify_agents) (k3dm_dispatch_split_parent_agents)`, joined on
     `parent` by the existing outer join. Exclude its `Value` column.
   - Exclude `parent` and the `Value #B` and `Value #C` count columns. Show `parent_display` as `Parent`, in the first
     position. Show `review_agents` as `Review` and `verify_agents` as `Verify`, where the counts were.
   - Rename `Value #A` from `Build` to `Sub-agents (build)`.
   - Update the description to say that `n/a` means no build children, so nothing to merge, and that `pending` means
     build children exist and no `combine` was recorded.
3. Tests: `scripts/tests/bin/test_dispatch_metrics.py` for the metric; `scripts/tests/plugins/agent_dispatch_dashboard.bats`
   for the panel and the join. `p-two` and `p-four` at `agent_dispatch_dashboard.bats:1194` assert `pending`: check each
   fixture's build members and convert only those that now read `n/a`.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`

## Do not

- Change the ledger format, `bin/k3dm-codex-dispatch`, or what `combine` records.
- Filter parents out of the panel, or count the parent task inside `Sub-agents (build)`.
- Remove or relabel `k3dm_dispatch_split_parent_parts`, `_info`, `_conflicts`, `_elapsed_seconds` or `_parents_dropped`.

## Contract readers

Found by `git grep k3dm_dispatch_split_parent` and `git grep COMBINE_RESULTS`, 2026-11-08.

| Reader | Changes? |
|---|---|
| `grafana-dashboard-agent-dispatch.yaml:2047-2077` (the panel's queries) | Yes: one new target. The `_info` query passes the `combine` label through, so `n/a` needs no query change |
| `agent_dispatch_dashboard.bats:1082-1200` | Yes: fixtures that now read `n/a`, and the new join |
| `bin/k3dm-dispatch-metrics:48, :2587` | Yes: the new value |
| `docs/plans/v1.43.14-dispatch-stall-detection-and-escalation-gates.md:299-303` | No: a historical plan |

## Proof of deployed behaviour

The change relies on Grafana showing a Prometheus label as a table column through the existing outer join and
`organize` transform. That panel already does this for its `combine` label: the operator's screenshot of the hub's
Agent Dispatch dashboard (2026-11-08) shows `pending` read from that label. The Grafana version was not read for this
spec. Before dispatch, confirm that the label values `n/a` and `Flash, Luna` survive `make dispatch-metrics DRY_RUN=1`
style rendering; live evidence E2 covers the panel.

## Acceptance

```yaml
must:
  - id: M1
    text: "a parent with no build members and no combine event exports combine=\"n/a\""
  - id: M2
    text: "a parent with at least one build member and no combine event exports combine=\"pending\" (paired control for M1)"
  - id: M3
    text: "a parent with a recorded combine exports that result, whether or not it has build members"
  - id: M4
    text: "k3dm_dispatch_split_parent_agents has parent_display '<parent> (Luna)' for a parent started on gpt-6-luna, and review_agents 'Flash' for a review child on gemini-3.8-flash-medium"
  - id: M5
    text: "two review children on different agents give review_agents with both names sorted and joined by ', '; two on the same agent give one name; a role with no members gives '0'"
  - id: M6
    text: "the Split work panel shows parent_display under Parent, review_agents under Review, verify_agents under Verify, and titles the build count 'Sub-agents (build)'"
must_not:
  - id: N1
    text: "a parent with build members and no combine event exports combine=\"n/a\" (paired with M1)"
  - id: N2
    text: "a model id outside the allowed characters reaches a label value; it reads 'unknown' (paired with M4)"
  - id: N3
    text: "the labels or values of the existing split_parent_parts, conflicts or elapsed metrics change for the same ledger"
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, M5, M6, N1, N2, N3]
    kind: offline
    intent: "tests feed the exporter a sample ledger of tasks with and without build sub-agents and reviewers on different agents; a task with nothing to merge reads n/a, a task with build sub-agents and no recorded merge still reads pending, and the panel definition shows the agent names under the new column titles"
  - id: E2
    proves: [M1, M4, M6]
    kind: live
    intent: "after the exporter runs on the merged code and the dashboard is promoted, the Split work panel on the hub shows each parent with its agent in brackets, the reviewer's name under Review, and n/a under Combine for tasks with no build sub-agents"
interface:
  - "bin/k3dm-dispatch-metrics rendering Prometheus text from a ledger, as in scripts/tests/bin/test_dispatch_metrics.py"
  - "make dispatch-metrics DRY_RUN=1"
  - "the 'Split work' panel in scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml"
```

## Definition of done (worker)

Before your last message, do all of these and paste the evidence:
1. Run every test suite that covers a file you changed, not only the new tests. For each, give the command, the exit
   code and every error line. An error you can't explain is a failure, not a pass. If the sandbox blocks a test, say
   so and name it; don't skip it silently.
2. For each `must_not` item: break the guard that enforces it (comment out the check, invert the condition), run its
   test, show it red, then restore the guard and show it green. List any `must_not` whose test stayed green with the
   guard broken.
3. Where the spec allows a read-only run against real data (a real file, a real ledger, a real container image), run
   the changed code once that way and paste what it printed. Otherwise say "no read-only real-data run possible" and
   why.
4. List every place where you chose something the spec did not decide (a default, a path, a mode, an edge case).

## Notes

- Operator chose this route on 2026-11-08 over a plan (which would displace one of the 5 v1.44.0 plans) and over waiting
  in `docs/ideas.md`. The agent names are a small feature carried with the fix, because they are what makes the table
  explain itself.
- It stays P3 by the priority definitions. The operator asked for it to go first in v1.44.0, so it is not batched.
- Delivery has two parts: the exporter runs from `make dispatch-metrics`; the dashboard reaches the hub by `make hub-promote`.
