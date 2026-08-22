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

## Live investigation 2026-08-22 — the real scope is SMALLER than feared

Verified against the running hub, this narrows the fix considerably:

- **The realm is `home`, not `shopping-cart`.** `KEYCLOAK_REALM_NAME` defaults to
  `home` (`scripts/etc/keycloak/vars.sh:38`, `keycloak.sh:53`); `shopping-cart` is
  only `KEYCLOAK_SMOKE_REALM` (`keycloak.sh:56`). Realms present: `home`, `master`.
- **Realm `home` already has working LDAP federation** — `realm-config.json.tmpl`
  wires it at deploy time (`keycloak.sh:258` envsubst of `KEYCLOAK_LDAP_*`). The
  `ldap-provider` component exists and `admin`/`developer`/`operator` are already
  synced into Keycloak.
- **The ONLY thing missing is LDAP passwords.** All three users have NO
  `userPassword` in LDAP, so login can't validate. Seeding them (step 10d.5) is the
  entire live fix. Federation reconcile is not needed.

### Consequence for the `bin/cluster-up` fixes

- **Step 10d.5 seed loop — the relevant fix, DONE (`9efb23f7`):** pod label,
  in-pod port 1389, `cn=ldap-admin,dc=home,dc=org`, `ou=users,dc=home,dc=org`.
  This is realm-independent and is all that's required to unblock dev SSO.
- **Steps 10d.6/10d.7 (federation + group-mapper reconcile) are BOTH broken AND
  redundant** and remain a follow-up:
  - they target realm **`shopping-cart`** (`kcadm ... -r shopping-cart`) which does
    not exist → they no-op/warn;
  - they call **`/opt/keycloak/bin/kcadm.sh`** (11 refs) but the Bitnami image
    (`bitnamilegacy/keycloak:26.3.3`) has it at **`/opt/bitnami/keycloak/bin/kcadm.sh`**;
  - kcadm needs a **writable `HOME`** (container `HOME=/`, uid 1001) — it fails with
    `Failed to create config file: /.keycloak/kcadm.config` unless `HOME=/tmp` is set.
  - Because realm `home` is already federated by the template, the cleanest fix is
    to **delete 10d.6/10d.7** (or retarget them to `-r home` + Bitnami path + `HOME`);
    the `dc=home,dc=org` values committed into those blocks are correct-but-inert
    until the realm ref is fixed. **Decision needed:** delete vs retarget.

### Live seed (applied out-of-band while classifier-blocked in-agent)

`scripts/seed-dev-sso-passwords.sh`-equivalent: for each of admin/developer/operator,
generate/reuse a password, `POST secret/data/keycloak/users/<u>`, `ldappasswd -S`
(stdin, port 1389, `cn=ldap-admin,dc=home,dc=org`), verify with `ldapwhoami`.

## Verification

- `ldapsearch -x -H ldap://localhost:1389 -D "cn=ldap-admin,dc=home,dc=org" -w "$LDAP_ADMIN_PASSWORD" -b "uid=admin,ou=users,dc=home,dc=org" userPassword` shows the attribute.
- `bin/vault-exec --namespace secrets -- vault kv get -field=password secret/keycloak/users/admin` returns a value.
- SSO login to realm `home` (and `https://frontend.3ai-talk.org`) completes as `admin`.
