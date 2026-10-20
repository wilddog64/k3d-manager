# Issue: dispatched documentation worker exited without output

**Date:** 2026-10-19
**Status:** OPEN

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

## Root cause

Unknown. The dispatcher successfully created the worktree but the worker exited before writing its normal completion markers.

## Recommended follow-up

Investigate why a dispatched worker can terminate before `_dispatch_codex_exit` records the exit state, then make the status command report a terminal failure instead of `state: unknown`.
