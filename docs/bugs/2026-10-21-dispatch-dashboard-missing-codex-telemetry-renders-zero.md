# Bug: Dispatch dashboard renders missing Codex telemetry as zero

**Status:** LIVE-VERIFIED — Grafana shows missing Codex exit metrics as unavailable, not zero
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

## Offline verification

- Landed on `k3d-manager-v1.43.5` as `63d604dd` (`fix(dispatch): omit missing codex usage samples`).
- `python3 -m pytest -p no:cacheprovider scripts/tests/bin/test_dispatch_metrics.py`: **12 passed**.
- `bats scripts/tests/plugins/agent_dispatch_dashboard.bats`: **7/7 passed**.
- The dispatcher's land gate reran both commands successfully. Commit hook `_agent_audit` passed; the intentional replacement of the old zero-run expectation is documented with an allow marker.
- At offline verification time, no live Grafana/Pushgateway check had been performed.

## Live verification

**Fix commit:** 63d604dd
**Live evidence:** 2026-10-20 · run grafana-screenshot-2026-10-20 · env hub-grafana · scenario historical-dispatch-rows-show-elapsed-and-blank-missing-codex-metrics · commit 63d604dd · proves fix

- 2026-10-20: operator screenshot after exporter rollout shows `slack-explicit-job-logs` with
  `Time to land` = **1.60 mins** and `slack-make-log-selection` = **4.98 mins**. `Codex tokens`,
  `Codex time`, and `Codex runs` are blank for both historical rows, confirming missing terminal
  telemetry is represented as unavailable rather than zero. The task rows and elapsed values remain.
- Evidence: operator-provided Grafana screenshot in the conversation (Checks table, columns Spec,
  Release, Codex tokens, Codex time, Time to land, Codex runs).
