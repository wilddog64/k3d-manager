# Keycloak LDAP login fails with null username when `mail` is mapped

## What I tested

I ran `make up` and then attempted Argo CD SSO login. Keycloak rejected the login with a generic identity-provider error page.

I then inspected the live Keycloak and LDAP pods and queried the admin user directly from LDAP:

```text
$ kubectl logs -n identity keycloak-745b995454-6rcd5 --tail=200
2026-05-13 02:18:48,972 INFO  [org.keycloak.storage.ldap.LDAPIdentityStoreRegistry] (executor-thread-3) Creating new LDAP Store for the LDAP storage provider: 'ldap', LDAP Configuration: {fullSyncPeriod=[604800], pagination=[true], searchScope=[2], useTruststoreSpi=[ldapsOnly], usersDn=[ou=users,dc=shopping-cart,dc=local], connectionPooling=[true], cachePolicy=[DEFAULT], priority=[0], trustEmail=[true], userObjectClasses=[inetOrgPerson, organizationalPerson], enabled=[true], bindDn=[cn=admin,dc=shopping-cart,dc=local], changedSyncPeriod=[86400], usernameLDAPAttribute=[mail], rdnLDAPAttribute=[uid], vendor=[other], editMode=[READ_ONLY], uuidLDAPAttribute=[entryUUID], connectionUrl=[ldap://ldap.identity.svc.cluster.local:389], syncRegistrations=[false], validatePasswordPolicy=[false], authType=[simple], batchSizeForSync=[1000]}, binaryAttributes: []
2026-05-13 02:18:49,056 WARN  [org.keycloak.services] (executor-thread-3) KC-SERVICES0013: Failed authentication: org.keycloak.models.ModelException: User returned from LDAP has null username! Check configuration of your LDAP mappings. Mapped username LDAP attribute: mail, user DN: uid=admin,ou=users,dc=shopping-cart,dc=local, attributes from LDAP: {}
2026-05-13 02:18:49,059 WARN  [org.keycloak.events] (executor-thread-3) type="LOGIN_ERROR", realmId="b102f5a4-3aba-428f-951f-96fdfe9532c0", clientId="argocd", userId="null", ipAddress="127.0.0.1", error="invalid_user_credentials", auth_method="openid-connect", auth_type="code", redirect_uri="https://argocd.shopping-cart.local/auth/callback", code_id="e7da654e-a54a-443f-84d0-b337c86879a4", username="admin@shopping-cart.local"
```

The LDAP entry itself does contain `mail`:

```text
$ kubectl exec -n identity ldap-56997b96d-7qc94 -- sh -lc 'ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=shopping-cart,dc=local" -w "$LDAP_ADMIN_PASSWORD" -b "uid=admin,ou=users,dc=shopping-cart,dc=local" "(uid=admin)" uid cn sn givenName mail objectClass'
# extended LDIF
#
# LDAPv3
#
# base <uid=admin,ou=users,dc=shopping-cart,dc=local> with scope subtree
# filter: (uid=admin)
# requesting: uid cn sn givenName mail objectClass
#

# admin, users, shopping-cart.local
dn: uid=admin,ou=users,dc=shopping-cart,dc=local
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
uid: admin
cn: Platform Admin
sn: Admin
givenName: Platform
mail: admin@shopping-cart.local

# search result
search: 2
result: 0 Success

# numResponses: 2
# numEntries: 1
```

## Actual behavior

Keycloak reaches LDAP, but the imported user comes back with no usable username when `usernameLDAPAttribute=mail` is configured. The browser then shows:

```text
Unexpected error when handling authentication request to identity provider.
```

## Root cause

The live Keycloak LDAP provider is configured to derive the username from `mail`, but the login/import path is not actually getting a username back from LDAP for that lookup. The live LDAP entry does have `mail`, so the failure is in the runtime mapping/import path, not the directory entry itself.

## Recommended follow-up

Align the live Keycloak LDAP configuration with the LDAP data model so the username can be imported deterministically.

Likely options:

1. Switch the LDAP username mapping back to `uid` and add an explicit email mapping if email-style login must remain supported.
2. Or keep the `mail` login path, but ensure the imported LDAP user actually exposes the attribute to Keycloak during login.

Verify the chosen approach against the live cluster before changing more bootstrap logic.
