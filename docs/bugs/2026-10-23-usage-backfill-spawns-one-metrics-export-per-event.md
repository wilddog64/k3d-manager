# Bug: usage-backfill starts one metrics export per event and starves the hub

**Status:** LIVE-VERIFIED 2026-10-23 — FIXED `5a96ef60`; E1 green (52 bats, shellcheck clean). E2 live 2026-10-23 17:44 PDT: 20 rapid `_dispatch_schedule_metrics` calls ran at most one real export at a time (one sampler reading of 2 was a transient process gone before `ps`), load stayed below 10, no lock left behind; `usage-backfill` with nothing to do started no export.
**Priority:** P1
**Fix commit:** `5a96ef60`
**Live evidence:** 2026-10-23 · run claude-usage-backfill-20-rapid-schedules · env laptop · scenario usage-backfill-after-dispatch · commit ef4b1156 · proves E2
**Severity:** high — one `usage-backfill` run put the laptop at load 101 and made every Grafana panel error
**Release:** v1.43.5 (bug; does not count toward the five-plan cap)
**Filed:** 2026-10-23, by Claude after the operator reported every Bug Tracking panel in error
**Approval:** explicit 2026-10-23. The operator said: "can you dispatch P1 bug".

**Component:** `bin/k3dm-codex-dispatch` (`_dispatch_schedule_metrics`, `_dispatch_codex_usage`,
`_dispatch_usage_backfill`)

## Problem

`_dispatch_schedule_metrics` starts `bin/k3dm-dispatch-metrics` in the background, with no limit on
how many run at once. `_dispatch_codex_usage` (added by `v1.43.5-dispatch-api-cost`, `8299e85d`)
calls it after every `codex_usage` event. `usage-backfill` calls `_dispatch_codex_usage` once per log.

Since `8299e85d`, each export also scans every Codex session file modified in the last 30 days
(about 600 files, some several MB). On 2026-10-23 at 16:53 PDT, Claude ran `usage-backfill` once.
It appended 127 events, so 127 exports ran at the same time:

- Load average rose to 101. OrbStack, which runs the k3d nodes, used about 285% CPU.
- Health probes timed out on Grafana, the ESO webhook, metrics-server, Istio ingress and
  kube-state-metrics (5 restarts). The metrics API became unavailable.
- Every Bug Tracking panel and the Release variable showed a datasource error.

The cluster recovered by itself about 5 minutes later, once the exports had finished.

Ordinary dispatches have the same flaw at a smaller scale. Two events close together (a `codex_exit`
followed by a `codex_usage`) start two full exports at once.

## Fix

### F1. Single-flight export

`_dispatch_schedule_metrics` runs at most one export at a time, and the last request is never lost:

- Take a lock with `mkdir "$_dispatch_worktree_root/metrics.lock"`. `mkdir` is atomic, and
  `flock` is not on macOS.
- If the lock is held, `touch "$_dispatch_worktree_root/metrics.pending"` and return.
- The lock holder runs the export in the background, in a loop:
  1. Remove `metrics.pending`.
  2. Run `k3dm-dispatch-metrics`.
  3. Run again if `metrics.pending` reappeared during the run.
  4. Otherwise, release the lock.
- A lock older than 10 minutes counts as stale, for example after a crash. Remove it and take it.

### F2. Backfill exports once

`_dispatch_codex_usage` gains a way to skip scheduling, for example `_DISPATCH_SKIP_METRICS=1`.
`usage-backfill` sets it for every log, then schedules one export after the counts are printed,
and only if `backfilled` is more than 0.

## Tests

`scripts/tests/bin/codex_dispatch.bats`. Stub `k3dm-dispatch-metrics` with a script that logs a line
per start, sleeps 1 second, and records the most processes running at once.

1. Twenty `_dispatch_schedule_metrics` calls in a tight loop: at most one stub runs at once. At least
   one run starts after the last call (the last request is not lost).
2. `usage-backfill` over 5 logs that each have a session file starts the stub exactly once.
3. `usage-backfill` with nothing to backfill starts the stub zero times.
4. A `metrics.lock` older than 10 minutes is taken over; a fresh one is not.

Show tests 1 and 2 red against the pre-fix script on a temp copy.

## Files

- `bin/k3dm-codex-dispatch`
- `scripts/tests/bin/codex_dispatch.bats`
- `CHANGELOG.md`

## Acceptance

```yaml
must:
  - id: M1
    text: At most one k3dm-dispatch-metrics export runs at a time from bin/k3dm-codex-dispatch, however many events are written.
  - id: M2
    text: A request made while an export runs causes exactly one more export after it; the last event is always reflected.
  - id: M3
    text: usage-backfill starts one export when it backfilled at least one event, and none otherwise.
  - id: M4
    text: A lock older than 10 minutes is treated as stale and taken over.
must_not:
  - id: N1
    text: N events written in quick succession must never start N concurrent exports.
  - id: N2
    text: A failed or killed export must not leave the lock held forever.
  - id: N3
    text: The ledger format and the k3dm-dispatch-metrics output must not change.
evidence:
  - id: E1
    kind: offline
    proves: [M1, M2, M3, M4, N1, N2, N3]
    text: bats scripts/tests/bin/codex_dispatch.bats green; tests 1 and 2 red on the pre-fix script.
  - id: E2
    kind: live
    proves: [M1, N1]
    text: Claude runs usage-backfill after a fresh dispatch; the highest count of k3dm-dispatch-metrics processes stays at 1, and the 1-minute load stays below 15.
interface:
  - bin/k3dm-codex-dispatch (usage-backfill, any command that writes a ledger event)
  - $K3DM_WORKTREE_ROOT/metrics.lock, metrics.pending
  - K3DM exporter path (stubbable as $_dispatch_script_dir/k3dm-dispatch-metrics)
```

## Definition of Done

- [ ] F1–F2 and a CHANGELOG `[Unreleased]` `### Fixed` entry; only the Files above change.
- [ ] `bats scripts/tests/bin/codex_dispatch.bats` green; paste the summary. `shellcheck -S warning bin/k3dm-codex-dispatch` clean.
- [ ] Tests 1 and 2 shown red on a temp copy of the pre-fix script.
- [ ] Commit: `fix(dispatch): run one metrics export at a time`

## What NOT to Do

- Do NOT create a PR, commit to `main`, or skip hooks (`--no-verify`).
- Do NOT run `usage-backfill` against the real worktree root, or push to the live Pushgateway, from tests.
- Do NOT read the real `~/.codex` from tests.
- Do NOT change `bin/k3dm-dispatch-metrics` or the ledger format.
- Do NOT remove any line beginning with `assert_` or any `@test` from a BATS file.
- Do NOT modify files outside the Files list.
