# Bug: the Release plans table hides implementation order and dependencies

**Status:** FIXED `62a06bb3` — E1/E2 green (91 pytest, 28 bats); E3 live pending (Argo refresh + screenshot)
**Priority:** P3
**Severity:** low — the order and dependencies exist in the plan documents, but the dashboard does not show them
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, at operator request
**Approval:** explicit 2026-10-23. The operator asked that "the pane table should show the order you
like to implement in the order or dependencies if there are … so I can understand".

**Component:** `bin/k3dm-vectordb-metrics` (`_plan_metrics`),
`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml` (panel 107 "Plans")

## Problem

The Bug Tracking "Plans" table (panel 107) lists a release's plans in name order. The operator asked
whether plan 5 (`v1.43.5-dispatch-claude-cost`) could be dispatched, and it could not: it depends on
plan 4. Nothing in the table says so.

Both facts are already in the plan headers:
- `**Release:** v1.43.5 (plan 4 of 5)`: the order Claude intends to implement. 23 plan docs carry it.
- `**Depends on:** \`docs/plans/v1.43.5-dispatch-api-cost.md\` (plan 4). …`: the prerequisite plans,
  as backticked paths. 41 plan docs carry the line.

`_plan_metrics` reads neither.

## Fix

### F1. `bin/k3dm-vectordb-metrics`, `_plan_metrics`

Append two labels to every `k3dm_plan_info` line, **after** `approval`, so existing label order and
existing test substrings are unchanged:

- `order`: N from the first line matching `^\*\*Release:\*\*\s*v\d+\.\d+\.\d+\s*\(plan\s+(\d+)\s+of\b`
  (case-insensitive), as decimal digits. Empty string `""` when absent.
- `depends_on`: from the first `^\*\*Depends on:\*\*` line, every backticked
  `docs/plans/<name>.md` path, in the order written, de-duplicated. Render each one as:
  - `plan N` when that plan is in the same release and has an `order`;
  - otherwise its stem (`v1.43.4-foo`).
  Join with `, `. Use `-` when there is no such line or it names no plan path.
  Apply the same quote/backslash/newline stripping already used for `title`.

Resolve `plan N` in a second pass over the scanned texts, so a dependency is found whatever the scan
order. A path to a plan that is not in the scan still renders as its stem.

`k3dm_plan_release_docs` and every other series are unchanged.

### F2. Dashboard panel 107

- Add `order` and `depends_on` to the `organize` step: `order` renamed **Order** at index 1 (right
  after Release), `depends_on` renamed **Depends on** right after Title. Shift the other indexes.
- Add a `convertFieldType` transformation **before** `organize` that converts `order` to a number, so
  10 sorts after 9.
- Sort the table by Order ascending (`options.sortBy` `[{"displayName": "Order", "desc": false}]`).
- Order override: `noValue` `-`, width 70. Depends on override: width 160.
- Panel description: "Order is the plan number from each plan's Release line: the order Claude intends
  to implement. Depends on lists the plans that must land first, from the Depends on line."

### F3. Guide

`docs/guides/grafana-dashboards.md`, Release plans section: one short paragraph on the two columns,
where they come from, and that a plan whose dependency is not yet implemented is not ready to dispatch.

## Tests

`scripts/tests/bin/test_vectordb_bug_metrics.py`:

1. A plan with `**Release:** v1.43.5 (plan 4 of 5)` gets `order="4"`; one without a Release line gets
   `order=""`; `(plan 10 of 12)` gets `order="10"`.
2. A plan whose Depends on line names a same-release plan that has `order` 4 gets `depends_on="plan 4"`,
   even when the dependency sorts after it in the scan.
3. A dependency in another release, or one without an order, renders as its stem; two paths give
   `"plan 3, v1.43.4-foo"`; a repeated path appears once.
4. No Depends on line, or one with no `docs/plans/` path, gives `depends_on="-"`.
5. The existing `k3dm_plan_info` tests pass unchanged (labels are appended after `approval`).

`scripts/tests/plugins/grafana_dashboard_bugs.bats`:

6. Panel 107 renames `order` → Order and `depends_on` → Depends on; Order is at index 1; a
   `convertFieldType` converting `order` to number comes before `organize`; `sortBy` is Order
   ascending.

Mutations (report each as caught): read `of` instead of the plan number → test 1; resolve `plan N`
from the scan order only (single pass) → test 2; drop de-duplication → test 3; sort Order as text →
test 6.

## Files

- `bin/k3dm-vectordb-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/bin/test_vectordb_bug_metrics.py`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: Every k3dm_plan_info line carries order (the N from "(plan N of M)" on the Release line, "" when absent) and depends_on, appended after approval.
  - id: M2
    text: depends_on lists each backticked docs/plans path from the Depends on line once, in written order, as "plan N" for a same-release plan with an order and as the stem otherwise, joined by ", "; "-" when there is none.
  - id: M3
    text: The Plans table shows Order right after Release and Depends on right after Title, sorted by Order numerically ascending.
  - id: M4
    text: The guide's Release plans section explains both columns and their source.
must_not:
  - id: N1
    text: The labels and their order on existing k3dm_plan_info lines, and every k3dm_plan_release_docs line, must not change apart from the two appended labels.
  - id: N2
    text: Order must not sort as text (10 must come after 9).
  - id: N3
    text: A dependency must not resolve to "plan N" from a different release.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, N1, N3]
    text: pytest scripts/tests/bin/test_vectordb_bug_metrics.py green; new tests red on the pre-fix exporter.
  - id: E2
    kind: offline
    proves: [M3, N2]
    text: bats scripts/tests/plugins/grafana_dashboard_bugs.bats green; the new test red on the pre-fix dashboard.
  - id: E3
    kind: live
    proves: [M3]
    text: After the Argo hard refresh and the next scan, the operator's screenshot of Bug Tracking with release v1.43.5 shows rows in order 1-5 and plan 5 "Depends on" plan 4.
interface:
  - bin/k3dm-vectordb-metrics (_plan_metrics; k3dm_plan_info labels order, depends_on)
  - docs/plans/*.md headers "**Release:** vX.Y.Z (plan N of M)" and "**Depends on:**"
  - scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml (panel 107 "Plans")
```

## Definition of Done

- [ ] F1–F3 done; only the Files above change.
- [ ] `pytest scripts/tests/bin/test_vectordb_bug_metrics.py` and `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` green; paste the summaries.
- [ ] New tests shown red on a temp copy of the pre-fix code; mutations reported.
- [ ] CHANGELOG `[Unreleased]` entry.
- [ ] Commit: `feat(bug-dashboard): show plan order and dependencies in the Plans table`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT push to the live Pushgateway or read Prometheus or Grafana from tests.
- Do NOT edit any plan document to add or change Release or Depends on lines.
- Do NOT rename or reorder existing labels or series.
- Do NOT modify files outside the Files list.
