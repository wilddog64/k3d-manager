# Bug (child D): stall recovery is invisible on the Agent Dispatch dashboard

**Status:** OPEN
**Priority:** P2 (operator, 2026-11-14)
**Waiting on:** dispatch — since 2026-11-14 (intent approved; queued by file and slot)
**Approval:** operator 2026-11-14 asked for a dashboard to track the stall-recovery loop ("maybe we can build a dashboard to track"); spec drafted by Claude, intent not yet approved
**Release:** v1.45.0 plan 5 `dispatch-stall-recovery` (operator, 2026-11-14: "go with your recommendation"); Fable review findings on the parent apply
**Intent approved:** operator, 2026-11-14
**Introduced by:** pre-existing
**Should have been caught by:** none
**Prior art:** exact-slug glob: none; `docs/bugs/2026-10-11-dispatch-dashboard-no-per-spec-cost-or-time.md` read, different scope (per-spec cost columns, landed); `make find-similar-docs` unavailable on the M4 (vector store needs the hub context)
**Parent:** `docs/bugs/2026-11-14-codex-dispatch-silent-running-raises-no-alert.md`

## Problem

Children A (detector), B (Slack approval) and C (headless diagnosis) add a loop that detects a hung dispatch, kills it,
asks Claude for a correction, asks the operator to approve it, and resumes the run. Nothing shows how often that loop
runs, what it costs, how the operator decided, or whether the resumed runs landed. The operator needs that record for
two decisions:

1. **Phase 2 (auto-resume without approval)** waits on "several phase-1 corrections the operator approved unchanged"
   (parent, Chosen direction). Today nobody counts them.
2. **API credit.** Diagnosis is paid from the $100 credit, which expires 2026-12-08. Only C's per-task
   `primary_coordinator_cost` cell shows any of that spend.

The existing **Stalled tasks** panel (`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml:1788-1802`,
`k3dm_dispatch_stalled_tasks` from `bin/k3dm-dispatch-metrics:2555-2569,2606`) counts tasks with two or more
unsuccessful *finished* attempts (`streak >= 2`). It never counted the 13-hour hang of 2026-11-13, because that run
never finished. Its title invites exactly that misreading.

## Fix

### 1. Ledger events (contract; written by A, B, C)

Each line goes to `$K3DM_WORKTREE_ROOT/ledger.jsonl` (default `~/.local/share/k3d-manager/worktrees/ledger.jsonl`) with the
fields `ts` (epoch number), `version` and `slug`. `stall` is the evidence directory's basename (`stall-<ts>`) and joins
the events of one incident.

| Event | Writer | Extra fields |
|---|---|---|
| `stall_detected` | A, `bin/k3dm-dispatch-stall-watch`, after capture and kill | `stall`, `run` (prompt number), `reason` (`silent` or `procs`), `silent_s`, `procs`, `killed` |
| `stall_diagnosis` | C, `bin/k3dm-dispatch-stall-diagnose`, once per run | `stall`, `status` (C's status word), `cost_usd` (this run only, 0 when none) |
| `stall_proposal` | B, `bin/k3dm-dispatch-recover` propose half | `stall`, `action_id` (`d1-<hex8>`) |
| `stall_decision` | B, drain half | `stall`, `decision` (`approved`, `denied`, `expired`, `precondition_failed`) |
| `stall_resume` | B, drain half, after `codex-dispatch resume` returns | `stall`, `rc` |

A, B and C each add one requirement and one offline test to their own specs: the event is written with these fields
and without the API key, the drain token or any prompt text. D defines the schema and reads it; D writes no events.
Writers use the existing `_dispatch_ledger_event_best_effort` (`bin/k3dm-codex-dispatch:34`) where they are bash, or the
same append-one-line-with-flock behaviour where they are Python; a failed write never changes the writer's exit code.

### 2. Exporter (`bin/k3dm-dispatch-metrics`)

- Add the five names to the set of events that `_task_states` skips (`NEW_S1_EVENTS`, used at `:878`), so the existing
  task-state, running, rework, stall-streak and cost metrics are byte-identical with and without them.
- Emit, per version (labels `version`, plus the listed ones; values from the current version's events):
  - `k3dm_dispatch_stall_incidents{reason}`: count of `stall_detected`.
  - `k3dm_dispatch_stall_silent_seconds_median`: median `silent_s`.
  - `k3dm_dispatch_stall_diagnoses{status}`: count of `stall_diagnosis`.
  - `k3dm_dispatch_stall_diagnosis_cost_usd`: sum of `cost_usd`.
  - `k3dm_dispatch_stall_diagnosis_cost_all_versions_usd` (no version label): sum over every version since
    2026-11-14, the figure to compare with the $100 credit.
  - `k3dm_dispatch_stall_decisions{decision}`: count of `stall_decision`.
  - `k3dm_dispatch_stall_decision_minutes_median`: median minutes from `stall_proposal` to `stall_decision`, same `stall`.
  - `k3dm_dispatch_stall_outcomes{outcome}`: for each `stall_resume` with rc 0, the first later event for that slug:
    `land` → `landed`, `stall_detected` → `stalled_again`, `abandon` → `abandoned`, nothing yet → `pending`.
  - `k3dm_dispatch_stall_clean_approvals`: incidents with decision `approved`, outcome `landed`, and no `resume` with
    `--reason correction` between that `stall_resume` and the `land`. This is the phase-2 count: Claude's correction,
    approved, landed without another human correction.
  - `k3dm_dispatch_task_stall_incident{slug,stall,reason,diagnosis,decision,outcome}` = `silent_s`, one series per
    incident, for the table.
- Every label value goes through the existing label sanitiser (the function ending at `:858`).

### 3. Dashboard (`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`)

- Retitle the existing panel to **Repeated failed attempts** and set its description to "Tasks whose last two or more
  finished attempts were unsuccessful. A run that hangs without exiting shows under Stall recovery." Query unchanged.
- New collapsed-by-default row **Stall recovery** after the row holding that panel, filtered by the dashboard's existing
  version variable:
  - Stat **Hangs detected** (`sum(k3dm_dispatch_stall_incidents)`), stat **Median silence before detection**
    (minutes).
  - Bar gauge **Diagnoses by result** (`k3dm_dispatch_stall_diagnoses` by `status`).
  - Stat **Diagnosis spend, all releases** (USD) with thresholds green < 50, yellow < 80, red ≥ 80, and the description
    "Paid from the $100 API credit, which expires 2026-12-08."
  - Bar gauge **Operator decisions** (`k3dm_dispatch_stall_decisions` by `decision`), stat **Median minutes to
    decide**.
  - Bar gauge **After resume** (`k3dm_dispatch_stall_outcomes` by `outcome`).
  - Stat **Clean approvals (phase 2 gate)** (`k3dm_dispatch_stall_clean_approvals`), description "Claude's correction
    approved unchanged and landed with no further correction. Auto-resume is considered only after several."
  - Table **Incidents**: one row per `k3dm_dispatch_task_stall_incident` series; columns slug, stall, reason, silent
    minutes, diagnosis, decision, outcome.
- No-data panels show 0, not "No data", when the version has no incidents (`or vector(0)` on the stats).

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/howto/agent-dispatch-dashboard.md` if it exists, otherwise the dashboard section of `docs/guides/` that
  describes the Agent Dispatch dashboard (worker greps and names the file it edits)
- (not `CHANGELOG.md`: `parallel-offline-tests-b` has it open; Claude adds the entry at land, operator 2026-11-14)

## Contract readers

Contract: ledger events `stall_detected`, `stall_diagnosis`, `stall_proposal`, `stall_decision`, `stall_resume` in
`ledger.jsonl` (new names).

- Writers: A, B and C (above); no existing writer. `bin/k3dm-codex-dispatch:14,34` are the shared append helpers.
- Readers that see every event: `bin/k3dm-dispatch-metrics` `read_ledger` (`:861-873`, needs numeric `ts`) and
  `_task_states` (`:876-883`, changed to skip the new names); `bin/k3dm-codex-dispatch` `_dispatch_open` (`:1302-1303`,
  looks only for `start`, `land`, `abandon`: unaffected) and `_dispatch_abandon_check_ledger` (`:1379-1402`, worker
  confirms by reading it that unknown names are ignored, and adds a test if not); `bin/k3dm-dispatch-logs` (worker greps
  for `ledger` and lists each reader found, with what it does with an unknown event name).

Contract: dashboard panel title `Stalled tasks`.

- Readers: `scripts/tests/plugins/agent_dispatch_dashboard.bats` and `scripts/tests/plugins/grafana_dashboard_bugs.bats`
  (worker greps both for `Stalled tasks` and updates each hit), the two fixtures under `scripts/tests/fixtures/` (left
  unchanged: they pin older dashboard versions).

## Acceptance

```yaml
must:
  M1: with a scratch ledger holding one full incident (detected, diagnosis ok with cost 0.42, proposal, decision approved, resume rc 0, land), the exporter's --dry-run prints every k3dm_dispatch_stall_* series listed in Fix 2 with the expected values, including outcome landed and clean_approvals 1
  M2: a second incident whose resume is followed by another stall_detected counts as stalled_again and leaves clean_approvals at 1; a third that is denied counts under decision denied and has no outcome
  M3: diagnosis_cost_all_versions_usd sums cost_usd across two versions while diagnosis_cost_usd counts only the selected version
  M4: the dashboard JSON has the retitled panel with the new description and unchanged query, and a Stall recovery row whose panels query exactly the metrics named in Fix 3
  M5: a version with no stall events renders 0 on the stat panels (or vector(0) present), not an absent series
must_not:
  N1: adding the five events to a ledger changes any existing metric line in --dry-run output (golden comparison of all non-stall lines with and without the events; positive control: adding a land event to the same fixture does change a line, so the comparison can fail)
  N2: an event with a quote, backslash or newline in slug or stall produces an unescaped label value
  N3: a malformed stall event (ts missing, or a non-numeric silent_s or cost_usd) stops the exporter or drops non-stall metrics; it is counted as bad or skipped
  N4: any test reaches a real Pushgateway, the real ledger or the real HOME
evidence:
  - {id: E1, proves: [M1, M2, M3, N2, N3], kind: offline, intent: "You will see pytest cases build a scratch worktree root (asserted not to be your real one), write hand-made ledgers with one to three stall incidents, run the real exporter with --dry-run and the Pushgateway pinned to 127.0.0.1:9, and check each new metric line and value. On today's exporter these lines do not exist, so every case fails."}
  - {id: E2, proves: [N1], kind: offline, intent: "You will see the exporter's full output for one ledger compared line by line with the same ledger plus five stall events: only k3dm_dispatch_stall_* lines differ. A control adds a land event instead and the comparison catches the change, which shows the check can fail. On today's exporter the stall events reach the task-state code, and the test shows whether that changes any line."}
  - {id: E3, proves: [M4, M5], kind: offline, intent: "You will see the dashboard bats suite read the dashboard YAML with yq and find the panel now titled Repeated failed attempts with its old query, the new Stall recovery row, and each new panel's exact query. On today's dashboard none of these exist, so the new tests fail."}
  - {id: E4, proves: [N4], kind: offline, intent: "You will see each new test assert first that HOME, the ledger path and the Pushgateway URL point at the scratch fixture, before it runs anything."}
  - {id: E5, proves: [M4], kind: live, intent: "After the platform-ops sync, you (or Claude, read-only) open the Agent Dispatch dashboard on the hub and see the Stall recovery row with zeros for v1.44.0 and the retitled panel. Claude captures a screenshot or the Grafana API panel list."}
interface:
  - "ledger events stall_detected, stall_diagnosis, stall_proposal, stall_decision, stall_resume (schema in Fix 1)"
  - "metrics k3dm_dispatch_stall_* and k3dm_dispatch_task_stall_incident"
  - "dashboard row Stall recovery; panel retitled Repeated failed attempts"
```

## Order

D reads events that A, B and C write, and works with none present (all zeros). It shares no file with A, B or C, so it
can be dispatched beside them within the WIP limit. A, B and C each gain one event requirement when their specs are
revised after the 2026-11-14 spec review.
