# Keycloak shopping-cart SSO federates the osixia `ldap` (`dc=shopping-cart,dc=local`), NOT the seeded `openldap-0` (`dc=home,dc=org`)

**Date:** 2026-09-04
**Severity:** high — `bin/get-keycloak-password <user>` returns a password that does **not** work for shopping-cart SSO login.
**Cluster:** hub `k3d-k3d-cluster`, ns `identity`.
**Found while:** completing the v1.28.0 two-cloud "two-LDAP-instance federation check" follow-up.
**Supersedes state in:** `docs/bugs/2026-08-22-hub-openldap-wrong-realm-blocks-sso-users.md` (that doc predates the osixia `ldap` Deployment — at the time "there is no `ldap` Service, only `openldap`"). The landscape has since changed.

## Observed state (live, verified)

Two **distinct** LDAP directories now coexist in `identity` on the hub:

| Directory | Pod / origin | Base DN | Bind DN | Users present |
|-----------|--------------|---------|---------|---------------|
| **openldap-0** | Helm `openldap-stack-ha` StatefulSet (Symas, commit `1bbb74b0`); svc `openldap` 389→1389 | `dc=home,dc=org` | `cn=ldap-admin,dc=home,dc=org` | admin, developer, operator, test-user, jenkins-admin, chengkai.liang |
| **ldap** | osixia/openldap:1.5.0 Deployment, ArgoCD-managed by app `shopping-cart-identity` (created 2026-09-04); svc `ldap` :389 | `dc=shopping-cart,dc=local` | `cn=admin,dc=shopping-cart,dc=local` | admin, developer, operator |

**What cluster-up seeds** (Step 10d.5, `bin/cluster-up:1017-1071`): binds `openldap-0`
(`cn=ldap-admin,dc=home,dc=org`, ldap://localhost:1389, pod label `openldap-stack-ha`),
sets `uid=<user>,ou=users,dc=home,dc=org` passwords, and mirrors them to Vault
`secret/keycloak/users/<user>`. This works correctly (after the 2026-08-22 direction fix +
the 2026-09-04 `-y` trailing-newline fix `41389804`).

**What Keycloak actually reads** (live federation component, realm `shopping-cart`):
```
name          : ldap
connectionUrl : ldap://ldap.identity.svc.cluster.local:389   ← osixia ldap, NOT openldap
usersDn       : ou=users,dc=shopping-cart,dc=local
bindDn        : cn=admin,dc=shopping-cart,dc=local
editMode      : READ_ONLY
```

## Proof of decoupling

Binding to the SSO-path directory (`ldap` svc) as `uid=developer,ou=users,dc=shopping-cart,dc=local`
with the **Vault-seeded** developer password → `ldap_bind: Invalid credentials (49)`.
The seeded password lives in `openldap-0` (`dc=home,dc=org`); Keycloak validates against the
osixia `ldap` (`dc=shopping-cart,dc=local`), which has its own (declaratively-seeded) passwords.

Net: the "Seeding Keycloak LDAP user passwords" step populates a directory the shopping-cart
realm never reads. SSO logs in against osixia `ldap`; `bin/get-keycloak-password` reports the
openldap-0/Vault value, which is wrong for SSO.

## Root cause

The realm federation `connectionUrl` (`scripts/etc/keycloak/realm-config.json.tmpl:21`, via
`KEYCLOAK_LDAP_HOST` — default `openldap.identity.svc.cluster.local`, `scripts/etc/keycloak/vars.sh:32`)
resolved at import to `ldap.identity.svc.cluster.local` / base `dc=shopping-cart,dc=local`, matching
the osixia `ldap` Deployment shipped by the `shopping-cart-identity` ArgoCD app — a directory
**different** from the one the cluster-up seed targets (`openldap-0` / `dc=home,dc=org`). The two
were wired independently and never reconciled after osixia `ldap` was introduced.

## Decision needed (do NOT implement blind)

Which directory is canonical for shopping-cart SSO?

- **Option A — osixia `ldap` is canonical (likely intended):** it is ArgoCD-managed and is what
  Keycloak already federates. Then the cluster-up Step 10d.5 seed should target
  `ldap.identity.svc:389` / `dc=shopping-cart,dc=local` / `cn=admin` (or be recognized as seeding a
  *separate* hub/Jenkins directory and renamed so it no longer implies it feeds Keycloak SSO).
  Caveat: osixia `ldap` is declaratively managed + `editMode: READ_ONLY` in Keycloak — writing
  passwords imperatively may fight ArgoCD; confirm the intended password source of truth first.
- **Option B — openldap-0 is canonical:** repoint the realm federation to
  `openldap.identity.svc:389` / `dc=home,dc=org` / `cn=ldap-admin` and retire the osixia `ldap`
  Deployment from `shopping-cart-identity`.
- **Option C — two directories by design** (openldap-0 = hub/Jenkins general dir; osixia `ldap` =
  app SSO dir): then Step 10d.5's name/scope is misleading — it does not feed SSO. Document the
  split and stop implying `get-keycloak-password` yields SSO creds.

## What NOT to do

- Do NOT change the realm base DN or the seed target before the canonical-directory decision — a
  wrong guess breaks either SSO or the hub/Jenkins directory.
- Do NOT imperatively write to the osixia `ldap` if ArgoCD is meant to own its entries — that
  reintroduces drift on the next sync.

## Verification once resolved

- `bin/get-keycloak-password developer` → the returned password binds successfully to the directory
  Keycloak federates (single `ldapwhoami` against the live `connectionUrl`).
- A real SSO login (frontend → Keycloak → shopping-cart) succeeds for a seeded dev user.
