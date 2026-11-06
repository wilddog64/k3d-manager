# Bug: dispatch resume ignores the task's model and records a worker model that did not run

**Status:** OPEN — dispatched to Luna 2026-11-06
**Priority:** P2
**Severity:** medium — every Codex resume runs Codex's configured default model rather than the model the task was dispatched with, and the ledger's `resume` event claims the dispatched model. Per-model cost and quality comparisons, and the planned lead-model dashboard, are wrong for any task that was resumed.
**Filed:** 2026-11-05
**Detected by:** Claude, while reviewing the 2-day keychain-stall dispatch (`v1.43.14/2026-11-02-acg-up-stalls-at-system-keychain-trust`)
**Branch:** `k3d-manager-v1.43.14`
**Approval:** pending
**Related:** `docs/bugs/2026-10-29-non-claude-coordinator-work-unattributed.md`, `docs/plans/v1.43.7-dispatch-vendor-coordinator-model-telemetry.md`

## Evidence

Ledger counts for slug `2026-11-02-acg-up-stalls-at-system-keychain-trust` (read 2026-11-05):

| event | worker model | source | count |
|---|---|---|---|
| start | gpt-6-luna | explicit | 1 |
| resume | gpt-6-luna | inherited | 23 |
| identity | gpt-6-luna | runtime | 1 |
| identity | gpt-6.1-terra | runtime | 23 |
| codex_usage | gpt-6.1-terra | — | 23 |

Code (`bin/k3dm-codex-dispatch` at `69f6a09f`):
- `_dispatch_resume` reads `model="$(cat "$run/model")"` and writes it into the `resume` event as `worker_identity.model` with `source: inherited`, around line 1036.
- The detached worker then runs `codex exec resume -c ... -o ... "$session_id" -` (lines 1238 and 1240) with **no `-m "$model"`**. Codex therefore falls back to its configured default model.

`bin/k3dm-dispatch-metrics` prefers the latest runtime identity for the task-level Worker column (around line 831), so the dashboard shows only the last model. A Luna-started, Terra-resumed task is reported as entirely one model or the other.

## Fix

1. When `$run/model` is non-empty, pass `-m "$model"` to both `codex exec resume` invocations. Add `resume --model ID` to override it. An override updates `$run/model` and records `source: explicit`.
2. The `resume` event records `source: inherited` only when a model is actually passed to Codex. When none is passed, record `model: unknown, source: unreported`.
3. Metrics attribute tokens and runs per run, from that run's `identity` and `codex_usage` events. A task's Worker cell lists every distinct runtime model in run order, for example `gpt-6-luna → gpt-6.1-terra`.

## Files

- `bin/k3dm-codex-dispatch`
- `bin/k3dm-dispatch-metrics`
- `scripts/tests/bin/codex_dispatch.bats`
- `scripts/tests/bin/test_dispatch_metrics.py`

## Acceptance

To be written before dispatch. It needs a captured `codex exec resume --help` for the `-m` contract, with host and date.
