# Slack bug dispatch workers terminated before reporting completion

**Date:** 2026-10-20
**Tasks:** `slack-smoke-health-diagnostics`, `slack-thread-e2e-replay-ack`
**Specs:** `docs/bugs/2026-10-13-slack-smoke-cluster-health-failure-hides-diagnostics.md`, `docs/bugs/2026-10-14-slack-thread-e2e-replay-no-ack.md`
**Result:** Both workers started, then dispatcher status reported `terminated unexpectedly`; neither wrote an `exit` marker or a final message. No task tests or landing gates ran.

## What was done

- Added explicit `## Files` and verification-gate sections to both existing P2 bug specs and pushed them in commit `3e7a2358`.
- Started two non-networked dispatch tasks from the clean pushed branch. The dispatcher created isolated worktrees under `~/.local/share/k3d-manager/worktrees/v1.43.5/` and run directories alongside them.
- Initial status showed both tasks in `terminated unexpectedly` with their scopes still reported as in-scope.

## Actual output

```text
task: slack-smoke-health-diagnostics
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/slack-smoke-health-diagnostics.run/supervisor.log)
scope: in-scope
task: slack-thread-e2e-replay-ack
state: terminated unexpectedly (see /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/slack-thread-e2e-replay-ack.run/supervisor.log)
scope: in-scope
```

Read-only checks showed:

```text
pid 22575 not alive
pid 24323 not alive
```

Both run directories have a `start` marker but no `exit` or `last-message.md`; both `supervisor.log` files are empty. The smoke task worktree has unverified modifications to `scripts/plugins/smoke.sh` and `scripts/tests/plugins/smoke.bats`. The replay task worktree has no tracked modifications. The Codex logs and both worktrees were preserved. No tests were run and no live Slack replay was triggered.

## Root cause and follow-up

Root cause is unknown. The workers died before producing their terminal markers or a diagnostic in `supervisor.log`, so the dispatcher output is insufficient to determine why. Preserve the current run directories and partial smoke work. Before claiming either dispatch is active or landing work, inspect/recover the dispatcher lifecycle or explicitly resume/re-dispatch the tasks with a documented path that preserves the unverified worktree changes.
