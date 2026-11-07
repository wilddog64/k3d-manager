# Bug: Agent Dispatch "Verification ladder" panel clips its last rows, cannot sort by count, and does not say what "unknown" means

**Filed:** 2026-11-07
**Branch:** `k3d-manager-v1.43.14`
**Status:** VERIFIED offline — 35fbd4bb; independent Sonnet verifier 2026-11-07: all M1–M4, N1–N2 pass on the fix, rc 1 on pre-fix 7ac60410 (N1 red); live E2 pending. Landed (2026-11-07, gpt-6-luna worker; Claude moved the guide section and pinned the N2 baseline to 028b898f); bats 43/43, new test red on pre-fix
**Priority:** P3 — cosmetic; every number is correct, but the last rows are cut off and the order cannot be changed
**Waiting on:** live check — since 2026-11-07
**Approval:** operator 2026-11-07 live check: "how do you classify unknown? also it seems number are cut off a bit! can we allow sort on number?"
**Severity:** low

## Symptom

On the Agent Dispatch dashboard, panel id 105 "Verification ladder"
(`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`) is a horizontal bar gauge
with `gridPos.h` 6. It draws one bar per `rung × status` pair of `k3dm_dispatch_ladder_tasks`, which is up
to 15 bars. The panel is too short for all of them, so the last rows ("landed unknown" and below) are
clipped. A bar gauge has no sortable column, so the operator cannot order the rows by count. The panel
description does not say what `unknown` means.

## Root cause

- Layout: 15 bars in a 6-row panel.
- Visualization: a bar gauge cannot sort interactively; a table can (click a column header).
- The meaning of `unknown` lives only in the exporter (`bin/k3dm-dispatch-metrics`, the ladder loop near
  `task_ladder`):
  - `offline_tested`, `deployed`, `live_verified`: `done` when the ledger has a `state_mark` for that
    rung; `unknown` when the task started before the ledger's `gate_coverage_start` marker (the ledger
    did not record rung marks then); `pending` otherwise.
  - `independently_verified`: `done` for a passing `verify` that carries `evidence_sha256`; `unknown` for
    a passing `verify` without it (recorded before evidence validation existed); `pending` otherwise.
  - `implemented` and `landed` are only ever `done` or `pending`; their `unknown` rows are always 0.

## Fix

Dashboard only. No exporter change.

1. Change panel 105 to `"type": "table"`. Keep the same query, as an instant query with `"format": "table"`.
2. Transformations: an `organize` step that keeps only `rung`, `status` and `Value`, in that order, and
   renames `Value` to `tasks`. Hide `Time` and any other label column.
3. `tasks` column: a cell display that shows a bar with the number (`custom.cellOptions` of type
   `gauge`, mode `basic`), so the visual stays. Default sort: `options.sortBy` = `[{"displayName": "tasks",
   "desc": true}]`. Every column header stays sortable (do not set `custom.filterable` or disable sort).
4. Hide always-zero impossible rows: a `filterByValue` transformation that excludes rows where `status` is
   `unknown` **and** `rung` is `implemented` or `landed`. Do not hide any other zero row.
5. Keep the panel's `gridPos` (`x` 12, `y` 65, `w` 12, `h` 6); a table scrolls, so nothing is clipped.
6. Description: keep the words "Self-reported and advisory" (a test requires them), then explain
   `unknown` per rung in one or two sentences, as in Root cause.
7. `docs/guides/grafana-dashboards/k3dm-agent-dispatch.md`: a short "Verification ladder" section with the
   rung and status rules above.
8. `CHANGELOG.md`: one bullet at the end of `[Unreleased]`.
9. Test: add a bats test in `scripts/tests/plugins/agent_dispatch_dashboard.bats` for the Acceptance block.

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (panel 105 only)
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/guides/grafana-dashboards/k3dm-agent-dispatch.md`
- `CHANGELOG.md`

## Gates

`bats scripts/tests/plugins/agent_dispatch_dashboard.bats`, with `/opt/homebrew/bin` first on `PATH`.
Show the new test red on the pre-fix dashboard and green after. Paste counts.

## What NOT to Do

- Do not change `bin/k3dm-dispatch-metrics`, the series, or any other panel (ids, positions, queries).
- Do not change the panel's `id`, `title` or `gridPos`.
- Do not commit, push or create a PR. Claude reviews and commits.
- Do not touch `memory-bank/`, the header of this doc, or files outside the Files list.

## Acceptance

```yaml
interface:
  - "scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml: the agent-dispatch.json panel titled \"Verification ladder\""
  - "docs/guides/grafana-dashboards/k3dm-agent-dispatch.md"
must:
  - id: M1
    text: "The Verification ladder panel is a table whose only visible columns are rung, status and tasks, in that order, from an instant query of k3dm_dispatch_ladder_tasks."
  - id: M2
    text: "The table sorts by tasks descending by default, and the tasks column shows a gauge cell."
  - id: M3
    text: "The panel description keeps \"Self-reported and advisory\" and states when status is unknown for the state-marked rungs (task started before gate coverage) and for independently_verified (pass without evidence hash)."
  - id: M4
    text: "The guide has a Verification ladder section with the same rules."
must_not:
  - id: N1
    text: "Rows with status unknown for rung implemented or landed are not shown; no other row is filtered out (paired control: a zero-count pending row is still shown)."
  - id: N2
    text: "No other panel in agent-dispatch.json changes, and panel 105 keeps its id, title and gridPos."
evidence:
  - id: E1
    proves: [M1, M2, M3, M4, N1, N2]
    kind: offline
    what: "bats on the dashboard JSON and guide; N2 compares every other panel against the pre-fix tree."
  - id: E2
    proves: [M1, M2]
    kind: live
    what: "Operator after make platform-ops/appset sync: the panel shows every row with no clipping and clicking tasks re-sorts it."
```
