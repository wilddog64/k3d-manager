# Issue: Hostinger refresh blocked before stale-ownership cleanup by Prometheus basic-auth Vault write failure

## What was attempted

Ran:

```text
make refresh CLUSTER_PROVIDER=k3s-hostinger
```

while validating the Hostinger stale-ownership/frontend DNS fix on `k3d-manager-v1.12.0`.

## Actual output

```text
running under bash version 5.3.15(1)-release
INFO: [k3s-hostinger] Refreshing ubuntu-hostinger kubeconfig + ArgoCD registration…
INFO: [k3s-hostinger] Removed stale ubuntu-hostinger context
INFO: [k3s-hostinger] ubuntu-hostinger merged into ~/.kube/config (current-context preserved: k3d-k3d-cluster)
INFO: [k3s-hostinger] ensured argocd-manager SA/RBAC on ubuntu-hostinger
INFO: [k3s-hostinger] Registering 'ubuntu-hostinger' (https://2.25.146.252:6443) with hub ArgoCD ns cicd...
INFO: [argocd] registering app cluster 'ubuntu-hostinger' -> https://2.25.146.252:6443
secret/cluster-ubuntu-hostinger configured
INFO: [argocd] cluster secret applied — verify with: kubectl get secret cluster-ubuntu-hostinger -n cicd
INFO: [argocd] app-cluster role label set on 'ubuntu-hostinger' (cleared from others)
INFO: [k3s-hostinger] Registered — verify: kubectl get secret cluster-ubuntu-hostinger -n cicd
INFO: [vault] in-cluster profile: configuring app-cluster auth on 'ubuntu-hostinger' Vault
INFO: [vault] configuring app cluster auth at mount: kubernetes-app
Success! Data written to: auth/kubernetes-app/configSuccess! Data written to: auth/kubernetes-app/role/eso-app-clusterINFO: [vault] app cluster auth configured successfully
INFO: [observability] Deploying ACG observability stack...
applicationset.argoproj.io/observability-acg unchanged
INFO: [observability] ACG ApplicationSet applied — ArgoCD will sync monitoring/trivy-system on ubuntu-hostinger
INFO: [observability] Ensured monitoring namespace exists on ubuntu-hostinger
INFO: [observability] Reading Alertmanager credentials from Vault...
WARN: [observability] Alertmanager Vault secret not found — skipping SMS config on ACG
WARN: [observability] Run: make alertmanager-secret to configure
INFO: [observability] Ensuring Prometheus basic auth secret exists in Vault.
ERROR: [observability] Failed to create Prometheus basic auth secret in Vault.
make: *** [refresh] Error 1
```

## Impact

The refresh aborted before `_hostinger_reapply_gitops_applicationsets` and
`_hostinger_clear_stale_platform_tracking_ids` ran, so the new frontend DNS self-heal path
could not be validated through the normal refresh flow in this run.

## Root Cause

Unknown from this run. The failure is inside the observability bootstrap path that ensures the
Prometheus basic-auth secret exists in Vault for the app cluster.

## Recommended follow-up

1. Inspect `deploy_observability_acg` / the Prometheus basic-auth Vault write path in
   `scripts/plugins/observability.sh`.
2. Re-run `make refresh CLUSTER_PROVIDER=k3s-hostinger` after that Vault write failure is fixed.
3. Keep this issue separate from the stale frontend DNS bug; it is a refresh pipeline blocker,
   not the frontend `/api/products` root cause.
