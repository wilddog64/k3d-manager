# Dispatcher land retry — worker worktree was uncommitted

During the 2026-10-27 landing of `plans-dispatch-status-reconcile`, the first `land` attempt from the task worktree was rejected. Exact output:

```text
[codex-dispatch] ERROR: current branch 'task/v1.43.9/plans-dispatch-status-reconcile' is not a release branch
```

Retrying from the correct clean release-branch checkout then reported:

```text
[codex-dispatch] ERROR: worktree has uncommitted changes
```

Inspection showed the task worktree had five staged implementation files but no task commit yet. `_agent_checkpoint` created the task commit, after which the dispatcher successfully rebased, ran the scoped tests, and landed it. The release checkout was clean throughout. This was a workflow sequencing issue; no code change was needed to the dispatcher.

Successful retry output:

```text
scope: in-scope
target moved: +1 commits since dispatch (24c9837ddfc3f7dcb539b00f82317235c69ec151..f792376fa739eb8f2e7d3c21a54da2390a175674)
Rebasing (1/1)
Successfully rebased and updated refs/heads/task/v1.43.9/plans-dispatch-status-reconcile.
tests: passed
landed: plans-dispatch-status-reconcile
push: git -C /private/tmp/k3dm-v1439-dispatch push origin k3d-manager-v1.43.9
```

The printed push line was a suggested command, so the coordinator explicitly pushed the target branch and confirmed `78ffa7d5` on `origin/k3d-manager-v1.43.9`.

Follow-up: commit/checkpoint the completed worker diff before invoking `land`; invoke `land` from a clean worktree on the named release branch.
