# `bin/cluster-up` seeds LDAP/realm at `dc=shopping-cart,dc=local` but the directory is `dc=home,dc=org` → dev-user SSO can't be seeded (2026-08-22)

> **Direction corrected 2026-08-22:** `dc=home,dc=org` is the *correct* designed
> directory (per `scripts/etc/ldap/vars.sh`); the consumers in `bin/cluster-up`
> are what's wrong. Original title implied the openldap was misconfigured — it is not.

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

## Root cause (CORRECTED 2026-08-22 — direction was inverted)

**The openldap is NOT drifted. `dc=home,dc=org` + `ldap-admin` is the DESIGNED
source of truth** — `scripts/etc/ldap/vars.sh` defaults `LDAP_DC_PRIMARY=home`,
`LDAP_DC_SECONDARY=org`, `LDAP_ADMIN_USERNAME=ldap-admin`, `LDAP_BIND_DN=cn=ldap-admin,dc=home,dc=org`.
A live search confirms the tree is fully correct and already holds the three dev users:

```
dn: uid=admin,ou=users,dc=home,dc=org
dn: uid=developer,ou=users,dc=home,dc=org
dn: uid=operator,ou=users,dc=home,dc=org
```

The bug is **entirely consumer-side**: `bin/cluster-up` (seed loop + realm
federation) hardcodes `dc=shopping-cart,dc=local` / `cn=admin` / `ldap.identity`
host / port `389`-from-inside-the-pod / pod label `app.kubernetes.io/name=ldap`,
none of which match the deployed instance (`dc=home,dc=org` / `cn=ldap-admin` /
service `openldap` / in-pod port `1389` / label `app.kubernetes.io/name=openldap-stack-ha`).

> ⚠️ **DO NOT redeploy openldap with `dc=shopping-cart,dc=local`** — that would
> DESTROY the correct, already-populated `dc=home,dc=org` tree. Fix the consumers
> to match the deployment, not the other way around.

## Remediation (fix the consumers — the tree is already correct)

1. **`bin/cluster-up` seed loop (~1010–1053)** — four fixes:
   - pod label `app.kubernetes.io/name=ldap` → `app.kubernetes.io/name=openldap-stack-ha`
     (the current selector matches nothing → `_ldap_pod` empty → `exit 1`).
   - in-pod URL `ldap://localhost:389` → `ldap://localhost:1389` (Bitnami listens on 1389).
   - bind DN `cn=admin,dc=shopping-cart,dc=local` → `cn=ldap-admin,dc=home,dc=org`.
   - user DN `uid=$1,ou=users,dc=shopping-cart,dc=local` → `...,ou=users,dc=home,dc=org`.
2. **Keycloak realm federation (~1103)** — `connectionUrl`
   `ldap://ldap.identity.svc.cluster.local:389` → `ldap://openldap.identity.svc.cluster.local:389`
   (the `openldap` Service maps 389→1389, so 389 is right at the Service),
   `usersDn`/`bindDn` → `ou=users,dc=home,dc=org` / `cn=ldap-admin,dc=home,dc=org`.
3. Re-run the seed → `secret/keycloak/users/*` populated → verify
   `bin/get-keycloak-password admin` and an SSO login round-trip.

## Verification

- `ldapsearch -x -H ldap://localhost:1389 -D "<admin-dn>" -w "$LDAP_ADMIN_PASSWORD" -b "<root>" "(uid=admin)"` returns the entry.
- `bin/vault-exec --namespace secrets -- vault kv get -field=password secret/keycloak/users/admin` returns a value.
- Frontend SSO login at `https://frontend.3ai-talk.org` completes.
