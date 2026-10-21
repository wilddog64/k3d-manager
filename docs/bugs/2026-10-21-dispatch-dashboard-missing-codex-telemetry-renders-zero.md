# Bug: Dispatch dashboard renders missing Codex telemetry as zero

**Status:** OPEN — landed tasks without a recorded Codex exit are displayed with zero runs/time
**Priority:** P3
**Filed:** 2026-10-21
**Detected by:** operator review of the k3dm Agent Dispatch dashboard
**Branch:** `k3d-manager-v1.43.5`
**Component:** dispatch ledger exporter / per-spec Grafana table
**Related:** `docs/issues/2026-10-21-dispatch-dashboard-legacy-task-metrics-missing.md`

## Observed behavior

The per-spec dashboard rows for `slack-explicit-job-logs` and `slack-make-log-selection` show
valid elapsed-to-land times (1.60 and 4.98 minutes), but blank Codex tokens, `0 s` Codex time,
and `0` Codex runs. Their ledger histories contain `start` and `land` events but no `codex_exit`:

```text
{"ts":1792454964,"event":"start","version":"v1.43.5","slug":"slack-make-log-selection","network":0}
{"ts":1792455263,"event":"land","version":"v1.43.5","slug":"slack-make-log-selection","verifier_lines":0,"wait_seconds":null}
{"ts":1792455636,"event":"start","version":"v1.43.5","slug":"slack-explicit-job-logs","network":0}
{"ts":1792455732,"event":"land","version":"v1.43.5","slug":"slack-explicit-job-logs","verifier_lines":0,"wait_seconds":null}
```

The elapsed calculations are correct (299 seconds and 96 seconds). Missing Codex terminal
telemetry is currently converted to zero for Codex time and run count, which falsely looks like
measured zero work. Tokens are already omitted when unavailable.

## Expected behavior

- For a landed task with no `codex_exit` events, keep the task row and valid elapsed-to-land
  metric, but do not emit per-task Codex duration or run-count samples. Grafana should render
  those fields as unavailable/blank, not zero.
- Keep the current semantics for tasks with one or more `codex_exit` events, including a genuine
  zero-second duration if supported by the recorded timestamps.
- Do not fabricate or backfill historical Codex run, duration, or token values.
- Ensure aggregate Codex-time-per-landed calculations continue to exclude tasks without an exit.
- Add exporter regression tests for missing exit events and a control case with recorded exits.

## Files

- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/test_dispatch_metrics.py`

## Verification gates

- `pytest -q scripts/tests/bin/test_dispatch_metrics.py`
- `bats scripts/tests/plugins/agent_dispatch_dashboard.bats`
- `_agent_audit`

## Scope limits

Do not edit the dashboard layout or query, mutate Pushgateway/Grafana, or modify ledger history.
Only correct exporter semantics and add regression tests.
