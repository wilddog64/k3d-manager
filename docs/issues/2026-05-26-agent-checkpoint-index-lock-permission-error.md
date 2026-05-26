# 2026-05-26 — `_agent_checkpoint` cannot create `.git/index.lock`

**Repository:** `k3d-manager`
**Context:** `bin/acg-down` /tmp cleanup change

## What was tested

Ran:

```bash
./scripts/k3d-manager _agent_checkpoint
```

## Actual output

```text
running under bash version 5.3.9(1)-release
fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted
ERROR: Failed to stage files for checkpoint
```

## Root cause

The helper could not create `.git/index.lock` in this environment. No stale lock file was left behind.

## Follow-up

- Continue with the normal `git commit` path for this task.
- Revisit `_agent_checkpoint` environment assumptions if the failure repeats on this machine.
