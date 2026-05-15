# Argo CD port-forward wrapper still trips `nounset` on the optional context args

## What was tested
- Ran `make up` after the prior context-fallback fix.
- Observed the rendered launchd wrapper fail before the Argo CD port-forward could become healthy.

## Actual output
```text
[argocd-pf] port-forward exited before healthz became reachable — restarting
[argocd-pf] starting port-forward: svc/argocd-server -> localhost:8080
/Users/cliang/.local/share/k3d-manager/argocd-port-forward.sh: line 49: _kubectl_context_args[@]: unbound variable
[argocd-pf] port-forward exited before healthz became reachable — restarting
make: *** [up] Error 1
```

## Root cause
- The rendered wrapper still expanded an optional `_kubectl_context_args[@]` array under `set -u`.
- The generated script also rendered an empty `KUBECONFIG_FILE` as a quoted empty string, which is not what the wrapper wants when no kubeconfig override is present.

## Follow-up
- Render the context selector as a scalar string instead of an empty array.
- Render an absent kubeconfig as truly empty so the wrapper can skip exporting `KUBECONFIG`.
