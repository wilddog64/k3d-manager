# Issue: Live LDAP bind secret returns invalid credentials against the running directory

**Date:** 2026-05-12
**Repo:** `k3d-manager`
**Area:** identity / troubleshooting

## What happened

After `make up` completed the Keycloak/Argo CD bootstrap, logging into Argo CD SSO still failed with Keycloak's generic identity-provider error page:

```text
We are sorry...
Unexpected error when handling authentication request to identity provider.
```

Keycloak logs showed the LDAP provider was active with the expected shopping-cart DN settings:

```text
usersDn=[ou=users,dc=shopping-cart,dc=local]
bindDn=[cn=admin,dc=shopping-cart,dc=local]
usernameLDAPAttribute=[mail]
connectionUrl=[ldap://ldap.identity.svc.cluster.local:389]
```

Then an actual login attempt failed with:

```text
Failed authentication: org.keycloak.models.ModelException: User returned from LDAP has null username! Check configuration of your LDAP mappings. Mapped username LDAP attribute: mail, user DN: uid=admin,ou=users,dc=shopping-cart,dc=local, attributes from LDAP: {}
```

I also queried the live LDAP directory using the troubleshooting helper:

```text
$ bin/ldap-search --filter '(uid=admin)' mail uid cn sn givenName dn
ldap_bind: Invalid credentials (49)
command terminated with exit code 49
```

That query used the live `openldap-admin` secret from the cluster and still could not bind to LDAP.

## Root cause

The running LDAP stack is not accepting the live bind credentials that the cluster currently exposes through `openldap-admin`.

That means Keycloak can reach the LDAP service, but the identity stack is still out of sync at the bind layer, so user lookup/authentication fails before SSO can complete.

## Follow-up

- Reconcile the live LDAP admin secret with the actual running directory credentials.
- If the directory was rebuilt from stale persisted data, resync or recreate the LDAP volume/secret pair so the bind DN and password match again.
- After that, rerun the SSO login using `admin@shopping-cart.local`.
