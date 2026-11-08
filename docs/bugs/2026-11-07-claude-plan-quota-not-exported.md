# Bug: Claude plan usage (5-hour and 7-day limits) is not exported, so no dashboard shows it

**Status:** LANDED — `d033731a`, 2026-11-07. Exporter reads five_hour and seven_day from the status line cache only and emits k3dm_claude_quota_used_ratio, _resets_at_seconds and _sample_timestamp_seconds; Agent Activity gains Claude weekly, 5h and reading-age panels (ids 113-115). test_dispatch_metrics.py 197 passed and agent_dispatch_dashboard.bats 44/44 in the land run
**Fix commit:** `d033731a`
**Priority:** P3
**Waiting on:** live check — since 2026-11-07
Live check (operator): make platform-ops from k3d-manager-v1.43.15; on the machine the exporter runs on, with Claude Code running there, Agent Activity shows Claude weekly and 5h quota matching the status line and a reading age under a few minutes.
**Severity:** low — the operator can see Claude plan usage only in the Claude Code status line, so whether the $100 Max plan is the right size cannot be judged from the dashboards
**Approval:** operator, 2026-11-07 ("yes, file a P3 bug and dispatch to Flash 3.8")
**Assigned:** Flash 3.8 (`AGENT=agy MODEL=gemini-3.8-flash-medium`)
**Filed:** 2026-11-07
**Detected by:** the operator, comparing the status line (`5h 5%`, `7d 17%`) with the Agent Cost dashboard ("I have no clue from metrics")
**Affected:** `bin/k3dm-dispatch-metrics`, Agent Activity dashboard (`scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`)
**Branch:** `k3d-manager-v1.43.15`

## Observed failure

The operator moved Claude to the $100 Max plan on 2026-11-05 and asked whether usage justifies it. The status line
shows the plan's 5-hour and 7-day usage. No metric carries those numbers. The Agent Activity dashboard has
`Codex weekly quota used`, `Codex 5h quota used` and `Quota reading age` for Codex, and nothing for Claude.

## Root cause

`bin/k3dm-dispatch-metrics:1784-1801` exports the Codex plan limits it finds in Codex session files
(`k3dm_codex_quota_used_ratio{limit,window_minutes}`, `k3dm_codex_quota_resets_at_seconds`,
`k3dm_codex_quota_sample_timestamp_seconds`). Claude's limits are not in Claude's session files. The status line
(`~/.claude/statusline.sh`) fetches them from Anthropic's usage endpoint and caches the response at
`${STATUSLINE_CACHE_DIR:-/tmp/claude}/statusline-usage-cache.json`. It rewrites the file only after a successful fetch,
so the file's mtime is when the reading was taken. Nothing reads that cache besides the status line.

Captured from `/tmp/claude/statusline-usage-cache.json` on the M4, 2026-11-07 16:01 PST (abridged: of the 30-odd
top-level keys, the rest were `null` except `limits`, which is not used here):

```json
{
 "five_hour": {"utilization": 5.0, "resets_at": "2026-11-08T02:39:59.614566+00:00", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null, "locked_reason": null},
 "seven_day": {"utilization": 17.0, "resets_at": "2026-11-12T21:59:59.614590+00:00", "limit_dollars": null, "used_dollars": null, "remaining_dollars": null, "locked_reason": null},
 "seven_day_opus": null,
 "seven_day_sonnet": null,
 "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": 0.0, "utilization": null, "currency": "USD", "disabled_reason": "out_of_credits"}
}
```

`utilization` is a percentage (0–100).

## Fix

1. `bin/k3dm-dispatch-metrics`: add `--claude-usage-cache`, defaulting to
   `${STATUSLINE_CACHE_DIR:-/tmp/claude}/statusline-usage-cache.json`. Read only the `five_hour` and `seven_day`
   objects, and emit:
   - `k3dm_claude_quota_used_ratio{limit="five_hour",window_minutes="300"}` and
     `{limit="seven_day",window_minutes="10080"}`, each = `utilization / 100`;
   - `k3dm_claude_quota_resets_at_seconds{...same labels}` = `resets_at` as epoch seconds (ISO 8601 with offset);
   - `k3dm_claude_quota_sample_timestamp_seconds` = the cache file's mtime.
   A limit whose object is `null`, missing, or whose `utilization` is not a number (a bool counts as not a number) is
   skipped; an unparsable `resets_at` drops only that series. A missing, unreadable or invalid-JSON file emits no
   `k3dm_claude_quota_*` series and never fails the run. Copy no other field into a label or value.
2. Agent Activity dashboard: add `Claude weekly quota used`, `Claude 5h quota used` (stat, `percentunit`, same
   thresholds as the Codex pair) and `Claude quota reading age` (`time() - k3dm_claude_quota_sample_timestamp_seconds`,
   unit `s`), next to the Codex quota panels. Use panel ids not already used in the dashboard, and gridPos values
   that overlap no panel. The weekly panel's description says the reading comes from the Claude Code status line
   cache, and only updates while Claude Code runs on the machine the exporter runs on.
3. `docs/guides/grafana-dashboards/k3dm-agent-activity.md`: document the three panels, the source file, and that a
   large reading age means Claude Code has not run there recently, not that usage is zero.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml`
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `docs/guides/grafana-dashboards/k3dm-agent-activity.md`

## What NOT to do

- Do not call the Anthropic usage endpoint or read any OAuth token or Keychain item; read the cache file only.
- Do not edit `~/.claude/statusline.sh` or write to the cache directory.
- Do not change the Codex quota metrics or panels.
- Do not edit the Agent Cost dashboard (`grafana-dashboard-agent-cost.yaml`).
- Do not add a new Grafana matcher or transformation id that is not in Grafana 11.4.0's registry.
- Three other open dispatches edit `bin/k3dm-dispatch-metrics`
  (`2026-11-07-bugs-dashboard-fix-running-not-checked-against-worker`,
  `2026-11-07-agy-dispatch-runs-have-no-api-equivalent-cost`,
  `2026-11-07-dispatch-window-variable-sorts-versions-alphabetically`), and the last one also edits
  `agent_dispatch_dashboard.bats`. Keep your change in a new function called next to the Codex quota block, and add
  new tests rather than editing existing ones, so the four merge cleanly.
- Tests use a fixture file in a temporary directory passed with `--claude-usage-cache`; never read the real
  `/tmp/claude` cache.
- Do not run git add, commit or push, and do not touch `memory-bank/`.

## Acceptance

```yaml
must:
  M1: given the captured cache above, the exporter emits k3dm_claude_quota_used_ratio 0.05 for five_hour (window_minutes 300) and 0.17 for seven_day (window_minutes 10080)
  M2: it emits k3dm_claude_quota_resets_at_seconds for each limit as the epoch of resets_at, and k3dm_claude_quota_sample_timestamp_seconds as the cache file mtime
  M3: the Agent Activity dashboard has Claude weekly quota used, Claude 5h quota used and Claude quota reading age panels querying those metrics, with unique ids and no gridPos overlap
  M4: the guide documents the three panels, the source file and what a large reading age means
must_not:
  N1: a missing, unreadable or invalid-JSON cache never fails the exporter run and never emits a k3dm_claude_quota_ series (paired control for M1)
  N2: a null limit object or a non-numeric utilization (including true) never emits a used_ratio series for that limit, and the other limit is still emitted
  N3: no field other than utilization and resets_at reaches the output (for example extra_usage, limits, locked_reason)
  N4: the Codex quota series are byte-identical before and after for the same Codex fixture
evidence:
  E1:
    proves: [M1, M2, N1, N2, N3, N4]
    kind: offline
    intent: >-
      You will see test_dispatch_metrics.py write the captured cache to a temp file with a set mtime, run the exporter
      with --claude-usage-cache, and assert the exact series; then a missing file, invalid JSON, a null seven_day and a
      utilization of true. M1 and M2 are red on the pre-fix exporter.
    what: python3 -m pytest scripts/tests/bin/test_dispatch_metrics.py
  E2:
    proves: [M3]
    kind: offline
    intent: >-
      You will see agent_dispatch_dashboard.bats assert the three panel titles, their exprs, unique panel ids and no
      gridPos overlap on the Agent Activity dashboard; red on the pre-fix dashboard.
    what: bats scripts/tests/plugins/agent_dispatch_dashboard.bats
  E3:
    proves: [M1, M3]
    kind: live
    intent: >-
      After make platform-ops, the operator sees the Claude 5h and weekly panels on Agent Activity match the status
      line within one refresh, and a reading age under a few minutes while Claude Code is running.
    what: Agent Activity dashboard on grafana.3ai-talk.org, beside the Claude Code status line
interface:
  - bin/k3dm-dispatch-metrics --claude-usage-cache PATH (Prometheus text output)
  - scripts/etc/argocd/platform-ops/grafana-dashboard-agent-activity.yaml
```
