# acg-up: PLUGINS_DIR is unbound before plugin sources load

## Status
Fixed

## What happened
Running `make up` failed before the Argo CD readiness step:

```text
[make] Running bin/acg-up...
/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/plugins/argocd.sh: line 7: PLUGINS_DIR: unbound variable
make: *** [up] Error 1
```

## Root cause
`bin/acg-up` sourced `scripts/plugins/argocd.sh` before defining `PLUGINS_DIR`, but `scripts/plugins/argocd.sh` uses `PLUGINS_DIR` immediately while sourcing its nested plugin dependencies.

## Fix
`bin/acg-up` now initializes `PLUGINS_DIR="${SCRIPT_DIR}/plugins"` before any plugin scripts are sourced.

## Follow-up
Keep plugin bootstrap variables initialized in the top-level entrypoint before sourced plugins run so `set -u` does not abort startup.
