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

## Decision RESOLVED (2026-09-04) — Option B: openldap-0 is canonical; osixia `ldap` is orphaned drift

Investigation on the v1.29.0 branch settled the ambiguity decisively:

- **The osixia `ldap` source was deliberately retired.** `services/shopping-cart-identity`
  (the kustomization that created the osixia `ldap` Deployment) was added in PR #72
  (`b5601cb5`, an ACG-era experiment with hardcoded declarative passwords `Admin@Cart2024` /
  `Dev@Cart2024` / `Ops@Cart2024`) and **removed in PR #74** (`8f93df25`,
  `v1.4.5-bugfix-services-git-identity-exclude` — "exclude shopping-cart-identity from the
  services-git ApplicationSet generator … remove dead kustomization"). It exists on NO current
  branch (main, v1.28.0, v1.29.0).
- **The code defaults already target openldap-0.** `KEYCLOAK_LDAP_HOST=openldap.identity.svc`,
  `KEYCLOAK_LDAP_BASE_DN=dc=home,dc=org`, `KEYCLOAK_LDAP_USERS_DN=ou=users,dc=home,dc=org`
  (`scripts/etc/keycloak/vars.sh:32-35`). The seed (Step 10d.5), the Vault mirror, and
  `bin/get-keycloak-password` all target openldap-0. Everything in code is self-consistent on
  openldap-0.
- **Live proof of orphan status:** the `shopping-cart-identity` Application is `OutOfSync`
  (Healthy) — its git source was removed, so ArgoCD has live resources with no matching source.
  It is excluded from the appset generator, so it will NOT regenerate once pruned.

**Direction confirmed by the human user's account:** `chengkai.liang` exists ONLY in openldap-0
(cluster-up-seeded + Vault-mirrored), NOT in osixia `ldap` (which has only the #72 declarative
admin/developer/operator). For a real person to log in to shopping-cart SSO as `chengkai.liang`,
Keycloak MUST federate openldap-0. So openldap-0 is the correct end-state.

### CORRECTION (2026-09-04, deeper trace) — the drift is coherent + multi-layer, NOT one stale component

Live investigation on the hub found the **entire live SSO stack coherently points at osixia**, not
just the Keycloak realm component. This is bigger than the original spec assumed:

| Layer | Live value | Managed by |
|-------|-----------|------------|
| Keycloak `shopping-cart` realm LDAP component (DB) | `ldap://ldap.identity.svc:389`, `dc=shopping-cart,dc=local`, `cn=admin` | Keycloak DB (id `4ae1e29a…`) |
| Keycloak Deployment pod env (`LDAP_CONNECTION_URL`/`LDAP_BIND_DN`/`LDAP_USERS_DN`) | osixia values | keycloak **Deployment manifest** (git/ArgoCD) |
| `LDAP_BIND_CREDENTIAL` | Vault `secret/ldap/admin` → `admin_password` (the **osixia** admin pw) | **ESO** `keycloak-secrets` (15m refresh) |
| osixia `ldap` Deployment + `shopping-cart-identity` App | present, App `OutOfSync` | orphaned (git source removed #74) |

The only things already on openldap-0: the code **defaults** (`vars.sh`/`keycloak.sh`), the
cluster-up seed (Step 10d.5), Vault `secret/ldap/openldap-admin`, and — notably — the component's
**group-mapper** (`groups.dn=ou=groups,dc=home,dc=org`). So the mapper and the connection already
disagree inside the same component.

**Consequence for remediation — do NOT hand-patch live.** Because `keycloak-secrets` is ESO-managed
(reverts in ≤15m) and the pod env comes from the keycloak Deployment manifest (ArgoCD reconciles),
imperative `kcadm`/`kubectl`/`vault` edits would be reverted. This must be a **git-first** change:

1. **Keycloak Deployment manifest** — repoint `LDAP_CONNECTION_URL`/`LDAP_BIND_DN`/`LDAP_USERS_DN`
   to openldap-0 (`ldap://openldap.identity.svc:389`, `cn=ldap-admin,dc=home,dc=org`,
   `ou=users,dc=home,dc=org`). (Confirm which services/ path or plugin templates it.)
2. **ESO source** — point `LDAP_BIND_CREDENTIAL`'s `remoteRef` at Vault `secret/ldap/openldap-admin`
   (the openldap-0 admin pw), OR reseed `secret/ldap/admin` to the openldap-0 value. Decide one
   canonical Vault path for the LDAP bind credential.
3. **Realm component (DB)** — re-import / update component `4ae1e29a…` connection fields to
   openldap-0 (its group-mapper is already correct), then full-sync. Keycloak does not reconcile its
   DB from env on a running pod, so this needs an explicit step (realm re-provision or kcadm update).
4. **Prune orphan** — delete `shopping-cart-identity` App + osixia `ldap` Deployment/Service (per
   [[reference_appset_generated_app_cleanup_ordering]] — App first).
5. **Drift guard** — `make status` / cluster-up assertion that the live realm `connectionUrl`
   matches `KEYCLOAK_LDAP_HOST`.

**Status: NOT executed.** Investigation stopped before mutating live SSO once the blast radius was
found to span a git-managed Deployment manifest + ESO/Vault + Keycloak DB + an ArgoCD app. Next
action is a staged remediation spec (git changes, not imperative surgery), then execute.

Rejected options (retained for the record):

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
