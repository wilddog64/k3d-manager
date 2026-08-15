# Bug: standalone `make down` fails during k3s-aws hub deregistration

## Observed

Running:

```text
make down CLUSTER_PROVIDER=k3s-aws KEEP_LOCAL=1
```

completed CloudFormation teardown and kubeconfig cleanup, then failed while
deregistering the sandbox from hub ArgoCD:

```text
INFO: [acg-down] Deregistering sandbox from hub ArgoCD...
/scripts/plugins/argocd.sh: line 7: PLUGINS_DIR: unbound variable
make: *** [down] Error 1
```

## Root cause

The standalone `bin/cluster-down` entrypoint defines `SCRIPT_DIR` but not
`PLUGINS_DIR`. The k3s-aws deregistration helper lazily sources
`scripts/plugins/argocd.sh`, whose first plugin path uses `PLUGINS_DIR` while
`set -u` is active.

## Fix

Define `PLUGINS_DIR="${SCRIPT_DIR}/plugins"` in `bin/cluster-down` before any
provider/plugin loading. Add a regression gate covering the standalone
entrypoint variable contract.

## Impact

The remote sandbox was already deleted, but hub ArgoCD cluster registration
objects could remain stale because deregistration never ran.
