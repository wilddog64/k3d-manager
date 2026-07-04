# Issue: `deploy_observability_acg` default invocation passed `--help` as the context

## What was attempted

Ran:

```text
./scripts/k3d-manager deploy_observability_acg
```

## Actual output

```text
running under bash version 5.3.15(1)-release
INFO: [observability] Deploying ACG observability stack...
applicationset.argoproj.io/observability-acg configured
INFO: [observability] ACG ApplicationSet applied — ArgoCD will sync monitoring/trivy-system on --help
error: context "--help" does not exist
error: context "--help" does not exist
kubectl command failed (1): kubectl create namespace monitoring --context --help --dry-run=client -o yaml
ERROR: failed to execute kubectl create namespace monitoring --context --help --dry-run=client -o yaml: 1
kubectl command failed (1): kubectl apply --context --help -f -
ERROR: failed to execute kubectl apply --context --help -f -: 1
INFO: [observability] Ensured monitoring namespace exists on --help
```

## Observed behavior

The default invocation did not resolve the provider context. It treated `--help` as the
context argument and then tried to run `kubectl --context --help ...`.

## Workaround used

This task was completed with the explicit context form:

```text
./scripts/k3d-manager deploy_observability_acg ubuntu-hostinger
```

That path succeeded and removed the stale dashboard from the app cluster.

## Root cause

Not diagnosed in this task. The behavior appears to be in the dispatcher/default-argument
path rather than in the dashboard cleanup logic itself.

## Recommended follow-up

Trace how the dispatcher invokes `deploy_observability_acg` with no positional arguments
and why `--help` is being forwarded as `$1`.
