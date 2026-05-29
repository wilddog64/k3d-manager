# Agent Command Not Found

## What was tested

Attempted to run the repo-required agent checks in `k3d-manager` before committing the memory-bank update:

```text
_agent_checkpoint
_agent_lint
_agent_audit
```

## Actual Output

```text
zsh:1: command not found: _agent_checkpoint
zsh:1: command not found: _agent_lint
zsh:1: command not found: _agent_audit
```

## Root Cause

The expected agent helper commands are not available as standalone shell commands in this session.

## Recommended Follow-up

Run the agent checks through the environment that defines them, or use the project-preferred wrapper/hook mechanism if one exists for this repo.
