# Bug: dispatch API cost is windowed by when the ledger event was written, so Projected / month is inflated

**Status:** LIVE-VERIFIED 2026-10-24 (E2) — operator screenshot: Agent Dispatch, Window 7d, Projected / month $1.08K = (Luna $3.56 + Claude $249.11) ÷ 7.00 days × 30 ≈ $1,083; By model gpt-5.6-luna $1.09 + gpt-6-luna $2.56. Claude half: `bin/k3dm-dispatch-metrics --dry-run` at `1e80a6d3`: 7d API cost $3.65 < 30d $9.97; observed_days printed (7d = 7.00). Deployed ConfigMap `monitoring/grafana-dashboard-agent-dispatch` Projected / month expression matches the repo (7d cost ÷ observed_days × 30, Luna + Claude); expected ≈ $1,073 from the dry run (Luna $3.56 + Claude $246.81 over 7.00 days). Was LANDED `f8dbf7b6` 2026-10-24 — E1 green (43 pytest; the 3 new tests and the dashboard test red on the pre-fix code). E2 dry run: 1d $0.79, 7d $3.48, 30d $9.61 (were all $9.61); observed days 1.00 / 7.00 / 14.12; Projected ≈ $14.89 (was $41.2). Dashboard part pending the Argo hard refresh.
**Priority:** P2
**Fix commit:** `f8dbf7b6`
**Live evidence:** 2026-10-24 · run operator-screenshot-agent-dispatch-projected-month · env hub · scenario projected-month-from-7d-observed-days · commit e8e899e1 · proves E2
**Severity:** medium — the cost totals are right, but the 1d/7d windows and Projected / month overstate recent spend
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude, answering the operator's cost-model questions (token semantics, cache, model, coverage, time windows)
**Approval:** explicit 2026-10-23. The operator said: "go as you suggested" (file the windowing bug, then dispatch it after the By model fix landed).

**Component:** `bin/k3dm-dispatch-metrics` (`_render_scope`), `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` (panel 25 "Projected / month")

## Problem

`_render_scope` selects ledgered Codex usage for a time window by the `codex_usage` event's `ts`:

```python
usage = {key: item for key, item in usage.items()
         if item.get("ts", 0) >= now - WINDOWS[window]}
```

`ts` is when the event was written to the ledger, not when the session ran. On 2026-10-23 at 16:53
PDT, `usage-backfill` wrote 127 events for sessions going back to early October. Every one of them
now counts as "last 7 days" (and "last 1 day" until tomorrow), so 7d and 30d show the same API cost.

Two consequences:

1. Panel 25 computes `k3dm_dispatch_api_cost_usd{window="7d"} * 30 / 7`, so Projected / month scales
   three weeks of work as if it were one.
2. Coverage (`k3dm_dispatch_codex_sessions`, `k3dm_dispatch_unledgered_api_cost_usd`) selects by the
   session's start time, read from the Codex session file. The cost and coverage panels on the same
   row therefore use different clocks.

Projected / month also assumes the 7d window holds 7 full days of data. When the ledger's earliest
session is less than 7 days old, it under-scales instead.

## Fix

### F1. Window ledgered usage by session start

In `_render_scope`, for time scopes only, select a ledgered session by its start time, the same
`start` that coverage uses. `main` already builds the coverage list from `_session_files`; pass a
`session → start` map built from it into `_render_scope` (or reuse `coverage` directly).

- A ledgered session whose session file is in the scan is in the window when
  `_timestamp(start) >= now - WINDOWS[window]`.
- A ledgered session with no session file in the scan is excluded from time windows. The scan
  covers files modified in the last 30 days, so such a session is older than every window.
- Release scopes are unchanged: they still select by `version`.

### F2. Emit the observed span

For each time window, emit `k3dm_dispatch_api_cost_observed_days{window}`: the number of days the
window actually covers,
`min(window_days, (now - earliest start among ledgered sessions in the scan) / 86400)`, rounded to
2 decimals. Emit `0` when no ledgered session is in the scan.

### F3. Projected / month

Panel 25's expression becomes
`k3dm_dispatch_api_cost_usd{window="7d"} / k3dm_dispatch_api_cost_observed_days{window="7d"} * 30`.
A zero span yields no value, which shows as No data; that is correct.

Panel 25's description: replace "Last 7 days of Codex usage at API prices, scaled to 30 days." with
"Codex usage at API prices over the last 7 days (or since the ledger's first session, if newer),
by session start time, scaled to 30 days." Keep the rest of the description.

### F4. Guide

`docs/guides/grafana-dashboards.md`, Agent dispatch cost section: one or two sentences saying that
time windows count a session by when it started, and that Projected / month divides by the days
actually observed.

## Tests

`scripts/tests/bin/test_dispatch_metrics.py`. Use a temp `CODEX_HOME` with session files; never the
real `~/.codex`.

1. A `codex_usage` event written now for a session that started 20 days ago counts in 30d but not in
   7d or 1d.
2. A session that started 2 days ago, whose event was written 2 days ago, counts in 7d and 30d.
3. A ledgered session with no session file in the scan is in no time window, but still in its
   release scope.
4. `k3dm_dispatch_api_cost_observed_days`: 7 when the earliest ledgered session started 20 days ago;
   3 (±0.01) when it started 3 days ago; 0 with no ledgered sessions.
5. Panel 25's expression divides by `k3dm_dispatch_api_cost_observed_days{window="7d"}`.

Show tests 1, 3, 4 and 5 red against the pre-fix exporter and dashboard on a temp copy.

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
    text: In a time window, a ledgered Codex session's API cost counts only if the session started inside that window.
  - id: M2
    text: k3dm_dispatch_api_cost_observed_days{window} is the number of days the window covers, capped at the window length, from the earliest ledgered session start; 0 when there is none.
  - id: M3
    text: Projected / month is the 7d API cost divided by the observed 7d span, times 30.
  - id: M4
    text: The guide says time windows count sessions by start time and Projected divides by observed days.
must_not:
  - id: N1
    text: A codex_usage event written now for a session that started more than 7 days ago must not count in the 7d or 1d window.
  - id: N2
    text: Release-scope cost series must not change.
  - id: N3
    text: Coverage series (k3dm_dispatch_codex_sessions, k3dm_dispatch_unledgered_api_cost_usd) must not change.
  - id: N4
    text: Tests must not read the real ~/.codex or push to the live Pushgateway.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, N1, N2, N3, N4]
    text: pytest scripts/tests/bin/test_dispatch_metrics.py green; tests 1, 3, 4, 5 red on the pre-fix code.
  - id: E2
    kind: live
    proves: [M1, M3]
    text: Claude runs the exporter with --dry-run; 7d API cost is below 30d, and the observed span is printed. After the Argo hard refresh, the operator's screenshot shows Projected / month from the new expression.
interface:
  - bin/k3dm-dispatch-metrics (--dry-run; env CODEX_HOME; ledger codex_usage events)
  - series k3dm_dispatch_api_cost_usd{window}, k3dm_dispatch_api_cost_observed_days{window}
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml (panel 25 "Projected / month")
```

## Definition of Done

- [ ] F1–F4 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `pytest scripts/tests/bin/test_dispatch_metrics.py` green; paste the summary.
- [ ] Tests 1, 3, 4 and 5 shown red on a temp copy of the pre-fix code.
- [ ] Commit: `fix(dispatch): window API cost by session start and normalize Projected`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT read the real `~/.codex`, query the live Prometheus or Grafana, or push to the Pushgateway.
- Do NOT run `usage-backfill`.
- Do NOT change the price file, the ledger format or `bin/k3dm-codex-dispatch`.
- Do NOT model long-context or cache-write pricing, or per-turn model pricing; those are out of scope.
- Do NOT modify files outside the Files list.
