# Monthly service credential rotation

## Scope

LDAP already had a monthly rotator (`0 0 1 * *`). Grafana was Vault-backed but had no automatic rotation or restart reconciliation, so this adds a least-privilege Grafana rotation CronJob. ArgoCD, Prometheus, and Alertmanager remain unchanged pending service-specific validation.

## Design

The Grafana job authenticates to Vault with Kubernetes auth using its dedicated service account and a policy restricted to `secret/data/observability/grafana`. It writes a new password, forces an ExternalSecret refresh, and restarts Grafana. If reconciliation fails, the previous password is restored before the job exits.

## Verification

Manifest parsing, shell lint, and the observability BATS suite are required before deployment. The first scheduled run is the first day of the next month; no immediate rotation is triggered by this change.
