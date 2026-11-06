# Bug: dispatch resume ignores the task's model and records a worker model that did not run

**Status:** OPEN — redispatched to Luna 2026-11-06 under slug `2026-11-06-dispatch-resume-keeps-task-model`. The first dispatch stopped without edits, because the Acceptance section was still a placeholder.
**Priority:** P2
**Severity:** medium — every Codex resume runs Codex's configured default model rather than the model the task was dispatched with, and the ledger's `resume` event claims the dispatched model. Per-model cost and quality comparisons, and the planned lead-model dashboard, are wrong for any task that was resumed.
**Filed:** 2026-11-05
**Detected by:** Claude, while reviewing the 2-day keychain-stall dispatch (`v1.43.14/2026-11-02-acg-up-stalls-at-system-keychain-trust`)
**Branch:** `k3d-manager-v1.43.14`
**Approval:** operator, 2026-11-06: "go with your suggestion". Not a hub spec.
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

Contract captured on `m4-air`, 2026-11-06 17:55Z, `codex-cli 0.166.0`, `codex exec resume --help`: `Usage: codex exec resume [OPTIONS] [SESSION_ID] [PROMPT]`, with `-m, --model <MODEL>` among the options. A stub `codex` must accept that shape.

```yaml
must:
  - id: M1
    text: "Resuming a Codex task whose run has a stored model starts `codex exec resume` with `-m <that model>`, on both resume paths (with and without network access)."
  - id: M2
    text: "`resume --model ID` passes `-m ID` to Codex, replaces the stored model so a later resume without --model uses ID, and writes a resume event with worker_identity.model ID and source explicit."
  - id: M3
    text: "A resume without --model that passes a stored model writes a resume event with worker_identity.model equal to it and source inherited."
  - id: M4
    text: "A resume with no stored model passes no -m and writes a resume event with worker_identity model unknown and source unreported."
  - id: M5
    text: "For a task whose runs reported different runtime models, the metrics Worker value lists each distinct model in run order, such as `gpt-6-luna → gpt-6.1-terra`, and tokens are attributed to the model of the run that used them."
must_not:
  - id: N1
    text: "A resume event never records source inherited when no model was passed to Codex (paired positive control: M3)."
  - id: N2
    text: "A task that only ever reported one runtime model shows that one model, with no arrow and no repeat."
  - id: N3
    text: "An agy resume is unchanged: it still requires and uses its stored conversation, and is not given Codex's -m handling."
evidence:
  - {id: E1, proves: [M1, M2, M3, M4, N1, N3], kind: offline, text: "Black-box tests of bin/k3dm-codex-dispatch resume with K3DM_CODEX_BIN pointing at a stub recording its argv, and K3DM_WORKTREE_ROOT at a scratch directory, asserted first. M1, M2, M3, M4 and N1 red on the pre-fix commit."}
  - {id: E2, proves: [M5, N2], kind: offline, text: "bin/k3dm-dispatch-metrics run against a scratch ledger with a two-model task and a one-model task. M5 red on the pre-fix commit; N2 red by a mutant."}
  - {id: E3, proves: [M1, M3], kind: live, text: "Claude resumes one real low-stakes dispatch and reads the runtime identity event: it reports the stored model."}
interface:
  - "bin/k3dm-codex-dispatch resume --slug SLUG --prompt-file PATH --reason REASON [--model ID]"
  - "bin/k3dm-dispatch-metrics, with its ledger path and Worker output"
```
