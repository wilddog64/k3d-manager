# OpenLDAP consumer reconciliation

## What was tested

After the Symas OpenLDAP StatefulSet became ready, Keycloak, ArgoCD, and Jenkins
consumer state was checked against the new `identity/openldap` service.

## Actual output

Keycloak's first `deploy_keycloak --enable-ldap --confirm` attempt reported:

```text
Error uploading policy: ... 'policy' parameter not supplied or empty
```

The Keycloak helper piped a policy heredoc into `_vault_exec_stream` without
its `--stdin` flag. After adding that flag, the policy upload succeeded and the
LDAP ExternalSecret became `SecretSynced=True`.

The first post-migration realm user list contained only `chengkai.liang`,
`jenkins-admin`, `k3dm-smoke`, and `test-user`; `admin`, `developer`, and
`operator` were absent. Those three accounts are seeded from Vault by
`bin/cluster-up`, but its old LDAP label, port, and shopping-cart DNs no longer
matched the Symas chart. The users were restored from their Vault passwords and
the seeding path was updated for the new StatefulSet contract.

The existing Keycloak realm still pointed at the retired service and base:

```text
ldap://ldap.identity.svc.cluster.local:389
ou=users,dc=shopping-cart,dc=local
```

The federation and group mapper were reconciled to:

```text
ldap://openldap.identity.svc.cluster.local:389
ou=users,dc=home,dc=org
ou=groups,dc=home,dc=org
```

Full sync returned:

```text
3 imported users, 0 updated users
```

The documented bootstrap user login through the `k3dm-smoke` client returned
HTTP 200 and `login-ok`. ArgoCD is OIDC-based (Keycloak issuer), and Jenkins is
not deployed in this cluster, so neither required an LDAP consumer change.
The restored `developer` account also returned HTTP 200 through the same smoke
client.

## Root cause

The live realm predated the chart migration and retained the old LDAP service,
base DNs, group mapper, and bind credential. The optional password rotator also
defaulted to the old chart label, so it could not locate `openldap-0`.

## Resolution

The Keycloak Vault policy stream now requests stdin explicitly. The rotator
defaults now select `app.kubernetes.io/component=openldap`, matching the
Symas chart's StatefulSet label. `bin/cluster-up` and the bootstrap LDIF now
use the Symas label/port/DNs and include the three Vault-seeded platform users.
