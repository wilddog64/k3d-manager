# Issue: `vault-auth-delegator` ClusterRoleBinding naming and management

## Date
2026-02-27

## Environment
- Hostname: `m4-air.local`
- OS: Darwin (macOS)
- Cluster Provider: `orbstack`
- Vault Helm Chart: `vault-0.30.1`

## Symptoms
The validation instruction expected a ClusterRoleBinding named `vault-auth-delegator`. However, after running `deploy_vault`, this specific name was not found. Instead, the `system:auth-delegator` role was already correctly bound to the `vault:vault` service account via a binding named `vault-server-binding`.

## Root Cause
The `hashicorp/vault` Helm chart (v0.30.1) automatically creates a ClusterRoleBinding named `vault-server-binding` that grants the `system:auth-delegator` ClusterRole to the Vault ServiceAccount if `server.authDelegator.enabled` is set to `true` (which is the default in our configuration).

The manual fix previously applied used the name `vault-auth-delegator`, which led to the confusion during validation.

## Findings
1. The required permission (`system:auth-delegator`) **is present** and managed by the Helm release.
2. `vault-server-binding` is the name used by the Helm chart.
3. Vault K8s auth is fully functional (verified via E2E test).

## Resolution
Update the validation documentation to look for `vault-server-binding` or recognize that the Helm chart manages this resource. The code in `scripts/plugins/vault.sh` that attempts to create `vault-auth-delegator` may be redundant if Helm is already providing it, but it serves as a safety net for non-Helm deployments or different chart versions.

## Evidence
`kubectl get clusterrolebinding vault-server-binding -o yaml`:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    app.kubernetes.io/instance: vault
    app.kubernetes.io/name: vault
  name: vault-server-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault
  namespace: vault
```
