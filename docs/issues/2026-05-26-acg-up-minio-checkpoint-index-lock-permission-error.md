# 2026-05-26 — `_agent_checkpoint` cannot create `.git/index.lock` during MinIO seed change

**Repository:** `k3d-manager`
**Context:** `bin/acg-up` MinIO Vault KV seed

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

The environment could not create `.git/index.lock` when `_agent_checkpoint` tried to stage the current diff. No stale lock file was left behind.

## Follow-up

- Proceed with the normal `git commit` path for the MinIO Vault seed change.
- Revisit `_agent_checkpoint` environment permissions if the failure repeats on this machine.
