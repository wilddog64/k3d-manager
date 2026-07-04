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

`deploy_observability_acg()` treated Prometheus basic-auth Vault bootstrap as a hard precondition
for the entire Hostinger refresh. When `secret/k3d-manager/prometheus-basic-auth` was absent,
`_prometheus_acg_web_config_secret()` attempted to create it with a hand-built JSON payload and
returned `_err` / exit 1 if the write failed for any reason. That made refresh abort even though
the immediate requirement for the app cluster was only the generated Kubernetes secret
`monitoring/prometheus-web-config`.

Two fixes were required:

1. Build the Vault payload with JSON serialization instead of shell-splicing the password into the
   request body.
2. Downgrade a failed bootstrap write/readback to a warning and fall back to the generated web
   config for the current run, so refresh can continue.

## Resolution

Implemented in `scripts/plugins/observability.sh` with regression coverage in
`scripts/tests/lib/observability.bats`:

- Added `_observability_prometheus_vault_payload()` to serialize the bootstrap payload safely.
- Changed `_prometheus_acg_web_config_secret()` so a failed Vault create/readback logs `WARN` and
  continues with the generated `prometheus-web-config` secret instead of aborting refresh.

## Live validation after fix

Re-ran:

```text
make refresh CLUSTER_PROVIDER=k3s-hostinger
```

Observed the previously fatal segment complete as:

```text
INFO: [observability] Ensuring Prometheus basic auth secret exists in Vault.
WARN: [observability] Failed to create Prometheus basic auth secret in Vault — using generated web config for this run
secret/prometheus-web-config unchanged
INFO: [observability] Prometheus web config secret applied (monitoring/prometheus-web-config on ubuntu-hostinger)
...
INFO: [k3s-hostinger] Refresh complete — ubuntu-hostinger reachable
__WEBHOOK_SUCCESS__
```

## Recommended follow-up

1. Inspect why the local Vault bootstrap write still fails in this environment even though refresh
   now continues safely; the remaining warning is non-blocking but still indicates missing
   persistence in Vault.
2. Keep this issue separate from the stale frontend DNS bug; it was a refresh pipeline blocker,
   not the frontend `/api/products` root cause.
