# Grafana admin credential moved to Vault

## Finding

Hub Grafana's admin credential was supplied by the Helm-generated
`monitoring/kube-prometheus-stack-grafana` Secret. The value was exposed by
the service-password display path and was not sourced from Vault.

## Resolution

- Seed the existing credential at `secret/observability/grafana` in Vault.
- Extend the ESO reader policy with read-only access to that exact path.
- Add `grafana-admin-credentials` ExternalSecret backed by the existing
  `vault-backend` ClusterSecretStore.
- Configure the kube-prometheus-stack values to use that Secret for
  `GF_SECURITY_ADMIN_USER` and `GF_SECURITY_ADMIN_PASSWORD`.
- Apply the ExternalSecret from `deploy_observability` so `make observability`
  recreates the wiring after a rebuild.

The credential value is not recorded in this issue or in Git.

