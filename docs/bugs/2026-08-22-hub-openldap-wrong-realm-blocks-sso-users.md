# Hub openldap is on `dc=home,dc=org`, not `dc=shopping-cart,dc=local` → dev-user SSO can't be seeded (2026-08-22)

**Severity:** high (blocks admin/developer/operator SSO login + `bin/get-keycloak-password`).
**Cluster:** hub `k3d-k3d-cluster`, ns `identity`.
**Found while:** completing step 4 (seed `secret/keycloak/users/*`) of
`docs/bugs/2026-08-22-keycloak-not-deployed-on-hub-sso-down.md` after the Keycloak
hub deploy. Keycloak itself is up and reachable (realm/master 200); this blocks
only the LDAP-federated dev users.

## Observed state

`openldap-0` (`openldap-stack-ha` container) env:

```
LDAP_ADMIN_USERNAME=ldap-admin
LDAP_ROOT=dc=home,dc=org
```

Listens on **1389** (ldap) / **1636** (ldaps); the `openldap` Service maps
389→1389, 636→1636. There is no `ldap` Service (only `openldap` /
`openldap-headless`).

Everything downstream assumes a **different** directory:

- `bin/cluster-up` LDAP user-seeding loop (~1018–1053) binds
  `cn=admin,dc=shopping-cart,dc=local` and writes
  `uid=<user>,ou=users,dc=shopping-cart,dc=local` — a tree that does not exist in
  this instance. It also targets `ldap://localhost:389` (wrong port — the server
  is on 1389), so the bind can't even connect from inside the pod.
- The Keycloak realm LDAP federation (cluster-up ~1103) uses
  `connectionUrl: ldap://ldap.identity.svc.cluster.local:389`,
  `usersDn: ou=users,dc=shopping-cart,dc=local`,
  `bindDn: cn=admin,dc=shopping-cart,dc=local`. The host `ldap.identity...`
  doesn't resolve (service is `openldap`), and the DNs don't exist here.

Net: `secret/keycloak/users/{admin,developer,operator}` was never populated
(the seed step has been silently failing), so `bin/get-keycloak-password admin`
returns "not found" and dev SSO / frontend login cannot complete.

## Likely cause

The openldap chart on this hub was installed with default values
(`dc=home,dc=org`, admin `ldap-admin`) rather than the shopping-cart values the
rest of the stack expects — a config-drift / wrong-values install, probably from
a rebuild that didn't pass the shopping-cart LDAP values (cf. the display-mirror
loss noted in `docs/issues/2026-08-22-service-credentials-na-multi-root-cause.md`).

## Remediation (needs a focused pass — do NOT hack live under time pressure)

Decide the source of truth for the directory schema, then make all three agree:

1. **openldap install values** — root DN, admin DN/username, and the `ou=users`
   subtree + the three user entries (admin/developer/operator). Either redeploy
   openldap with `dc=shopping-cart,dc=local` + `cn=admin`, or change the seeding +
   realm to match `dc=home,dc=org` + `ldap-admin`. Prefer the former (the rest of
   the stack already encodes shopping-cart).
2. **`bin/cluster-up` seed loop** — fix the port `ldap://localhost:389` →
   `:1389` (or use the `openldap` Service on 389), and bind DN/root to match (1).
3. **Keycloak realm federation** — `connectionUrl` host `ldap` → `openldap`, and
   `usersDn`/`bindDn` to match (1).
4. Re-run the seed → `secret/keycloak/users/*` populated → verify
   `bin/get-keycloak-password admin` and an SSO login round-trip.

## Verification

- `ldapsearch -x -H ldap://localhost:1389 -D "<admin-dn>" -w "$LDAP_ADMIN_PASSWORD" -b "<root>" "(uid=admin)"` returns the entry.
- `bin/vault-exec --namespace secrets -- vault kv get -field=password secret/keycloak/users/admin` returns a value.
- Frontend SSO login at `https://frontend.3ai-talk.org` completes.
