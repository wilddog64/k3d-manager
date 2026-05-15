# Argo CD port-forward should not hard fail on missing `k3d-k3d-cluster` context

## What happened

Running `make up` failed while the Argo CD port-forward wrapper was restarting:

```text
error: context "k3d-k3d-cluster" does not exist
[argocd-pf] port-forward exited before healthz became reachable — restarting
[argocd-pf] starting port-forward: svc/argocd-server -> localhost:8080
error: context "k3d-k3d-cluster" does not exist
[argocd-pf] port-forward exited before healthz became reachable — restarting
[argocd-pf] starting port-forward: svc/argocd-server -> localhost:8080
error: context "k3d-k3d-cluster" does not exist
[argocd-pf] port-forward exited before healthz became reachable — restarting
make: *** [up] Error 1
```

## Root cause

The generated port-forward wrapper was still assuming that `k3d-k3d-cluster` always exists in the kubeconfig seen by launchd. In practice, the wrapper can be launched in an environment where that context is absent, so `kubectl port-forward --context k3d-k3d-cluster ...` fails immediately and the self-healing loop just retries forever.

## Fix

The wrapper now:

- prefers the requested context when it exists
- falls back to `kubectl config current-context`
- falls back again to the kubeconfig default if neither context lookup succeeds

## Follow-up

If this shows up again, inspect the kubeconfig file passed into the wrapper and confirm launchd is seeing the intended context list before `kubectl port-forward` starts.
