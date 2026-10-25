# Bug: dispatch worker model shows `unknown` though Codex reports it, and the coordinator cannot be declared

**Status:** FIXED 2026-10-25 — `71f70dd2`; pytest 121/121, BATS 78/78, shellcheck clean (land gate). Claude ran Luna's tests against a pre-fix copy: test 1 (bats 9), test 2 (pytest), test 4 (bats 11), plus the invalid-input (bats 10) and make-target (bats 78) cases all failed. Live E2 waits for the next dispatch with `COORDINATOR=`.
**Fix commit:** `71f70dd2`
**Review note:** reported models other than the latest are emitted with `role="worker_history"`, so the Per spec Worker column (role `worker`) still has one row per task.
**Priority:** P3
**Severity:** low — attribution only; the Worker and Coordinator columns carry no information yet
**Release:** v1.43.7 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-25, by Claude, from the live check of `docs/plans/v1.43.7-dispatch-vendor-coordinator-model-telemetry.md` (operator screenshots 299/300)
**Approval:** not required — non-critical spec (operator rule: dispatch approval only for critical specs); dispatcher ledger metadata and metrics exporter only.
**Component:** `bin/k3dm-codex-dispatch` (start/resume ledger identity), `bin/k3dm-dispatch-metrics` (`k3dm_dispatch_model_identity`)
**Related:** `docs/plans/v1.43.7-dispatch-vendor-coordinator-model-telemetry.md` (`0d5c58db`), scope items 3 and 6

## Problem

An offline dry run of `bin/k3dm-dispatch-metrics` on 2026-10-25 emits, for every v1.43.7 task:

- worker `vendor="openai",model="unknown",source="inherited",status="unknown"`, including tasks dispatched
  after `0d5c58db` landed;
- coordinator `vendor="unknown",model="unknown",source="unreported",status="unknown"`.

The plan's scope item 6 says to prefer the runtime-reported identity. Codex reports it: the header of each
run's `codex.log` has a `model: <id>` line (on 2026-10-25, `model: gpt-6-luna` in all 16 v1.43.7 run dirs).
The dispatcher never reads it. Without `MODEL=`, the start event records the model as `null`/inherited, so
the column is always `unknown`.

Scope item 3 says to record an explicitly declared coordinator identity, but nothing can declare one: the start
event hard-codes `coordinator_identity` to `unknown/unreported`.

`codex.log` is overwritten on each attempt (`>`), so the header has to be read at the end of each attempt,
not later.

## Fix

### F1. Record the runtime-reported worker model per attempt

In `bin/k3dm-codex-dispatch`, after each Codex attempt exits (initial run and resume), read the first
`^model: (\S+)$` line from the first 40 lines of `$run/codex.log`. If it matches `[A-Za-z0-9._:-]{1,64}`,
append a ledger event `identity` with `version`, `slug`, `run` (the attempt number) and
`worker_identity={vendor:<openai for codex, google for agy>, model:<id>, source:"runtime", status:"reported"}`.
If the line is missing or invalid, write nothing. Read only that line. Never copy any other part of
`codex.log` into the ledger, a metric or a log.

### F2. Allow a declared coordinator

Add an optional `--coordinator <vendor>/<model>` to `bin/k3dm-codex-dispatch start` and `resume`, and a
`COORDINATOR=` variable to `make codex-dispatch` and `make codex-resume` that passes it through. Each part must
match `[A-Za-z0-9._:-]{1,64}`, or the dispatcher exits with `invalid coordinator`. When given, the
start/resume event carries `coordinator_identity={vendor,model,source:"declared",status:"declared"}`. When
absent, today's `unknown/unreported` stays. Do not derive it from the environment, account settings or a
default.

### F3. Metrics prefer the reported identity

In `bin/k3dm-dispatch-metrics`, the worker identity for a task is its latest `identity` event when there is
one, otherwise today's start-event value. The coordinator is the latest declared value from start/resume,
otherwise today's value. When attempts report different worker models, the label is the latest and
`k3dm_dispatch_model_identity` also emits each distinct reported model once with `source="runtime"`.
(Scope item 2: keep every attempt's model, do not overwrite earlier ones.) The Per spec query
already takes `max by (..., worker)`, so check that a task still produces one Worker row there.

### F4. Docs

`docs/guides/grafana-dashboards.md`, Per spec: Worker is the model Codex reports in its log (`runtime`),
else what was selected (`selected`) or `unknown`. Coordinator is shown only when declared with `COORDINATOR=`.

## Tests

`scripts/tests/bin/test_dispatch_metrics.py` and `scripts/tests/bin/codex_dispatch.bats`, with a stub `codex` binary:

1. A stub whose log starts with `model: gpt-test-1` → an `identity` ledger event with model `gpt-test-1`,
   `source:"runtime"`, and the metrics emit `model="gpt-test-1",source="runtime",status="reported"` for that task.
2. A resume whose stub reports `gpt-test-2` → the ledger holds both events; the metrics label is `gpt-test-2`
   and `gpt-test-1` is still emitted.
3. A log without a `model:` line, or with `model: bad value!` → no `identity` event, and the label stays at
   today's value.
4. `COORDINATOR=anthropic/claude-test` → coordinator `vendor="anthropic",model="claude-test",source="declared"`.
5. `--coordinator 'bad/x y'` → exits non-zero with `invalid coordinator`, and writes no start event.
6. Ledger events from before this fix (no `identity` events, no coordinator) render exactly as today.
7. No line of the stub log other than the model id appears in the ledger or in the metrics output (seed
   the stub log with a marker string and assert it is absent).

Tests 1, 2 and 4 must be red on a temp copy of the pre-fix files.

## Files

- `bin/k3dm-codex-dispatch`
- `bin/k3dm-dispatch-metrics`
- `Makefile` (`codex-dispatch` / `codex-resume` pass `COORDINATOR`)
- `scripts/tests/bin/test_dispatch_metrics.py`
- `scripts/tests/bin/codex_dispatch.bats`
- `docs/guides/grafana-dashboards.md`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: After each Codex attempt, the model named on the codex.log "model:" header line is recorded for that attempt with source runtime, and k3dm_dispatch_model_identity shows it as the task's worker model.
  - id: M2
    text: COORDINATOR=<vendor>/<model> on dispatch or resume records a declared coordinator identity, and the metrics show it.
  - id: M3
    text: When attempts report different models, every reported model is kept, and the latest one is the task's worker.
  - id: M4
    text: The guide says where Worker and Coordinator come from.
must_not:
  - id: N1
    text: Nothing from codex.log other than the validated model id reaches the ledger, a metric label or a log line.
  - id: N2
    text: An invalid or missing model line or coordinator value never becomes a label value; an invalid coordinator stops the dispatch before any start event.
  - id: N3
    text: Old ledger events render exactly as before; no model selection, default or resume behaviour changes.
  - id: N4
    text: Tests never push to the real Pushgateway or run a real codex binary.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3, N4]
    text: K3DM_DISPATCH_PUSHGATEWAY_URL=http://127.0.0.1:9 pytest scripts/tests/bin/test_dispatch_metrics.py and bats scripts/tests/bin/codex_dispatch.bats green; tests 1, 2 and 4 red on a temp copy of the pre-fix files; shellcheck clean.
  - id: E2
    kind: live
    proves: [M1, M2]
    text: After the next Codex dispatch made with COORDINATOR= set and the next metrics push, the operator's screenshot of Agent Dispatch Per spec shows that task's Worker as the model in its codex.log header (source runtime) and its Coordinator as the declared value.
interface:
  - bin/k3dm-codex-dispatch start|resume (env K3DM_CODEX_BIN, K3DM_WORKTREE_ROOT; flag --coordinator)
  - make codex-dispatch / codex-resume COORDINATOR=
  - ledger.jsonl identity, start and resume events
  - bin/k3dm-dispatch-metrics --dry-run, series k3dm_dispatch_model_identity
```

## Definition of Done

- [ ] F1–F4 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] E1 green; paste the summaries.
- [ ] Tests 1, 2 and 4 shown red on a temp copy of the pre-fix files.
- [ ] Commit: `fix(dispatch): record the model Codex reports and a declared coordinator`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT read user model configuration (`~/.codex/config.toml`) or infer a model from a vendor or default.
- Do NOT copy `codex.log` content anywhere beyond the validated model id.
- Do NOT push to the real Pushgateway; tests use `http://127.0.0.1:9`.
- Do NOT change or remove existing tests or assertions.
- Do NOT modify files outside the Files list.
