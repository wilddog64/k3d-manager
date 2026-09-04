# Remediation: unify shopping-cart SSO on openldap-0 (retire bundled osixia ldap) — Option B

**Date:** 2026-09-04
**Decision:** Option B (user-chosen 2026-09-04) — openldap-0 is the canonical directory for
shopping-cart SSO. Repoint the Keycloak `shopping-cart` realm federation to k3d-manager's openldap-0
(`openldap-stack-ha`) and retire the bundled osixia `ldap`.
**Source of truth for this decision + full architecture:**
`docs/issues/2026-09-04-keycloak-federates-osixia-ldap-not-seeded-openldap.md` (read CORRECTION 2).
**Target repo:** `github.com/wilddog64/shopping-cart-infra` (NOT k3d-manager). Cross-repo → this is a
spec for Codex on a feature branch; never a direct edit, never imperative kcadm/kubectl/vault surgery
(ESO + ArgoCD reconcile revert it — the fix must be in git).

## Why

Keycloak currently federates its own bundled osixia `ldap` (`dc=shopping-cart,dc=local`), which holds
only #72-era declarative users (admin/developer/operator). Real SSO users — notably `chengkai.liang` —
live in k3d-manager's **openldap-0** (`dc=home,dc=org`), seeded by cluster-up Step 10d.5 and mirrored to
Vault. So `bin/get-keycloak-password <user>` returns a password SSO can't use. Option B makes Keycloak
federate openldap-0 so the seeded/Vault users are the SSO users, and the existing k3d-manager seed +
`get-keycloak-password` become correct as-is.

## Before You Start

- Branch (shopping-cart-infra): `fix/sso-federate-openldap0` off `origin/main`. Never work on `main`.
- `git pull origin main` in `~/src/gitrepo/personal/shopping-carts/shopping-cart-infra` first.
- Read this spec in full and the issue doc's CORRECTION 2.
- Confirm openldap-0 is reachable from the identity ns as `openldap.identity.svc.cluster.local:389`
  and that its admin bind is `cn=ldap-admin,dc=home,dc=org` with the password in Vault
  `secret/data/ldap/openldap-admin` property `LDAP_ADMIN_PASSWORD`.

## Compatibility facts (verified 2026-09-04)

- openldap-0 user entries are `cn=<user>,ou=users,dc=home,dc=org`, objectClasses
  `inetOrgPerson`/`posixAccount`/`top`, and DO carry a `uid` attribute (`uid: chengkai.liang`).
  → `usernameLDAPAttribute: uid` works; `rdnLDAPAttribute` must be **cn** (RDN is cn=, not uid=).
- Groups live at `ou=groups,dc=home,dc=org` (objectClass `groupOfNames`, `member` DNs) — matches the
  live component's existing group-mapper (`groups.dn=ou=groups,dc=home,dc=org`).

## Phase 1 — Repoint federation to openldap-0 (SSO must work before Phase 2)

### File 1 — `identity/keycloak/kustomization.yaml` (configMapGenerator `keycloak-config` literals)

Old:
```yaml
  - LDAP_CONNECTION_URL=ldap://ldap.identity.svc.cluster.local:389
  - LDAP_USERS_DN=ou=users,dc=shopping-cart,dc=local
  - LDAP_BIND_DN=cn=admin,dc=shopping-cart,dc=local
```
New:
```yaml
  - LDAP_CONNECTION_URL=ldap://openldap.identity.svc.cluster.local:389
  - LDAP_USERS_DN=ou=users,dc=home,dc=org
  - LDAP_BIND_DN=cn=ldap-admin,dc=home,dc=org
```
Also change the RDN attribute literal:
Old: `  - LDAP_RDN_ATTRIBUTE=uid`
New: `  - LDAP_RDN_ATTRIBUTE=cn`
(Leave `LDAP_USERNAME_ATTRIBUTE=uid` and `LDAP_UUID_ATTRIBUTE=entryUUID` unchanged.)

### File 2 — `identity/keycloak/realm-shopping-cart.json` (LDAP UserStorageProvider `config`)

Change the three hardcoded values in the `org.keycloak.storage.UserStorageProvider` component:
- `connectionUrl`: `ldap://ldap.identity.svc.cluster.local:389` → `ldap://openldap.identity.svc.cluster.local:389`
- `usersDn`: `ou=users,dc=shopping-cart,dc=local` → `ou=users,dc=home,dc=org`
- `bindDn`: `cn=admin,dc=shopping-cart,dc=local` → `cn=ldap-admin,dc=home,dc=org`
- `rdnLDAPAttribute`: `uid` → `cn`
(Leave `bindCredential: ["${LDAP_BIND_CREDENTIAL}"]`, `usernameLDAPAttribute: uid`, and
`uuidLDAPAttribute: entryUUID` unchanged.)

### File 3 — `identity/keycloak/keycloak-secrets-externalsecret.yaml` (`LDAP_BIND_CREDENTIAL` remoteRef)

Old:
```yaml
    - secretKey: LDAP_BIND_CREDENTIAL
      remoteRef:
        key: secret/data/ldap/admin
        property: admin_password
```
New:
```yaml
    - secretKey: LDAP_BIND_CREDENTIAL
      remoteRef:
        key: secret/data/ldap/openldap-admin
        property: LDAP_ADMIN_PASSWORD
```

### Phase 1 verification (live, after ArgoCD sync + the keycloak-realm-reconcile hook runs)

1. `keycloak-secrets` Secret key `LDAP_BIND_CREDENTIAL` now equals the openldap-0 admin password.
2. Live realm component `connectionUrl` = `ldap://openldap.identity.svc.cluster.local:389`,
   `usersDn`/`bindDn` = `dc=home,dc=org` (via kcadm get components -r shopping-cart).
3. `bin/get-keycloak-password developer` (k3d-manager) → the returned password binds successfully to
   the federated directory: one `ldapwhoami` against `ldap://openldap.identity.svc:389` as the user.
4. A real frontend → Keycloak → shopping-cart SSO login succeeds for a seeded openldap-0 user
   (`chengkai.liang` or `developer`).

STOP after Phase 1 and confirm SSO works before Phase 2.

## Phase 2 — Retire the bundled osixia `ldap` (cleanup, only after Phase 1 verified)

- Remove `identity/ldap` from whatever now deploys the identity stack (the ArgoCD Application source;
  see the OutOfSync-source caveat below), and delete `identity/ldap/` (deployment.yaml,
  kustomization.yaml, bootstrap.yaml, ldap-secrets-externalsecret.yaml).
- The osixia `ldap` Deployment/Service/PVCs are then pruned by ArgoCD on sync (they are app-owned).
- Do NOT delete openldap-0 or the `openldap` Service — that is k3d-manager's directory, not osixia.

## What NOT to do

- Do NOT edit the live cluster imperatively (kcadm/kubectl/vault) — ESO (15m) + ArgoCD revert it. Git only.
- Do NOT delete the `shopping-cart-identity` ArgoCD Application — it owns the ENTIRE identity stack
  (keycloak + postgres + ldap + ExternalSecrets). Deleting it destroys live SSO.
- Do NOT delete openldap-0 / the k3d-manager `openldap` Service.
- Do NOT change the realm `bindCredential` to a literal — keep the `${LDAP_BIND_CREDENTIAL}` placeholder.
- Do NOT create a PR or merge (prepare-and-stop; the human decides).

## Definition of Done

- [ ] Branch `fix/sso-federate-openldap0` off `origin/main` in shopping-cart-infra.
- [ ] Files 1–3 changed exactly as above; `kustomize build identity/keycloak` renders with the new values.
- [ ] Phase 1 committed:
      `fix(identity): federate shopping-cart SSO against openldap-0 (dc=home,dc=org), retire osixia bind`
- [ ] Phase 1 verification 1–4 all pass on the live hub.
- [ ] Phase 2 (osixia retirement) committed separately AFTER Phase 1 verified:
      `chore(identity): retire bundled osixia ldap now that SSO federates openldap-0`
- [ ] Pushed to `origin/fix/sso-federate-openldap0`; no PR, no merge.
- [ ] memory-bank (k3d-manager) updated with status + SHAs.

## Caveat to resolve during execution — broken app source

The live `shopping-cart-identity` Application is `OutOfSync`: its k3d-manager source pointer
(`services/shopping-cart-identity/kustomization.yaml`, a remote-base reference to
`shopping-cart-infra//identity/{ldap,keycloak}?ref=main`) was removed in #74. Determine how the stack
is currently wired to ArgoCD on the hub and reconcile the source BEFORE relying on a sync to apply
these changes — otherwise a git change upstream will not reach the cluster (or a hard refresh could
disrupt the stack). See `docs/issues/2026-09-02-argocd-identity-drift-and-dashboard-502.md`.
