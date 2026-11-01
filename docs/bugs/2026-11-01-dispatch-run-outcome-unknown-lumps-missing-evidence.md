# Bug: "Run outcomes" labels 199 runs `unknown` although the ledger says why each has no verdict

**Status:** FIXED — `9146f9f7` (Codex; Claude review, independent verify); E2 (live) pending
**Fix commit:** 9146f9f7
**Priority:** P3
**Severity:** low — the bar gauge and the 35.8% coverage read as "two thirds of runs went nowhere"; the counts are right but one label hides three different reasons
**Approval:** operator, 2026-11-01 ("it possible a good idea not to label everything as unknown")
**Filed:** 2026-11-01
**Detected by:** operator (screenshot 519, Agent Dispatch "Run outcomes"), breakdown by Claude
**Affected:** `bin/k3dm-dispatch-metrics` (`_run_outcomes`, ~lines 999-1100; `k3dm_dispatch_run_outcomes`), `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` ("Run outcomes", "Run outcome coverage" descriptions)
**Branch:** `k3d-manager-v1.43.13`
**Related:** `docs/plans/v1.43.6-dispatch-verified-delivery-cost.md` (defines the outcome classes; "`unknown` otherwise")

## Observed

On Window 30d: accepted 96, failed 13, progress 0, rework 2, **unknown 199**, coverage 35.8%. A read of
`~/.local/share/k3d-manager/worktrees/ledger.jsonl` on the M4 (2026-11-01, same rules as the exporter) splits the 199:

| Count | Ledger fact |
|---|---|
| 144 | the task landed, but its `land` event has no `tree`/`test_result` (lands before v1.43.6: v1.43.5 has 94) |
| 34 | the run exited 0 and a later run of the same task followed it |
| 21 | the task never landed and was never abandoned (17 single-run, 4 with later runs) |

## Root cause

`_run_outcomes` falls through to `outcome, evidence = "unknown", "none"` for every run that is not accepted,
refused or failed. It never looks at the facts it already has: whether the land predates evidence recording, whether a
later run exists, and whether the task is still open.

## Fix

Replace the single fallback with labels named for the ledger fact, checked in this order:

1. `unrecorded` — the task has a `land` event without `tree` or `test_result`.
2. `superseded` — a later `start`/`resume` of the same task follows this run's exit.
3. `open` — no `land` and no `abandon`, and the task's last event is newer than 7 days.
4. `stale` — no `land` and no `abandon`, and the task's last event is 7 days old or older.
5. `unknown` — anything left.

Keep `accepted`, `progress`, `rework` and `failed` and their rules unchanged. Keep the coverage formula unchanged:
the new labels do not count as covered, because none of them is a verdict. Update the dashboard descriptions of both
panels to define each label in one line, and list the new labels in "Run outcomes" in the order above, after
`failed`.

Layout: "Run outcomes" (panel 43, `h: 6`, `w: 6`, `y: 33`, `namePlacement: left`) goes from 5 to 9 rows. Raise the
whole `y: 33` row to `h: 9` (panels 43, 44, 45, 46, so the row stays level) and shift every panel at `y >= 39`
down by 3. Keep `namePlacement: left` and `orientation: horizontal`, and set `minVizHeight: 20` so each of the 9
rows keeps a readable bar and its full name ("superseded" and "unrecorded" untruncated at `w: 6`).

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `CHANGELOG.md`

## What NOT to do

- Do not rewrite or backfill `ledger.jsonl`.
- Do not count the new labels as covered, and do not change the coverage formula.
- Do not edit `scripts/tests/fixtures/agent-dispatch-dashboard-pre-split.yaml`.
- Tests build a scratch ledger (asserted not to be the real one); the event shapes copy real ledger lines (M4,
  2026-11-01) with the host and date in a comment.

## Acceptance

```yaml
must:
  M1: a run whose task has a land event without tree/test_result is labelled unrecorded
  M2: a run exiting 0 that is followed by a later launch of the same task, with no refusal between, is labelled superseded
  M3: a run of a task with no land and no abandon is labelled open when the task's last event is under 7 days old, stale at 7 days or more
  M4: the sum over all outcome labels equals the run total before the change for the same ledger
  M5: panels 43-46 have h 9 at y 33, panel 43 keeps namePlacement left with minVizHeight 20, and every panel previously at y >= 39 moves down by exactly 3
must_not:
  N1: a run that meets the accepted, rework or failed rule never gets a new label (paired control: the same fixtures still yield accepted/rework/failed)
  N2: k3dm_dispatch_run_outcome_coverage is unchanged for the same ledger
  N3: no other metric name or label set changes
  N4: no gridPos rectangles overlap or leave a gap, and no panel other than 43-46 changes anything but its y
evidence:
  E1:
    proves: [M1, M2, M3, M4, M5, N1, N2, N3, N4]
    kind: offline
    intent: You will see pytest build a scratch ledger with one task per case and assert each label (M1-M3 red on the pre-fix exporter, which says unknown), the label total equals the old total, the accepted/rework/failed fixtures keep their labels, and coverage is equal to the pre-fix value.
    what: pytest scripts/tests/bin/test_dispatch_metrics.py; bats scripts/tests/plugins/agent_dispatch_dashboard.bats (layout assertions for M5/N4)
  E2:
    proves: [M1, M2, M3]
    kind: live
    intent: You will see, after the hub syncs, Run outcomes on Window 30d show unrecorded about 144, superseded about 34, open plus stale about 21, and unknown near 0, every name readable beside its bar.
    what: operator screenshot of /d/k3dm-agent-dispatch
interface:
  - bin/k3dm-dispatch-metrics (Prometheus text output)
  - k3dm_dispatch_run_outcomes{window,outcome}, k3dm_dispatch_run_outcome_coverage{window}
  - ledger.jsonl under K3DM_WORKTREE_ROOT
  - Grafana /d/k3dm-agent-dispatch
```

## Verification (2026-11-01, Claude)

- Landed as `9146f9f7` through `make codex-land`; the ledger records `land` and `verify` events for slug `2026-11-01-dispatch-run-outcome-unknown-lumps-missing-evidence`.
- Offline evidence: `/opt/homebrew/bin/python3 -m pytest -q scripts/tests/bin/test_dispatch_metrics.py && bats scripts/tests/plugins/agent_dispatch_dashboard.bats`: rc 0; fast gate passed. Independent black-box verifier (Sonnet, tests written from the Acceptance block only): PASS; M1-M4 red on pre-fix code, M5/N4 layout ok, N3 61 metric signatures identical.
- Errors seen: a CHANGELOG rebase conflict, resolved by keeping both entries.
- E2 (live) pending: after `make platform-ops` and an exporter run, Run outcomes shows the nine labels.
