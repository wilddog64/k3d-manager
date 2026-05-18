# Issue: agent rigor helper invocation emits index.lock permission error in this shell

**Date:** 2026-05-16
**Repo:** `k3d-manager`

## What was tested

I ran the repo's local rigor helpers after the feature change:

```bash
bash -lc 'source scripts/lib/agent_rigor.sh; _agent_checkpoint "post-change checkpoint"; printf "checkpoint ok\n"; _agent_lint; printf "lint ok\n"; _agent_audit; printf "audit ok\n"'
```

## Actual output

```text
fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted
scripts/lib/agent_rigor.sh: line 28: _err: command not found
fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted
scripts/lib/agent_rigor.sh: line 37: _err: command not found
checkpoint ok
lint ok
audit ok
```

## Root cause

The helper functions were invoked directly from `scripts/lib/agent_rigor.sh` without the full shell bootstrap they expect, and `_agent_checkpoint` also attempted to write `.git/index.lock` in this shell context. The `_err` helper was not available in the direct invocation path.

## Recommended follow-up

Run the rigor helpers through the repo's normal bootstrap path, or adjust the helper entrypoint so it sources its dependencies before use in ad hoc validation shells.
