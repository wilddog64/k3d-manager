# `make up` smoke test blocked before cluster validation

## What I tested

- Ran `shellcheck scripts/lib/core.sh`
- Ran `grep -n 'cluster_name_value=.*k3d-cluster' scripts/lib/core.sh`
- Ran `make up` as the live smoke test requested by the spec

## Actual output

```text
[make] Running bin/acg-up...
INFO: [acg-up] Step 1/12 — Getting k3s-aws credentials...
INFO: [acg] Chrome CDP not available on port 9222 — launching Chrome...
make: *** [up] Error 1
```

## Root cause

The smoke test stopped before it reached the cluster YAML validation path. The failure appears to be an environment/runtime issue with the Chrome CDP startup path, not the `CLUSTER_NAME` default change.

## Follow-up

- Re-run `make up` in an environment with a working Chrome CDP session
- Confirm the run reaches the cluster template step and no longer emits the empty `metadata.name` validation error
