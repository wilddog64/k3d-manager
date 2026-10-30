# Dispatch requires a release-branch checkout

## What was attempted

Started the approved P3 task `plans-dispatch-status-reconcile` for
`docs/bugs/2026-10-26-release-plans-dispatch-approval-unknown-despite-landed.md` from the M2
worktree `codex/v1439-retrieval-land`, which tracks `origin/k3d-manager-v1.43.9` but is not named as a
release branch.

Actual output:

```text
[codex-dispatch] ERROR: current branch 'codex/v1439-retrieval-land' is not a release branch
```

## Root cause

`bin/k3dm-codex-dispatch` derives the release version from the current branch name and refuses to
start unless checked out on `k3d-manager-vX.Y.Z`. Tracking a release branch remotely is not enough.
This is an intentional dispatcher guard, not a task or repository defect.

## Resolution

Created a clean local worktree on `k3d-manager-v1.43.9` at pushed revision `24c9837d`, then started
the same task. Actual dispatcher output:

```text
Preparing worktree (new branch 'task/v1.43.9/plans-dispatch-status-reconcile')
worktree: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/plans-dispatch-status-reconcile
run: /Users/cliang/.local/share/k3d-manager/worktrees/v1.43.9/plans-dispatch-status-reconcile.run
status: bin/k3dm-codex-dispatch status plans-dispatch-status-reconcile
```

A subsequent status check returned:

```text
task: plans-dispatch-status-reconcile
state: running
repo: k3d-manager
scope: in-scope
```
