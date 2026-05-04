# 2026-05-03 — `_agent_audit` fails in zsh because of `status`

## What Was Tested

I staged the docs-only review-fix patch and ran:

```bash
source scripts/lib/system.sh
source scripts/lib/agent_rigor.sh
_agent_audit
```

This was executed from the default session shell (`zsh`).

## Actual Output

```text
_agent_audit:20: read-only variable: status
```

## Root Cause

`scripts/lib/agent_rigor.sh` uses a local variable named `status` inside `_agent_checkpoint`
and `_agent_audit`. In zsh, `status` is a special readonly parameter, so sourcing the
function in a zsh shell fails before the audit can run.

## Recommended Follow-Up

- Rename the `status` locals in `scripts/lib/agent_rigor.sh` to a non-reserved name.
- Keep the audit invocation in `bash` for now when running it manually from the shell.
- Add a small regression test if the helper is changed so the zsh collision does not return.
