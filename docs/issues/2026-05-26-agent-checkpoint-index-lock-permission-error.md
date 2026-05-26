# 2026-05-26 — `_agent_checkpoint` cannot create `.git/index.lock`

**Repository:** `k3d-manager`
**Context:** services-git ApplicationSet project fix validation

## What was tested

Ran:

```bash
./scripts/k3d-manager _agent_checkpoint
```

Then checked for a stale lock file:

```bash
ls -l .git/index.lock
```

## Actual output

```text
running under bash version 5.3.9(1)-release
fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted
ERROR: Failed to stage files for checkpoint
```

```text
ls: cannot access '.git/index.lock': No such file or directory
```

## Root cause

Likely a sandbox or filesystem permission restriction on creating the Git index lock file during `_agent_checkpoint`. The lock file was not left behind afterward.

## Follow-up

- Continue using the normal `git add` / `git commit` path for this task.
- Revisit `_agent_checkpoint` environment assumptions if this happens again on the same machine.
