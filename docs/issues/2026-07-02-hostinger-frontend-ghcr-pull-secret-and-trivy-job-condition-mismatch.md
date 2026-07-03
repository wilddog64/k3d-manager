# Hostinger frontend GHCR pull-secret drift and Trivy job-condition mismatch

## What was tested

- `kubectl describe pod frontend-6c96666fd-ts868 -n shopping-cart-apps --context ubuntu-hostinger`
- `kubectl get deploy frontend -n shopping-cart-apps --context ubuntu-hostinger -o yaml`
- `kubectl get secret ghcr-pull-secret -n shopping-cart-apps --context ubuntu-hostinger -o yaml`
- `kubectl get externalsecret -n shopping-cart-apps ghcr-pull-secret --context ubuntu-hostinger -o yaml`
- `kubectl logs -n trivy-system acg-trivy-operator-645fb48db5-ntxxv --context ubuntu-hostinger --tail=200`
- `kubectl get application trivy-operator -n cicd --context k3d-k3d-cluster -o yaml`
- `kubectl get application acg-trivy-operator -n cicd --context k3d-k3d-cluster -o yaml`

## Actual output

Frontend pod:

```text
Warning  Failed  ...  Failed to pull image "ghcr.io/wilddog64/shopping-cart-frontend:latest": failed to resolve reference "ghcr.io/wilddog64/shopping-cart-frontend:latest": failed to authorize: failed to fetch anonymous token: unexpected status from GET request to https://ghcr.io/token?...: 401 Unauthorized
```

Frontend deployment pod spec had no `imagePullSecrets`, while the namespace
`ghcr-pull-secret` ExternalSecret and Secret were present and synced.

Trivy operator logs:

```text
error":"unrecognized scan job condition: FailureTarget"
error":"unrecognized scan job condition: SuccessCriteriaMet"
```

ArgoCD app spec was pinned to chart `0.24.1`, but the rendered deployment image
was still:

```text
ghcr.io/aquasecurity/trivy-operator:0.22.0
```

## Root cause

1. `services/shopping-cart-frontend/kustomization.yaml` did not wire
   `ghcr-pull-secret` into the frontend Deployment, so kubelet attempted an
   anonymous GHCR pull and failed with `401 Unauthorized`.
2. The Trivy Helm chart pin alone did not advance the rendered operator image
   enough for Kubernetes 1.36 Job conditions. The live operator binary stayed
   on `0.22.0` and could not reconcile `FailureTarget` /
   `SuccessCriteriaMet`.

## Recommended follow-up

- Patch frontend to set `imagePullSecrets: [ghcr-pull-secret]` on the
  Deployment pod spec.
- Override the Trivy operator image explicitly in
  `scripts/etc/helm/observability/trivy-operator-values.yaml` so the rendered
  deployment uses a current operator binary instead of the chart default.
