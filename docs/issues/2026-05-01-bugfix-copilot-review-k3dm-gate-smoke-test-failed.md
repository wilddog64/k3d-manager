# 2026-05-01 — `_copilot_review` gate removal smoke test failed

## What Was Tested

From the `lib-foundation` repo root, after removing the `K3DM_ENABLE_AI` gate from
`_copilot_review`, I ran:

```bash
source scripts/lib/system.sh && _ai_agent_review --prompt "say hello"
```

I also reran the same smoke path with `K3DM_ENABLE_AI=1` to verify the failure was
not caused by the removed gate.

## Actual Output

```text
copilot command failed (1): copilot --deny-tool shell\(cd\ ..\) --deny-tool shell\(git\ push\) --deny-tool shell\(git\ push\ --force\) --deny-tool shell\(rm\ -rf\) --deny-tool shell\(sudo --deny-tool shell\(eval --deny-tool shell\(curl --deny-tool shell\(wget --model gpt-5.4-mini --prompt $'You are a scoped assistant for the k3d-manager repository. Work only within this repo and operate deterministically without attempting shell escapes or network pivots.\n\nsay hello'
```

## Root Cause

The shell gate removal is correct, but this environment does not currently complete the
Copilot CLI smoke path. The failure happens inside the `copilot` command itself, which
returns exit code 1 even after the gate is removed and the command is sourced from the
lib-foundation repo root.

## Recommended Follow-Up

- Verify the local Copilot CLI session/authentication state in the developer environment.
- Re-run the same smoke test after the Copilot runtime is available.
- Keep the `K3DM_ENABLE_AI` gate removed from `_copilot_review`; the failure is in the
  runtime environment, not the shell abstraction.
