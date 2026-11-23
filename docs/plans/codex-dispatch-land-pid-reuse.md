# Plan: `codex-dispatch land` ignores a reused PID (P3)

**Filed:** 2026-11-18
**Branch:** `k3d-manager-v1.45.0`
**Status:** PLANNED — ready for dispatch
**Covers:** `docs/bugs/2026-11-18-codex-dispatch-land-refuses-on-reused-pid.md`
**Risk:** low (one guard line in `land`, reusing the helper `resume` already uses; two tests)
**Reviewed:** Claude only (P3, one line; all PID liveness sites read)
**Agent:** Luna (Codex)

## Problem

`land` refuses with `Codex is still running` whenever the PID in `<slug>.run/pid` belongs to any live process
(`bin/k3dm-codex-dispatch:1357-1358`, bare `kill -0`). After a worker exits, macOS can hand its PID to an unrelated
process, and `land` is then refused although `<slug>.run/exit` exists. `resume` (`:1639`) already guards correctly with
`[[ ! -f "$run/exit" ]] && _dispatch_worker_matches_start "$run"` (`:166-175`), which compares the process start time
recorded in `<slug>.run/start`.

## Before You Start

1. Read the bug doc above.
2. Read `bin/k3dm-codex-dispatch` lines 140-176, 1340-1365 and 1630-1645, `scripts/tests/bin/codex_dispatch_helpers.bash`,
   `scripts/tests/bin/codex_dispatch_land.bats` and the two resume tests at the top of
   `scripts/tests/bin/codex_dispatch_resume.bats` (the pattern to copy).

## Fix

In `land` (`bin/k3dm-codex-dispatch:1357-1358`), replace the `pid` read and the bare `kill -0` check with the same guard
`resume` uses:

```bash
if [[ ! -f "$run/exit" ]] && _dispatch_worker_matches_start "$run"; then
  _dispatch_error "Codex is still running"
fi
```

Remove the now-unused `pid` assignment only if nothing later in `land` reads `$pid` (check; if something does, keep the
assignment). Do not change `_dispatch_worker_matches_start`, `resume`, `status`, prune (`:1818`), the network-slot scan
(`:904`) or the landing lock (`:1409`).

## Files

| File | Change |
|---|---|
| `bin/k3dm-codex-dispatch` | Fix |
| `scripts/tests/bin/codex_dispatch_land.bats` | tests 1-3 |

## Contract readers

`<slug>.run/pid` and `<slug>.run/start` — `grep -n 'run/pid\|run_dir/pid\|run/start' bin/k3dm-codex-dispatch`: writers
`_dispatch_write_start_marker` (`:146-153`, unchanged); readers `status` (`:1279`), network-slot scan (`:904`), land
(`:1357`, **changes**: now reads `start` and `exit` instead of `pid`), resume (`:1639`), prune (`:1818`) — all others
unchanged. `bin/k3dm-dispatch-stall-watch` reads `start` (unchanged). No file format changes.

## Tests (these names exactly, in `scripts/tests/bin/codex_dispatch_land.bats`)

Each test that starts a stand-in process runs `sleep 30 & sleeper=$!`, and kills it with `kill "$sleeper"` right after
the `run dispatch land ...` line and before any assertion, so a failing assertion never leaves it running.

1. `codex dispatch: land accepts a finished run whose PID was reused` — `dispatch start ... --slug one`, `sleep 1`,
   assert `one.run/exit` exists, commit `a.txt` in the task worktree (as in `land fast-forwards without pushing`); start
   the sleeper; write its PID to `one.run/pid` and set `pid=<sleeper>` and `process_start=not-the-worker` in
   `one.run/start`; first assert `kill -0 "$sleeper"` succeeds (the stand-in is live); `run dispatch land --slug one --no-test`;
   status 0 and output does not contain `Codex is still running`.
2. `codex dispatch: land accepts a dead worker whose PID identity is stale` — same as 1 but also `rm one.run/exit`;
   status 0.
3. `codex dispatch: land refuses while the worker is still running` (positive control) — `export STUB_SLEEP=5`,
   `dispatch start ... --slug one`, `sleep 1`; `run dispatch land --slug one --no-test`; status 2 and output contains
   `Codex is still running`; then `sleep 5` so the worker exits before the test ends.

Pre-fix red: 1 and 2 fail on today's code; 3 passes. Mutations (apply by hand, run, revert): put back the bare
`kill -0 "$pid"` check (1, 2 red); make the guard always false, e.g. `if false; then` (3 red).

## What NOT to Do

- Do not change any other PID check, the start-marker format, `_dispatch_worker_matches_start`, or error wording.
- Do not touch `docs/`, `CHANGELOG.md` or `memory-bank/`. Do not commit, push or open a PR; Claude verifies and commits.
- Do not skip hooks. Do not modify files outside the Files table. Do not run `land`, `start` or `abandon` against the
  real worktree root; tests use the helpers' scratch `K3DM_WORKTREE_ROOT` only.

## Rules

LF only; keep indentation, quoting and naming; no unsolicited refactors. If the spec contradicts the code, stop and say so.

## Gates

`bats scripts/tests/bin/codex_dispatch_land.bats scripts/tests/bin/codex_dispatch_resume.bats`, then
`shellcheck bin/k3dm-codex-dispatch`.

## Definition of Done

- [ ] Fix applied; `git status` shows only the two files.
- [ ] Pre-fix red for 1 and 2, green for 3, recorded.
- [ ] Gates green; mutation table recorded.
- [ ] Report: changed files, test output, mutation table. No commit.

## Acceptance

```yaml
interface:
  - "bin/k3dm-codex-dispatch land --slug S (refuses only while the recorded worker is alive)"
must:
  - id: M1
    text: land proceeds when the run has an exit marker, even if its recorded PID now belongs to another live process
  - id: M2
    text: land still refuses with "Codex is still running" while the recorded worker (same PID and start time) is alive
must_not:
  - id: N1
    text: land refuses a finished run, or a dead worker, because an unrelated process now holds its PID — red today
evidence:
  - id: E1
    proves: [M1, M2, N1]
    kind: offline
    command: bats scripts/tests/bin/codex_dispatch_land.bats -f "PID was reused|PID identity is stale|still running"
    intent: "Landing a finished dispatch no longer fails with 'Codex is still running' just because the Mac reused the agent's process number; a dispatch that is really still working is still refused."
```

**Intent approved:** operator, 2026-11-18
**Approval words and scope:** "please file that P3 and dispatch to Luna if there is a free slot" (after Claude reported the
`land` PID check at `:1358` and that `resume` already uses `_dispatch_worker_matches_start`). Scope: the one `land` guard.
