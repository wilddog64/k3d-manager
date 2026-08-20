# Bug: `make up` hangs in recursive `_run_command` during credential validation

## Observed

`make up CLUSTER_PROVIDER=k3s-aws` advanced through Step 0 and printed Step 1,
then consumed a CPU core without progressing:

```text
INFO: [acg-up] Step 0/12 — Pruning stale public IPs from ~/.ssh/known_hosts...
INFO: [acg-up] known_hosts pruned 5 public-IP entries, kept 529
INFO: [acg-up] Step 1/12 — Getting k3s-aws credentials...
```

The active `bash bin/cluster-up` process stayed near 99% CPU for several
minutes. A direct `aws sts get-caller-identity` completed successfully.

## Root cause

`bin/cluster-up` sourced `system_overrides.sh`, loaded plugins, then unset only
`__k3dm_base_run_command` and sourced the override again. The plugins retain
the existing wrapper, so the second source captured the wrapper itself as its
new base implementation. `_run_command` then called `__k3dm_base_run_command`,
which recursively called `_run_command` forever.

## Fix

Remove the redundant post-plugin re-wrap. The initial system override remains
active, and plugin loading is guarded against replacing the existing command
implementation.

## Verification

The regression suite verifies the post-plugin command wrapper is not captured
as its own base. Existing dry-run lifecycle tests continue to pass.
