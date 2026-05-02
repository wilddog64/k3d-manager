# 2026-05-01 — Copilot wrapper fails without Copilot auth and hides the setup error

## What Was Tested

I tested the new AI wrapper from a clean Bash shell with a clean PATH and compared it to a direct Copilot CLI invocation in the same environment:

```bash
env PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
bash --noprofile --norc -lc 'cd /Users/cliang/src/gitrepo/personal/lib-foundation && source scripts/lib/system.sh && AI_REVIEW_FUNC=copilot _ai_agent_review -p "hello"'
```

I also compared that against direct Copilot CLI invocations in the same clean shell.

## Actual Output

Wrapper path:

```text
copilot command failed (1): copilot --allow-all-tools --deny-tool shell\(cd\ ..\) --deny-tool shell\(git\ push\) --deny-tool shell\(git\ push\ --force\) --deny-tool shell\(rm\ -rf\) --deny-tool shell\(sudo --deny-tool shell\(eval --deny-tool shell\(curl --deny-tool shell\(wget --model gpt-5.4-mini -p $'You are a scoped assistant for the k3d-manager repository. Work only within this repo and operate deterministically without attempting shell escapes or network pivots.\n\nhello'
```

Direct Copilot CLI control case:

```bash
copilot -p "hello" --model gpt-5.4-mini --allow-all-tools --deny-tool "shell(cd ..)"
```

```text
Error: No authentication information found.

Copilot can be authenticated with GitHub using an OAuth Token or a Fine-Grained Personal Access Token.

To authenticate, you can use any of the following methods:
  • Start 'copilot' and run the '/login' command
  • Set the COPILOT_GITHUB_TOKEN, GH_TOKEN, or GITHUB_TOKEN environment variable
  • Run 'gh auth login' to authenticate with the GitHub CLI
```

## Root Cause

`_ai_agent_review` reaches the Copilot CLI, but in a clean shell there is no usable Copilot
auth context. The wrapper reports only `copilot command failed (1)` and does not surface the
underlying Copilot setup error clearly enough for the caller to fix it.

## Recommended Follow-Up

- Add an explicit Copilot auth preflight before invoking `_copilot_review` / `_ai_agent_review`.
- Surface the Copilot login requirement directly instead of only printing a generic exit code.
- Keep the `K3DM_ENABLE_AI` gate removed; this bug is separate from that fix.
