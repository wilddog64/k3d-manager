# Dispatcher status transiently reported Slack bug tasks as terminated

**Date:** 2026-10-20
**Tasks:** `slack-smoke-health-diagnostics`, `slack-thread-e2e-replay-ack`
**Specs:** `docs/bugs/2026-10-13-slack-smoke-cluster-health-failure-hides-diagnostics.md`, `docs/bugs/2026-10-14-slack-thread-e2e-replay-no-ack.md`
**Result:** An early status check reported both tasks as `terminated unexpectedly`, with no terminal markers visible at that instant. Later checks showed the workers had completed successfully and written their exit/final-message markers. Both scoped test suites passed; no landing was performed and no live Slack replay was triggered.

## What was done

- Added explicit `## Files` and verification-gate sections to both existing P2 bug specs and pushed them in commit `3e7a2358`.
- Started two non-networked dispatch tasks from the clean pushed branch. The dispatcher created isolated worktrees under `~/.local/share/k3d-manager/worktrees/v1.43.5/` and run directories alongside them.
- Initial status showed both tasks in `terminated unexpectedly` with their scopes still reported as in-scope. The task logs continued to grow afterward, then both terminal markers appeared.

## Actual output

```text
task: slack-smoke-health-diagnostics
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/slack-smoke-health-diagnostics.run/supervisor.log)
scope: in-scope
task: slack-thread-e2e-replay-ack
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/slack-thread-e2e-replay-ack.run/supervisor.log)
scope: in-scope
```

At the initial check, read-only PID checks showed:

```text
pid 22575 not alive
pid 24323 not alive
```

The initial check preceded terminal markers. Subsequent status and final messages confirmed:

- `slack-smoke-health-diagnostics`: exited successfully; `bats scripts/tests/plugins/smoke.bats` passed 10/10, ShellCheck produced no output, and `git diff --check` passed. Changes are limited to `scripts/plugins/smoke.sh` and `scripts/tests/plugins/smoke.bats`.
- `slack-thread-e2e-replay-ack`: exited successfully; the focused pytest command passed 34/34 and `git diff --check` passed. Changes are limited to `bin/k3dm-webhook` and the two scoped thread-dispatch/broadcast test files. No live replay or report publication was run.

Both worktrees and run logs were preserved for review. Separately, the operator requested cleanup of three older stale tasks; their clean local worktrees and local task branches were removed, while their run directories/logs were retained.

## Root cause and follow-up

Root cause for the transient `terminated unexpectedly` status is unknown. Because both tasks subsequently produced successful exit markers and final messages, no worker recovery or re-dispatch was needed. Review the task diffs and run the required land gates before integrating; operator live verification remains separate.
