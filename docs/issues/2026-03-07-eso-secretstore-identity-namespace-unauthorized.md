# Issue: ESO SecretStore `identity/vault-kv-store` — namespace not authorized

## Date
2026-03-07

## Discovered During
OrbStack cluster teardown + rebuild validation (Task 3, v0.7.0)

## Symptom

After `deploy_ldap`, the `identity/vault-kv-store` SecretStore enters
`InvalidProviderConfig` state within ~5 minutes of deployment:

```
Warning  InvalidProviderConfig  ...  unable to log in to auth method:
unable to log in with Kubernetes auth: Error making API request.
URL: PUT http://vault.secrets.svc:8200/v1/auth/kubernetes/login
Code: 403. Errors: * namespace not authorized
```

`directory/vault-kv-store` and `cicd/vault-kv-store` remain Valid.

## Root Cause

`deploy_ldap` creates the Vault Kubernetes auth role `eso-ldap-directory`
bound to namespace `[directory]` only. However, `deploy_ldap` also creates
a `vault-kv-store` SecretStore in the `identity` namespace using the same
role and service account (`eso-ldap-sa`).

On first sync the secrets succeed (ESO synced before the role narrowed to
`directory` only — or the SecretStore is briefly Valid before the second
SecretStore creation updates the role). On the next reconcile cycle the
identity namespace token is rejected by Vault.

## Impact

- `identity/openldap-admin` and `identity/openldap-bitnami-ldif-import`
  ExternalSecrets show `SecretSynced: True` after initial deploy (secrets
  already exist). But the 1-hour refresh cycle will fail, causing secrets
  to go stale.
- OpenLDAP in `identity` namespace continues to function with the already-
  synced secrets until next refresh window.

## Manual Workaround (applied during rebuild)

Update the Vault role to include both namespaces:

```bash
VAULT_TOKEN="$(kubectl get secret vault-root -n secrets \
  -o jsonpath='{.data.root_token}' | base64 -d)"
kubectl exec -n secrets vault-0 -- env VAULT_TOKEN="$VAULT_TOKEN" \
  vault write auth/kubernetes/role/eso-ldap-directory \
    bound_service_account_names=eso-ldap-sa \
    bound_service_account_namespaces=directory,identity \
    policies=eso-ldap-directory \
    ttl=1h

# Force ESO reconcile
kubectl annotate secretstore vault-kv-store -n identity \
  force-sync="$(date +%s)" --overwrite
```

## Proper Fix

In `scripts/plugins/ldap.sh` (or `scripts/plugins/vault.sh`), when
creating/updating the `eso-ldap-directory` Kubernetes auth role, include
all namespaces that use the role:

```bash
vault write auth/kubernetes/role/eso-ldap-directory \
  bound_service_account_names=eso-ldap-sa \
  bound_service_account_namespaces=directory,identity \
  ...
```

Alternatively, use a namespace selector label if more than two namespaces
are expected.

## Assigned To

Codex — v0.7.0 backlog (low priority, workaround in place)

## Related

- `docs/issues/2026-03-07-deploy-cluster-if-count-violation.md`
