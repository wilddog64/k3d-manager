# Dispatch dashboard: two landed tasks lack Codex terminal metrics

## Observation

The operator screenshot shows `slack-explicit-job-logs` and `slack-make-log-selection` in the
per-spec table with elapsed time (`1.60 mins` and `4.98 mins`) but blank Codex tokens, `0 s` Codex
time, and `0` Codex runs.

The raw ledger entries are:

```text
{"ts":1792454964,"event":"start","version":"v1.43.5","slug":"slack-make-log-selection","network":0}
{"ts":1792455263,"event":"land","version":"v1.43.5","slug":"slack-make-log-selection","verifier_lines":0,"wait_seconds":null}
{"ts":1792455636,"event":"start","version":"v1.43.5","slug":"slack-explicit-job-logs","network":0}
{"ts":1792455732,"event":"land","version":"v1.43.5","slug":"slack-explicit-job-logs","verifier_lines":0,"wait_seconds":null}
```

The retained run directories have a `landed` marker and an empty `codex.log`, but no `start`,
`exit`, or `codex-exit-ts` markers. There is no `codex_exit` ledger event for either slug.

## Interpretation

The exporter derives elapsed time from `start` to `land`, so those values are valid: 299 seconds
(4.98 minutes) and 96 seconds (1.60 minutes), respectively. It derives Codex runs and duration
from `codex_exit` events; with no such event, it reports zero runs and zero seconds, and omits
the token series, which Grafana displays blank. These zeros/blanks mean “terminal usage data was
not recorded,” not “Codex did no work.”

Both tasks predate `2de716d8` (`fix: detach Codex dispatch workers and record terminal status`),
which added durable terminal markers and Codex exit ledger events. New runs should record those
metrics; the existing records were not backfilled. No dashboard or ledger mutation was performed.

## Follow-up

Consider rendering missing Codex metrics as unavailable rather than zero, to distinguish legacy
incomplete telemetry from a measured zero. Any historical backfill would need independent
evidence; the current run directories do not retain Codex output or exit/token counts.
The implementation task is tracked in
`docs/bugs/2026-10-21-dispatch-dashboard-missing-codex-telemetry-renders-zero.md`.
