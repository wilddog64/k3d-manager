# Bug: Agent Dispatch Per spec and Per run evidence show no tokens or time for an agy-landed spec

**Status:** PARTLY FIXED 2026-10-25 — F1 (Agent column, Claude) and F2/F3 (agent-neutral series, Luna, landed `be7ef686`; 89/89 pytest, new tests red on the pre-fix script, ruff clean) done; F4 dashboard (Claude) pending
**Priority:** P3
**Severity:** low — the ledger has the data; the dashboard hides it, so agy and Codex cannot be compared per spec
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the operator's screenshots 232 and 233
**Approval:** explicit 2026-10-25 ("let's do that in v1.43.7", after Claude proposed both parts). Not critical (metrics script and one dashboard ConfigMap).
**Component:** `bin/k3dm-dispatch-metrics`, `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`
**Related:** `docs/bugs/2026-10-24-agent-dispatch-run-evidence-table-unreadable.md`

## Problem

On k3dm Agent Dispatch, the Per spec row for v1.43.6 `claude-context-compaction-metrics-agy` shows
only Time to land (21.4 min). In Per run evidence the same run shows no tokens.

1. Per spec does not say which agent landed a spec. A blank Codex column reads as missing data.
2. `_render` emits `k3dm_dispatch_task_codex_tokens`, `task_codex_seconds` and `task_runs` only
   when `agent == "codex"`, and `_run_metrics` sets a run's tokens only from `codex_exit`. That
   split is deliberate (`test_agy_usage_never_enters_codex_token_series`: agy tokens must never
   enter a Codex series) and stays.
3. No agent-neutral series exists, so agy's usage is lost to the dashboard. Its `agent_exit`
   event records `usage.total_tokens` (484,346 for this run).

## Fix

### F1 (Claude, done). Agent column on Per spec

Panel 12 target E groups by `agent` too (`max by (version, slug, spec, agent)`). The `organize`
step places `agent` after `slug` and renames it `Agent`. BATS test 19 covers it.

### F2 (Luna). Agent-neutral per-spec series

In `bin/k3dm-dispatch-metrics`, `_task_metrics` additionally returns:

- `agent_tokens`: the last `codex_exit.tokens` that is an int (Codex tokens are cumulative across
  resumes), plus the sum of `usage.total_tokens` over every `agent_exit` whose value is a
  non-negative int (agy reports per run). `None` when neither exists.
- `agent_seconds`: the `codex_seconds` pairing, over all exits (`codex_exit` and `agent_exit`):
  each exit pairs with the latest `start`/`resume` after the previous exit.

`_render` emits, for every task and agent (`codex`, `agy`, `other`), with the existing task labels:

- `k3dm_dispatch_task_agent_tokens{...}` when `agent_tokens` is not `None`;
- `k3dm_dispatch_task_agent_seconds{...}` when the task has at least one exit;
- `k3dm_dispatch_task_agent_runs{...}` = number of exits, when at least one.

The existing `task_codex_tokens`, `task_codex_seconds` and `task_runs` lines do not change.

### F3 (Luna). Agent-neutral per-run tokens

In `_run_metrics`, each row also carries `agent_tokens`: the Codex increment already computed for
a `codex_exit`, or that `agent_exit`'s `usage.total_tokens` when it is a non-negative int. `_render`
emits `k3dm_dispatch_task_run_agent_tokens{<run labels>}` when it is an int. The existing
`task_run_codex_tokens` line does not change.

### F4 (Claude, after F2/F3 land). Dashboard

Per spec targets A, B, D move to `task_agent_tokens`, `task_agent_seconds`, `task_agent_runs`, renamed
Tokens, Agent time, Runs. Per run evidence target B moves to `task_run_agent_tokens`, renamed Tokens.
API equiv. stays Codex-only: there is no agy pricing.

## Tests

Add to `scripts/tests/bin/test_dispatch_metrics.py`:

1. An agy task (start agent agy, `agent_exit` with `usage.total_tokens` 500, land) emits
   `task_agent_tokens ... 500`, `task_agent_seconds`, `task_agent_runs ... 1`, and still no
   `task_codex_tokens{`.
2. A Codex task emits `task_agent_tokens` equal to its `task_codex_tokens` and `task_agent_seconds`
   equal to its `task_codex_seconds`.
3. An agy task with two runs (totals 300 and 200) emits `task_agent_tokens ... 500` and runs 2.
4. An agy `agent_exit` with no `usage`, or a non-int / negative / boolean `total_tokens`, emits no
   `task_agent_tokens` line and does not raise.
5. Per run: the agy run emits `task_run_agent_tokens{...,run="1"} 500` and no
   `task_run_codex_tokens`; a Codex run's `task_run_agent_tokens` equals its
   `task_run_codex_tokens`.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `docs/guides/grafana-dashboards.md` (one sentence: agent-neutral series exist and what agy's
  total counts)
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: A landed agy task exports agent-neutral tokens (sum of agent_exit usage.total_tokens), agent seconds and agent runs.
  - id: M2
    text: A landed Codex task exports agent-neutral tokens and seconds equal to its existing Codex series.
  - id: M3
    text: Each agy run exports its own total_tokens as agent-neutral per-run tokens.
  - id: M4
    text: Per spec shows which agent landed each spec.
must_not:
  - id: N1
    text: agy tokens must not appear in any task_codex_* or task_run_codex_tokens series.
  - id: N2
    text: Missing or malformed agy usage must not raise or emit an agent-neutral tokens line.
  - id: N3
    text: Existing task_codex_tokens, task_codex_seconds, task_runs and task_run_codex_tokens output must not change.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N3]
    text: pytest scripts/tests/bin/test_dispatch_metrics.py green with tests 1-5; tests 1, 3 and 5 red on a temp copy of the pre-fix script; ruff 0.15.8 clean.
  - id: E2
    kind: offline
    proves: [M4]
    text: agent_dispatch_dashboard.bats 19/19; test 19 red on the pre-fix dashboard.
  - id: E3
    kind: live
    proves: [M1, M3, M4]
    text: After F4 and a hub sync, the claude-context-compaction-metrics-agy rows show agy, 484 K tokens and agent time.
interface:
  - bin/k3dm-dispatch-metrics --dry-run (Prometheus text on stdout)
  - dispatch_metrics.render(events, start, end) as imported by test_dispatch_metrics.py
  - Grafana /d/k3dm-agent-dispatch
```

## Definition of Done

- [ ] F2, F3 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9 pytest scripts/tests/bin/test_dispatch_metrics.py` green; paste the summary.
- [ ] Tests 1, 3 and 5 shown red on a temp copy of the pre-fix script.
- [ ] Commit: `fix(dispatch-metrics): export agent-neutral tokens, time and runs for agy tasks`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT change or remove any existing `task_codex_*`, `task_runs` or `task_run_codex_tokens` line or test.
- Do NOT edit the dashboard YAML (F1 and F4 are Claude's).
- Do NOT push to the real Pushgateway or read the real ledger.
- Do NOT modify files outside the Files list.
