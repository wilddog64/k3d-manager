# Keycloak LDAP bind DN mismatches the live LDAP admin account

## What was tested
- Reproduced the current SSO login failure from the Argo CD browser flow.
- Checked the live Keycloak pod logs.
- Queried the live LDAP directory through the new troubleshooting helper.

## Actual output
Live Keycloak log excerpt:

```text
User returned from LDAP has null username!
Mapped username LDAP attribute: mail
attributes from LDAP: {}
```

Live LDAP bind failure:

```text
$ bin/ldap-search --filter '(uid=admin)' mail uid cn sn givenName dn
ldap_bind: Invalid credentials (49)
command terminated with exit code 49
```

Live cluster inspection showed the LDAP admin secret decodes to username `ldap-admin`, while Keycloak is still configured with:

```text
LDAP_BIND_DN: cn=admin,dc=shopping-cart,dc=local
```

## Root cause
Keycloak is binding to LDAP as `cn=admin,dc=shopping-cart,dc=local`, but the live LDAP admin identity exposed by the cluster is `ldap-admin`. That mismatch prevents LDAP bind from succeeding, so Keycloak cannot resolve the user and Argo CD SSO fails before login completes.

## Recommended follow-up
- Update `shopping-cart-infra/identity/keycloak/configmap.yaml` so Keycloak binds as `cn=ldap-admin,dc=shopping-cart,dc=local`, or
- Re-seed the live LDAP admin secret/bootstrap so the bind identity matches the current Keycloak config consistently.

## Relevant source files
- `identity/keycloak/configmap.yaml`
- `identity/ldap/bootstrap.yaml`
- `identity/ldap/ldap-secrets-externalsecret.yaml`
- `identity/keycloak/realm-shopping-cart.json`
