# Vault ESO SecretStore remained NotReady during `deploy_ldap`

## Impact
- `k3d-manager deploy_ldap` timed out waiting for the Vault-backed secret `directory/openldap-admin`.
- External Secrets reported `SecretStore "vault-kv-store" is not ready`, so the LDAP Helm release never received admin credentials.

## What we saw
- `scratch/deploy_ldap_error.log`: repeated timeout while waiting for `directory/openldap-admin`.
- `scratch/openldap-admin-error.log`: ESO controller emitted `error processing spec.data[0] ... SecretStore "vault-kv-store" is not ready`.
- Vault logs showed the Kubernetes auth endpoint was mounted at `kubernetes/`, not `auth/kubernetes/`.

## Root causes
1. The ESO SecretStore template (`scripts/etc/ldap/eso.yaml`) pointed Kubernetes auth to `auth/kubernetes`. Vault enables that backend at `kubernetes`, so ESO was trying to authenticate against a path that does not exist.
2. While broadening the Vault policy for LDAP, the helper `_vault_configure_secret_reader_role` temporarily had a syntax error (missing `done`). That prevented the function from being defined, so the LDAP deployment aborted before wiring the policy.

## Fix
- Updated `scripts/etc/ldap/eso.yaml` to set `mountPath: kubernetes`, aligning ESO with Vault's auth mount.
- Extended `_vault_configure_secret_reader_role` in `scripts/plugins/vault.sh` to add metadata read/list permissions for parent prefixes and corrected the loop syntax so the helper loads properly.

## Verification
- `./k3d-manager deploy_ldap` now completes, ESO marks `vault-kv-store` Ready, and Kubernetes receives the `directory/openldap-admin` secret.
