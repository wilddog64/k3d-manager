# 2026-05-28 agent audit shell mismatch

## What I tested
- Ran `_agent_audit` from the k3d-manager repo after staging the `scripts/plugins/shopping_cart.sh` change.
- First attempt used the default `zsh` session from the Codex shell wrapper.
- Second attempt used `bash -lc` with the same sourced helpers.

## Actual output
```text
_agent_audit:20: read-only variable: status
```

## Root cause
- The first invocation sourced the bash helper function in `zsh`, which caused the audit function to fail immediately on the `status` variable assignment.
- Re-running the same function under `bash -lc` succeeded with no output.

## Recommended follow-up
- Invoke `scripts/lib/agent_rigor.sh` helpers under `bash` instead of the default `zsh` shell when validating staged changes.
- Keep the bash wrapper in future verification commands for `_agent_checkpoint`, `_agent_lint`, and `_agent_audit`.
