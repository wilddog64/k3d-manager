# Bug: the Bugs dashboard shows "fix running" after the worker has exited

**Status:** LANDED `bcf7b31d` 2026-11-07 (Flash; reviewed and landed by Claude, land tests green); independent verifier not yet run
**Priority:** P3
**Waiting on:** live check — since 2026-11-07
**Fix commit:** `bcf7b31d`
**Severity:** low — the dashboard misstates what a bug is waiting for; the operator has to ask Claude to triage by hand
**Approval:** operator, 2026-11-07 ("go ahead to file a P3 bug then dispatch to Flash 3.8")
**Assigned:** Flash 3.8 (`AGENT=agy MODEL=gemini-3.8-flash-medium`)
**Filed:** 2026-11-07
**Detected by:** Claude, triaging the seven v1.43.15 rows on the operator's request ("can you triage these bugs and update their status?")
**Affected:** `bin/k3dm-dispatch-metrics`, the Bugs dashboard table (`scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`)
**Branch:** `k3d-manager-v1.43.15`
**Related:** `docs/bugs/2026-11-06-hub-code-lag-invisible-and-no-catch-up-step.md` (tile 19 "Hub code behind" already flags a hub checkout that is not on the newest release; this bug is the per-bug check it does not cover)

## Observed failure

On 2026-11-07 the Bugs dashboard showed four v1.43.15 bugs as `Waiting on: fix running`. When Claude checked the
dispatch run directories, only one worker was alive (`2026-11-07-machine-setup-tests-inherit-caller-tty`). The
other three (`2026-11-02-hub-data-export-never-ran`, `2026-11-07-e2e-results-never-reach-m5-hub`,
`2026-11-07-claude-tokens-per-day-chart-crowded-labels`) had exited hours earlier and their changes were waiting for
Claude's verification. Nothing on the dashboard showed that the doc's claim no longer held.

## Root cause

`Waiting on` is a claim written into the doc at dispatch time. Nothing checks it afterwards.

The evidence that would check it exists but is not published for bugs. `bin/k3dm-dispatch-metrics:2443-2461` emits
`k3dm_dispatch_plan_state{plan,version,slug,dispatch_state}` (values from `_dispatch_state`, `:804`: `running`,
`awaiting_land`, `landed`, `abandoned`, ...) only for specs whose stem matches `PLAN_STEM_RE`
(`^v\d+\.\d+\.\d+-...`, `:36`). A dispatch of a `docs/bugs/2026-11-07-<slug>.md` spec fails that match and is only
counted in `k3dm_dispatch_plan_state_skipped`. Live on 2026-11-07 the hub had `plan_state` for the three v1.43.15
plan dispatches and nothing for the four bug dispatches.

## Fix

1. `bin/k3dm-dispatch-metrics`: beside `k3dm_dispatch_plan_state`, emit
   `k3dm_dispatch_bug_state{bug="<stem>",version="<version>",slug="<slug>",dispatch_state="<state>"} 1` for each
   task whose latest `start` event has a `spec` of the form `docs/bugs/<stem>.md`, with `<stem>` matching
   `^\d{4}-\d{2}-\d{2}-[a-z0-9][a-z0-9-]*$`. Use the latest start per stem, as the plan loop does, and the same
   `_dispatch_state`. Do not change `k3dm_dispatch_plan_state` or how `k3dm_dispatch_plan_state_skipped` is counted.
2. Bugs dashboard table (the panel whose query starts at `grafana-dashboard-bugs.yaml:1098`): add a `State check`
   column, joined on `bug`, using the table's existing join pattern. Values:
   - `no worker running (<dispatch_state>)`: `waiting_on="fix running"`, and the bug's `k3dm_dispatch_bug_state`
     is not `running`;
   - `no dispatch recorded`: `waiting_on="fix running"`, and there is no `k3dm_dispatch_bug_state` for the bug;
   - `already dispatched (<dispatch_state>)`: `waiting_on="dispatch"`, and a `k3dm_dispatch_bug_state` exists;
   - `unchecked`: the dispatch metrics are older than 30 minutes, measured with the timestamp series
     `bin/k3dm-dispatch-metrics` already pushes (confirm which one marks the push, e.g.
     `k3dm_dispatch_ledger_timestamp_seconds`, and name it in your final message);
   - `ok`: everything else.
   Mismatch values get a warning colour; `ok` stays plain.
3. Document the column in `docs/guides/grafana-dashboards/k3dm-bugs.md`: what each value means and what to do
   about it (verify the worker's changes, or update the doc's `Waiting on`).

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/grafana_dashboard_bugs.bats`
- `docs/guides/grafana-dashboards/k3dm-bugs.md`

## What NOT to do

- Do not change `bin/k3dm-vectordb-metrics` or the `k3dm_bug_info` labels. In particular, keep `waiting_on` as
  `-` for fixed bugs; `test_bug_metrics_waiting_on_labels_are_safe_and_status_gated` pins that, and fixed rows use
  the Verified and Live-verified columns instead.
- Do not edit any `docs/bugs/` doc to make the check pass.
- Do not add a new Grafana field matcher id without checking it against Grafana 11.4.0's registry. The `byRefId`
  crash (`docs/bugs/2026-11-07-hub-code-behind-tile-unknown-matcher-crashes-bugs-dashboard.md`) came from an
  invented id that the test asserted as well.
- Do not touch tile 19 (`Hub code behind`) or the release filter.
- Do not run git add, commit or push, and do not touch `memory-bank/`.

## Acceptance

```yaml
must:
  M1: a dispatch whose latest start has spec docs/bugs/<stem>.md produces exactly one k3dm_dispatch_bug_state series with bug=<stem> and the task's dispatch_state
  M2: plan dispatches still produce k3dm_dispatch_plan_state exactly as before, and the skipped count is unchanged for the same ledger
  M3: the Bugs table shows a State check column with the five values defined in the Fix, joined on bug
  M4: the guide documents each State check value and the action it calls for
must_not:
  N1: a bug whose doc says "fix running" while its latest dispatch has exited never shows "ok"
  N2: a bug whose doc says "fix running" while its dispatch is running never shows a mismatch (paired control for N1)
  N3: stale dispatch metrics (older than 30 minutes) never produce a mismatch value; they show "unchecked"
  N4: a spec path outside docs/bugs/ or a stem that fails the date-slug pattern never produces k3dm_dispatch_bug_state
evidence:
  E1:
    proves: [M1, M2, N4]
    kind: offline
    intent: >-
      You will see test_dispatch_metrics.py feed a fixture ledger with one plan start, one bug start that has exited,
      one bug start still running and one start whose spec is outside docs/bugs/, and assert the series emitted for
      each. The bug_state assertions are red on the pre-fix exporter.
    what: python3 -m pytest scripts/tests/bin/test_dispatch_metrics.py
  E2:
    proves: [M3, N1, N2, N3]
    kind: offline
    intent: >-
      You will see grafana_dashboard_bugs.bats assert the State check queries, the join on bug, the five values and
      the freshness guard; the N1 and N3 assertions are red on the pre-fix dashboard. Any matcher or transformation
      id the panel uses is one from Grafana 11.4.0's registry.
    what: bats scripts/tests/plugins/grafana_dashboard_bugs.bats
  E3:
    proves: [M3, N1, N2]
    kind: live
    intent: >-
      Claude or the operator opens the Bugs dashboard on the hub after the ApplicationSets read the fix branch and
      sees an exited bug dispatch shown as "no worker running" and a running one shown as "ok".
    what: Bugs dashboard on grafana.3ai-talk.org
interface:
  - bin/k3dm-dispatch-metrics (Prometheus text output)
  - scripts/etc/argocd/platform-ops/grafana-dashboard-bugs.yaml (Bugs table panel)
```
