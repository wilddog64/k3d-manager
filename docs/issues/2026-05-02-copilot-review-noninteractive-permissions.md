# 2026-05-02 — Copilot review wrapper still fails to opt into non-interactive permissions

## What Was Tested

I reproduced the current wrapper path from a clean Bash shell with a clean PATH and the
current `feat/v0.3.18` auth preflight fix in place:

```bash
env PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
bash --noprofile --norc -lc 'cd /Users/cliang/src/gitrepo/personal/lib-foundation && source scripts/lib/system.sh && AI_REVIEW_FUNC=copilot _ai_agent_review -p "hello"'
```

I also inspected the Copilot CLI help to verify the execution mode it expects for
non-interactive prompts.

## Actual Output

The wrapper still fails with a generic exit-code message from the Copilot CLI layer:

```text
copilot command failed (1): copilot --deny-tool shell\(cd\ ..\) --deny-tool shell\(git\ push\) --deny-tool shell\(git\ push\ --force\) --deny-tool shell\(rm\ -rf\) --deny-tool shell\(sudo --deny-tool shell\(eval --deny-tool shell\(curl --deny-tool shell\(wget --model gpt-5.4-mini -p $'You are a scoped assistant for the k3d-manager repository. Work only within this repo and operate deterministically without attempting shell escapes or network pivots.\n\nhello'
```

The generated command does not include `--allow-all-tools`, even though the Copilot CLI help
describes that flag as required for non-interactive mode.

## Root Cause

`_copilot_review` builds a non-interactive Copilot invocation using only `--deny-tool` guards.
That is not enough to establish the CLI mode Copilot expects for scripted execution. The wrapper
does not currently opt into the non-interactive permission model explicitly, so it still exits 1
instead of completing the prompt.

## Recommended Follow-Up

- Make `_copilot_review` explicitly opt into the non-interactive permission model required by
  the Copilot CLI.
- Keep the auth preflight fix from `v0.3.18`; this is a separate layer from authentication.
- Surface a more specific error if the CLI rejects the invocation shape or permissions mode.
