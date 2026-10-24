# Dispatch preflight issue: shell special variable and git metadata permissions

## What was attempted

Before committing dispatch scopes, the repo-prescribed `_agent_checkpoint` helper was first sourced in interactive zsh. It failed because zsh reserves `status`:

```text
_agent_checkpoint:18: read-only variable: status
```

The helper was then invoked from Bash. The workspace sandbox allows editing tracked files but denied writes to `.git/index`, so checkpoint staging did not occur. Exact output:

```text
fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted
scripts/lib/foundation/scripts/lib/agent_rigor.sh: line 28: _err: command not found
fatal: Unable to create '/Users/cliang/src/gitrepo/personal/k3d-manager/.git/index.lock': Operation not permitted
scripts/lib/foundation/scripts/lib/agent_rigor.sh: line 37: _err: command not found
```

No staging or commit was performed. The first error is avoided by invoking from Bash. The second appears to reflect the managed filesystem permission boundary; `_err` was also not loaded by the standalone helper invocation.

## Follow-up

Use a reviewed permission escalation for the specifically scoped git add/commit/push operations, and source the normal project shell helpers when running the repo rigor functions. If escalation is unavailable, do not claim dispatch was started because the dispatcher requires tracked, pushed specs.
