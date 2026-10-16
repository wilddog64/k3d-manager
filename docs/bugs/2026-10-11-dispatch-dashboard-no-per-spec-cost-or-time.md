# Bug: the Agent Dispatch dashboard shows an unreadable token average and no per-spec cost or time

**Filed:** 2026-10-11
**Branch:** `k3d-manager-v1.43.3` (moved from v1.43.2, operator 2026-10-16)
**Status:** LIVE-VERIFIED 2026-10-16 — hub Pushgateway after the v1.43.3 appsets-reapply: 38 per-spec `k3dm_dispatch_task_*` series per metric; `hub-dr-drill` (v1.43.0) reads 1.599 M Codex tokens and 5,070 s (84.5 min) of Codex time, matching the proof. The 7d token average is now 217 K, not 434 K, because v1.43.3 dispatches joined the window. Dashboard ConfigMap is Argo CD-tracked. Was: IMPLEMENTED — `eb45900e` (v1.43.3)
**Approval:** explicit 2026-10-12 "approved for per-spec dashboard" (operator)
**Priority:** P3 — the ledger holds every number; only the dashboard cannot show them
**Severity:** low — no metric is wrong; the view cannot answer "what did each spec cost"

## Symptom

Operator, 2026-10-11, on the k3dm Agent Dispatch dashboard (window `7d`): "for codex token
consumption per spec: can we make number readable, each spec consumption, and time to complete spec".

- "Codex tokens per accepted spec" shows `433825`: unit `none`, so no thousands scaling.
- It is a mean over five specs. One of them (`hub-dr-drill`, 7 Codex runs) used 1.60M tokens, the
  other four 43K–335K, so the mean describes no real spec, and nothing shows the split.
- Nothing shows how long a spec took. "Wait minutes per task" is only Codex exit → land.

## Root cause

The v1.42.x exporter spec (`docs/bugs/2026-10-09-codex-dispatch-has-no-throughput-or-cost-metrics.md`,
"Labels") ruled that slugs and versions never become labels, so `bin/k3dm-dispatch-metrics` can
only publish window means. The ledger (`K3DM_WORKTREE_ROOT/ledger.jsonl`) already has every
per-task fact: `start`/`resume` and `codex_exit` timestamps, `tokens` on each `codex_exit` (a
session total, so the latest one is the task's total), and the `land` timestamp.

This spec makes one bounded exception to that rule, the same way
`docs/bugs/2026-10-11-bug-dashboard-cannot-list-open-bugs.md` did for `k3dm_bug_open_info`:
validated label values and a hard cap. The original rule still holds for every other series.

## Definitions

For a task `(version, slug)` landed inside a window (its latest `land` event is in the window):

| Name | Definition |
|---|---|
| tokens | `tokens` of the task's latest `codex_exit` that has an int `tokens`; absent if none |
| Codex seconds | sum over the task's `codex_exit` events of `exit.ts − launch.ts`, where `launch` is the latest `start`/`resume` with `ts ≤ exit.ts` and after the previous `codex_exit` (a exit with no such launch adds nothing) |
| time to land (elapsed seconds) | latest `land.ts` − earliest `start.ts`; absent if the task has no `start` |
| runs | number of `codex_exit` events |

Time to land includes Codex runs, Claude's verification and any wait between them; Codex seconds is
Codex alone. Both are wall-clock.

## Files

| File | Change |
|---|---|
| `bin/k3dm-dispatch-metrics` | per-task series, two new means |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml` | panel 5 unit, panels 10–12 (and panel 2 from the landing-success doc) |
| `scripts/tests/bin/test_dispatch_metrics.py` | new tests |
| `scripts/tests/plugins/agent_dispatch_dashboard.bats` | new assertions (and the landing-success one) |
| `docs/guides/grafana-dashboards.md` | dashboard section |
| `docs/howto/codex-dispatch.md` | Metrics section |
| `CHANGELOG.md` | `[Unreleased]` entry |

## Fix

### 1. `bin/k3dm-dispatch-metrics`

- In `_window_metrics`, for each landed task also compute the four values above. Add to the
  returned dict:
  - `"elapsed"`: mean of time-to-land minutes over landed tasks that have one, else `None`;
  - `"codex_minutes"`: mean of Codex minutes over landed tasks with at least one run, else `None`;
  - `"tasks"`: a list of `(land_ts, version, slug, tokens, codex_seconds, elapsed_seconds, runs)`.
- In `render`, per window, after the existing lines:
  - `k3dm_dispatch_elapsed_minutes_per_landed{window}` and
    `k3dm_dispatch_codex_minutes_per_landed{window}` (each only when not `None`, like `wait`).
  - Per task, newest `land_ts` first, at most `TASK_CAP = 50` tasks:
    - `k3dm_dispatch_task_codex_tokens{window,version,slug}` (only when tokens is present)
    - `k3dm_dispatch_task_codex_seconds{window,version,slug}`
    - `k3dm_dispatch_task_elapsed_seconds{window,version,slug}` (only when present)
    - `k3dm_dispatch_task_runs{window,version,slug}`
  - Label values must match `^v?[0-9]+\.[0-9]+\.[0-9]+$` (version) and `^[A-Za-z0-9._-]{1,120}$`
    (slug); a task failing either is not emitted and is counted.
  - Always emit `k3dm_dispatch_task_skipped{window}` (count of invalid tasks) and
    `k3dm_dispatch_task_truncated{window}` (`1` when more than 50 valid tasks, else `0`).
  - The means above cover **all** landed tasks, not only the 50 emitted.
- The push stays one `PUT` to `job/k3dm-dispatch`, so a task that leaves the window disappears on
  the next export.

### 2. `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-dispatch.yaml`

- Panel 5 "Codex tokens per accepted spec": `"unit": "short"` (433825 → `434 K`). Description adds:
  "A mean; one long spec can dominate it — see Per spec."
- New panel 10, stat, "Minutes to land per spec", `gridPos {"h": 6, "w": 4, "x": 20, "y": 0}`,
  expr `k3dm_dispatch_elapsed_minutes_per_landed{window="$window"}`, unit `m`. Description: "Mean
  wall-clock time from a spec's first Codex start to its land, including Claude's verification."
- New panel 11, stat, "Codex minutes per spec", `gridPos {"h": 6, "w": 4, "x": 20, "y": 6}`,
  expr `k3dm_dispatch_codex_minutes_per_landed{window="$window"}`, unit `m`. Description: "Mean
  time Codex itself ran per spec, summed over its runs."
- New panel 12, table, "Per spec", `gridPos {"h": 10, "w": 19, "x": 5, "y": 12}`. Four instant
  targets, `"format": "table"`, refIds A–D, each wrapped in `sum by (version, slug) (...)` so the
  rows merge on `version`+`slug` only:
  - A `k3dm_dispatch_task_codex_tokens{window="$window"}`
  - B `k3dm_dispatch_task_codex_seconds{window="$window"}`
  - C `k3dm_dispatch_task_elapsed_seconds{window="$window"}`
  - D `k3dm_dispatch_task_runs{window="$window"}`
  - Transformations: `merge`, then `organize` with `excludeByName {"Time": true}` and
    `renameByName {"version": "Release", "slug": "Spec", "Value #A": "Codex tokens",
    "Value #B": "Codex time", "Value #C": "Time to land", "Value #D": "Codex runs"}`.
  - Overrides by name: Codex tokens unit `short`; Codex time and Time to land unit `s`.
  - `"options": {"sortBy": [{"displayName": "Codex tokens", "desc": true}]}`.
  - Description: "Each landed spec in the window, newest 50. Codex tokens are the session total of
    the spec's last run. Only specs dispatched with `bin/k3dm-codex-dispatch` appear; a bare `codex exec`
    writes no ledger event."
- Panel 9 "Export age" keeps `x 0, y 12`.

### 3. Docs

- `docs/guides/grafana-dashboards.md`, "k3dm Agent Dispatch": the two new stats, the Per spec table,
  the definitions of time to land and Codex time, and the 50-row cap.
- `docs/howto/codex-dispatch.md`, "Metrics": the per-task series, the label exception and why
  (bounded, validated), and that `make dispatch-metrics DRY_RUN=1` shows them.

## Tests

`scripts/tests/bin/test_dispatch_metrics.py`:

- Replace `test_render_has_no_slug` with `test_slug_only_in_task_series`: a started-not-landed task's
  slug appears nowhere; a landed task's slug appears only on `k3dm_dispatch_task_*` lines.
- `test_per_task_values`: fixture `start@0, codex_exit@100 tokens=10, resume@150, codex_exit@250
  tokens=30, land@400` → tokens `30`, Codex seconds `200`, elapsed `400`, runs `2`; window means
  elapsed `6.666…` minutes and Codex `3.333…` minutes.
- `test_exit_without_launch_adds_nothing`: an extra `codex_exit` right after another adds no seconds
  and counts as a run.
- `test_invalid_label_values_skipped`: slug `bad slug` and version `latest` are not emitted;
  `k3dm_dispatch_task_skipped{window="1d"} 2`.
- `test_task_cap`: 51 landed tasks → 50 `k3dm_dispatch_task_runs` lines per window, the oldest
  missing, `k3dm_dispatch_task_truncated{window="1d"} 1`; the means still count 51.
- None of these may reach the network (existing fixture pattern: `render` only, never `main`
  without `--dry-run`).

`scripts/tests/plugins/agent_dispatch_dashboard.bats`:

- Existing "every queried metric is exported" and "no overlap" tests cover the new panels.
- New: panel 5 unit is `short`; panel 12 has four targets each starting `sum by (version, slug)`.

Mutations (each must turn a test red): drop the `sum by` from target A; emit tokens from the first
`codex_exit` instead of the latest; drop the slug regex check; set `TASK_CAP` to 51.

## Proof it works

After merge and `make appsets-reapply`, then `make dispatch-metrics` on the M4: the 7d table lists
the five v1.43.0 specs with hub-dr-drill at 1.60 M tokens, about 84 min of Codex time and about
132 min to land, and the token stat reads `434 K`.

## Known limit (not fixed here)

v1.43.1's Codex work was launched with a bare `codex exec`, not the dispatcher, so it wrote no
ledger events and is absent from every panel. Routing those runs through the dispatcher is a
process change, not this fix.

## What NOT to Do

- Do NOT add slug or version labels to any series other than `k3dm_dispatch_task_*`.
- Do NOT sum `tokens` across a task's `codex_exit` events; each is already a session total.
- Do NOT change panel 2 here beyond what `dispatch-dashboard-landing-success-no-data` specifies; one
  agent does both docs in one dispatch because they edit the same file.
- Do NOT push to the hub Pushgateway from a test.
