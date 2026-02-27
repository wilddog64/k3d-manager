# Vault Kubernetes auth fails without system:auth-delegator ClusterRoleBinding

**Date:** 2026-02-27
**Status:** FIXED

## Summary

The Vault install path never created the `system:auth-delegator` ClusterRoleBinding for the Vault service account. When
`test_vault` (Stage 2 CI) tried to log in via `auth/kubernetes/login`, the Kubernetes auth backend attempted a TokenReview
but the Vault pod's service account lacked RBAC permission. The login returned HTTP 403 and Stage 2 CI failed on m2-air.

## Impact

- `deploy_vault` leaves the Vault SA unable to call the TokenReview API.
- All Kubernetes auth consumers (ESO, Jenkins, manual `vault write auth/kubernetes/login`) fail with:
  `Error making API request. Code: 403. Errors: request forbidden: User "system:serviceaccount:vault:vault" cannot create resource "selfsubjectreviews"`.
- Stage 2 CI (`test_vault`) cannot pass on a fresh cluster without manually creating the binding.

## Fix

- After enabling the Kubernetes auth method we now run:

```
_kubectl create clusterrolebinding vault-auth-delegator \
  --clusterrole=system:auth-delegator \
  --serviceaccount="${ns}:${release}" \
  --dry-run=client -o yaml | _kubectl apply -f -
```

in both code paths (`_vault_set_eso_reader` bootstrap and the generic `_vault_set_secret_reader` helper) so every Vault
install wires the binding automatically.

## Validation

1. `CLUSTER_PROVIDER=orbstack PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager deploy_vault`
2. `kubectl get clusterrolebinding vault-auth-delegator -o yaml` → shows `subjects: serviceaccount: vault/vault`
3. `kubectl -n vault exec -it vault-0 -- vault write auth/kubernetes/login role=eso-reader jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token` → succeeds (HTTP 200).

## Follow-up

- Consider adding an explicit check in `test_vault` to assert the ClusterRoleBinding exists before running auth tests.

## Validation

`PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_vault` — 2026-02-27 (macOS/OrbStack)
```
running under bash version 5.3.9(1)-release
INFO: Testing Vault deployment and Kubernetes auth...
INFO: Preparing test namespace 'vault-test-1772229457-8663' and service account 'vault-test-1772229457-8663-sa'...
INFO: Refreshing Vault Kubernetes auth backend (TokenReview mode)...
Success! Data written to: auth/kubernetes/config
INFO: Creating temporary Vault role for service account...
WARNING! The following warnings were returned from Vault:

  * Role vault-test-1772229457-8663-sa does not have an audience. In Vault
  v1.21+, specifying an audience on roles will be required.

INFO: Seeding test secret at secret/eso/vault-secret-1772229457-8947...
================ Secret Path ================
secret/data/eso/vault-secret-1772229457-8947

======= Metadata =======
Key                Value
---                -----
created_time       2026-02-27T21:57:38.534174013Z
custom_metadata    <nil>
deletion_time      n/a
destroyed          false
version            1
pod/vault-read created
pod/vault-read condition met
INFO: Vault test succeeded
Cleaning up Vault test resources...
```

