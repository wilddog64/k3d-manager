# How-To: Keycloak

Keycloak provides identity federation for the infra cluster — SSO for Jenkins, ArgoCD, and other services. k3d-manager deploys Keycloak and can connect it to the OpenLDAP or Active Directory directory service.

## Prerequisites

- Infra cluster running (`deploy_cluster`)
- LDAP/AD deployed (`deploy_ldap` or `deploy_ad`) if using directory federation

## Deploy Keycloak

```bash
./scripts/k3d-manager deploy_keycloak --confirm
```

Installs Keycloak via Helm into its own namespace. Admin credentials are stored in Vault.

## Smoke Test

```bash
./scripts/k3d-manager test_keycloak
```

Verifies the Keycloak pod is healthy and the admin API responds.

## Common Operations

```bash
# Access Keycloak admin UI (port-forward)
kubectl port-forward svc/keycloak -n keycloak 8443:443
# then open https://localhost:8443/auth/admin

# Get admin password from Vault
vault kv get secret/k3d-manager/keycloak
```

## LDAP Federation

To connect Keycloak to the OpenLDAP instance deployed by `deploy_ldap`:

1. Open the admin UI → User Federation → Add provider → LDAP
2. Connection URL: `ldap://openldap.ldap.svc.cluster.local:389`
3. Bind DN and credentials: retrieve from Vault (`secret/k3d-manager/ldap`)
4. User DN: `ou=users,dc=example,dc=com` (adjust to your `LDAP_BASE_DN`)

## Notes

- Keycloak uses `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` in dev — never use in production
- Admin credentials are managed via Vault/ESO — do not hardcode in manifests
