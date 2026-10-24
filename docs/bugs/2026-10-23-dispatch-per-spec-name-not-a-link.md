# Bug: the Per spec table's Spec names are not links to the spec

**Status:** LANDED `33a1b841` 2026-10-23 — E1/E2 green (37 pytest; 5 new tests red on pre-fix, path-validation mutation caught; rework 1 added the audit marker for the 20→21 count). Review miss: one override both hid and linked "Spec", so the linked column was hidden and raw `spec` showed; Claude fixed it (separate `spec` hide override, Spec ordered after Release). E3 pending a second hard refresh.
**Priority:** P3
**Severity:** low — the operator has to find the spec file by hand
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, at operator request
**Approval:** explicit 2026-10-23. The operator asked: "can we turn this spec column into a hyperlink
that will open a tab?"

**Component:** `bin/k3dm-dispatch-metrics` (`_render_scope`),
`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (panel 12 "Per spec")

## Problem

Panel 12 shows each dispatched task's slug in the **Spec** column as plain text. The slug alone does not
locate the file: a plan is `docs/plans/<version>-<slug>.md` and a bug is `docs/bugs/<slug>.md`.
The `start` event in the dispatch ledger already records the exact path (`"spec"`, written by
`bin/k3dm-codex-dispatch` line 278), but no series exposes it.

## Fix

### F1. `bin/k3dm-dispatch-metrics`

For each task row `_render_scope` emits (the same rows, same cap, same order), also emit
`k3dm_dispatch_task_spec{window="<window>",version="<version>",slug="<slug>",spec="<path>"} 1`.
`<path>` is the `spec` of that task's latest `start` event. Emit the line only when that path matches
`^docs/(plans|bugs)/[A-Za-z0-9._-]+\.md$`. Otherwise (no start event, no `spec` field, any other
value), emit nothing for that task. Every existing series is unchanged.

### F2. Dashboard panel 12

- Add query E: `max by (version, slug, spec) (k3dm_dispatch_task_spec{window="$window"})`, table,
  instant.
- `organize`: exclude `Value #E`. Do **not** exclude `spec`: a link can only read
  `${__data.fields.spec}` from a field that is still in the frame. Hide `spec` with a `custom.hidden`
  override instead, the way panel 107 on Bug Tracking hides `branch`.
- Override on **Spec**: link titled `Open spec document`, URL
  `https://github.com/wilddog64/k3d-manager/blob/k3d-manager-${__data.fields.version}/${__data.fields.spec}`,
  `targetBlank: true`.

A row with no spec path gets a link to the release branch root. That is acceptable; do not add a
fallback.

## Tests

`scripts/tests/bin/test_dispatch_metrics.py`:

1. A task whose latest `start` has `spec: docs/bugs/2026-10-23-x.md` emits
   `k3dm_dispatch_task_spec{...,slug="...",spec="docs/bugs/2026-10-23-x.md"} 1` for each window and
   release scope that lists the task.
2. Two `start` events: the later one's spec wins.
3. No `spec`, or a spec of `../etc/passwd` or `docs/plans/a b.md`, emits no `k3dm_dispatch_task_spec`
   line for that task, and its other task series are still emitted.
4. Panel 12: query E exists; the Spec override has a link with `targetBlank` true whose URL contains
   `${__data.fields.spec}` and `k3d-manager-${__data.fields.version}`; `spec` is hidden; `Value #E` is
   excluded.

Show tests 1, 3 and 4 red against the pre-fix code on a temp copy. Mutation: drop the path validation
→ test 3 must fail.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: For every task row it already renders, the producer emits k3dm_dispatch_task_spec with the spec path from the task's latest start event.
  - id: M2
    text: Clicking a Spec cell in Per spec opens that spec on GitHub, on the task's release branch, in a new tab.
  - id: M3
    text: The guide's Agent dispatch section says the Spec column links to the spec.
must_not:
  - id: N1
    text: A spec value that is not a docs/plans or docs/bugs markdown path must not appear in any label.
  - id: N2
    text: No existing series, label or panel column changes, apart from the added hidden spec field.
  - id: N3
    text: The raw spec path must not show as a visible column.
evidence:
  - id: E1
    kind: offline
    proves: [M1, N1, N2]
    text: pytest scripts/tests/bin/test_dispatch_metrics.py green; new tests red on the pre-fix producer.
  - id: E2
    kind: offline
    proves: [M2, N3]
    text: Dashboard test green; red on the pre-fix dashboard.
  - id: E3
    kind: live
    proves: [M2]
    text: After the Argo hard refresh and the next metrics push, clicking a Spec in Per spec opens the spec on GitHub in a new tab.
interface:
  - bin/k3dm-dispatch-metrics --dry-run (series k3dm_dispatch_task_spec)
  - dispatch ledger start events with a "spec" field
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml (panel 12 "Per spec")
```

## Definition of Done

- [ ] F1–F2, a one-line guide note, and a CHANGELOG `[Unreleased]` entry; only the Files above change.
- [ ] `pytest scripts/tests/bin/test_dispatch_metrics.py` green; paste the summary.
- [ ] New tests shown red on a temp copy of the pre-fix code; mutation reported.
- [ ] Commit: `feat(dispatch): link Per spec names to their spec documents`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT push to the live Pushgateway in tests.
- Do NOT change `bin/k3dm-codex-dispatch` or the ledger format.
- Do NOT modify files outside the Files list.
