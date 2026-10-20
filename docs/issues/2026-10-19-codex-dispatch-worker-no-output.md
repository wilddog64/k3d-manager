# Issue: dispatched documentation worker exited without output

**Date:** 2026-10-19
**Status:** PARTIALLY FIXED — status reporting improved; worker-start failure remains unresolved

## What was attempted

The canonical e2e sandbox bug status update was dispatched with:

```text
bin/k3dm-codex-dispatch start --spec docs/bugs/2026-10-19-e2e-sandbox-provision-frontend-upstream-race.md --slug e2e-sandbox-live-verify
```

The dispatcher created the task worktree and run directory, but the worker produced no output and no exit marker.

## Actual output

```text
Preparing worktree (new branch 'task/v1.43.5/e2e-sandbox-live-verify')
worktree: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/e2e-sandbox-live-verify
run: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/e2e-sandbox-live-verify.run
status: bin/k3dm-codex-dispatch status e2e-sandbox-live-verify
```

```text
task: e2e-sandbox-live-verify
state: unknown
scope: in-scope
```

The run directory contained an empty `codex.log`; no `exit` or `last-message.md` file was produced, and the recorded worker PID was no longer running.

## Recurrence — 2026-10-20

The PR Checks table task was dispatched with:

```text
bin/k3dm-codex-dispatch start --spec docs/bugs/2026-10-19-pr-checks-grafana-tables-misaligned-populated-state.md --slug pr-checks-table-misalignment --network
```

The task again created its worktree and PID, then lost the worker before it wrote any Codex output or exit marker:

```text
task: pr-checks-table-misalignment
state: unknown
network: yes
scope: in-scope
pid=58276
alive=no
exit=not-recorded
codex.log size=0 bytes
```

After the dispatcher status fix, the same record reports:

```text
task: pr-checks-table-misalignment
state: failed (worker exited without exit marker)
network: yes
scope: in-scope
```

The detached-worker retry was then implemented and tested, but a live retry still failed in this launcher environment:

```text
task: pr-checks-table-misalignment-retry3
pid=17223
alive=no
codex.log: not created
exit=not-recorded
state: failed (worker exited without exit marker)
```

The dispatcher fix commits are `6e8ef83e` (terminal failure reporting) and `04d91a6e` (detached worker launch). The retry cannot yet be considered active or complete.

## Root cause

The worker termination mechanism is still unknown. The dispatcher successfully created the worktree and PID, but the worker exited before writing to `codex.log`, `last-message.md`, or `exit`. The dispatcher previously misclassified this terminal condition as `unknown`.

The dispatcher now treats a dead recorded PID without an `exit` marker as `failed (worker exited without exit marker)`, so operators can distinguish a dead worker from an active one.

## Recommended follow-up

Investigate why a dispatched worker can terminate before `_dispatch_codex_exit` records the exit state. Preserve the new terminal failure status and add startup diagnostics or a supervised worker mechanism once the termination cause is isolated.

## Verification

```text
bats scripts/tests/bin/codex_dispatch.bats
1..34
ok 1 ...
...
ok 34 ...

shellcheck bin/k3dm-codex-dispatch
clean
```

The focused BATS suite passed 34/34, including the regression test for a dead worker without an exit marker.
