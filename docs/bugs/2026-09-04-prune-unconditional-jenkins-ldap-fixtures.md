# Cleanup: prune unconditional Jenkins fixtures from the LDAP bootstrap seed

## Context

Jenkins is a deprecated demo feature — disabled by default, never deployed (CLAUDE.md; decision
2026-08-10 keeps the code marked DEPRECATED). Yet the OpenLDAP bootstrap seed hardcodes Jenkins
directory entries **unconditionally**, so every fresh `openldap-0` (`dc=home,dc=org`) directory
carries a `jenkins-admin` service account + `jenkins-admins` group even when Jenkins is never
enabled. Surfaced 2026-09-04 while auditing the identity directory during the v1.28.0 two-cloud work.

This is inconsistent with the LDIF **generator** in `scripts/plugins/ldap.sh:469-493`, which already
gates the identical `jenkins-admins` group + `jenkins-admin` user behind `enable_jenkins == 1`. The
static bootstrap seed should follow the same "Jenkins only when enabled" rule.

## Scope (what to remove)

1. **Delete `scripts/etc/ldap/jenkins-users-groups.ldif` entirely.** It is a dead file — nothing
   loads it (`LDAP_LDIF_FILE` defaults to `bootstrap-basic-schema.ldif`, `scripts/etc/ldap/vars.sh:73`;
   no other reference exists), and its `cn=admin`/`cn=developer`/`cn=tester` users (with malformed
   `{SSHA}admin123`-style values) are absent from the live directory. All-Jenkins content.

2. **`scripts/etc/ldap/bootstrap-basic-schema.ldif`** (the live seed) — remove the unconditional
   Jenkins entries:
   - the `cn=jenkins-admin,ou=users,dc=home,dc=org` user block (was "User 2: jenkins-admin (Service Account)")
   - the `cn=jenkins-admins,ou=groups,dc=home,dc=org` group block
   - the dangling `member: cn=jenkins-admin,ou=users,dc=home,dc=org` line inside the `it-devops` group
     (keep `it-devops` itself — it still has `cn=chengkai.liang`)
   - update the two header comments that say the file exists "for testing Jenkins authentication"

3. **`bin/test-directory-auto-load`** (the consumer that asserts the removed fixtures) — drop
   `jenkins-admin` from the **user** verification loop and `jenkins-admins` from the **group**
   verification loop, plus the summary lines, so it stays consistent with the pruned seed.

4. **Rotation-list defaults that target the removed `jenkins-admin`** — drop it from the default
   user list in `scripts/etc/ldap/vars.sh:102` (`LDAP_USERS_TO_ROTATE`),
   `scripts/etc/ldap/ldap-password-rotator.sh:20`, and
   `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl:28` (`USERS_TO_ROTATE`), so the rotator does
   not target a user that fresh directories no longer seed. (Overridable env var — only the default
   changes.)

## Out of scope (deliberately kept — deprecated-but-gated Jenkins feature code)

Per the 2026-08-10 keep-deprecated decision, do NOT touch:
- `scripts/plugins/ldap.sh:469-493` — already gated on `enable_jenkins`; correct as-is.
- `scripts/etc/ldap/vars.sh:36-47` the `LDAP_JENKINS_*` config block (defaults used only when Jenkins is enabled).
- `scripts/etc/ldap/bootstrap-ad-schema.ldif` — a **separate** AD-testing directory
  (`dc=corp,dc=example,dc=com`) with its own `Jenkins Service` fixtures; exercises the AD plugin
  path, not the `dc=home,dc=org` directory this cleanup targets. Prune separately if desired.
- `scripts/lib/dirservices/openldap.sh:194` Jenkins RBAC mapping.
- `scripts/etc/jenkins/values-*.yaml.tmpl`, `bin/smoke-test-jenkins`, `scripts/etc/ad/vars.sh:46`.

## Live impact

None immediate. These LDIFs seed a directory **only on a fresh bootstrap**; the running `openldap-0`
keeps its current entries until re-bootstrapped. `openldap-0` (`dc=home,dc=org`) is NOT the
shopping-cart SSO directory (Keycloak federates the osixia `ldap` at `dc=shopping-cart,dc=local` —
see `docs/issues/2026-09-04-keycloak-federates-osixia-ldap-not-seeded-openldap.md`), so SSO is
unaffected either way. This is a source-cleanup so future fresh directories are Jenkins-free.

## Definition of Done

- [x] `jenkins-users-groups.ldif` deleted.
- [x] `bootstrap-basic-schema.ldif` has no `jenkins-admin` user, no `jenkins-admins` group, no
      dangling `jenkins-admin` member; `it-devops` retained with `chengkai.liang`; headers updated.
- [x] No `jenkins` refs remain in `bootstrap-basic-schema.ldif`. (The `dc=home,dc=org` tidy surface —
      seed + test + rotation defaults — is jenkins-admin-free; `vars.sh` `LDAP_JENKINS_*` config and
      `bootstrap-ad-schema.ldif` are deliberately kept, see Out of scope.)
- [x] `bin/test-directory-auto-load` no longer references `jenkins-admin`/`jenkins-admins` (user +
      group loops + summary); `shellcheck` clean.
- [x] Rotation defaults (`vars.sh`, `ldap-password-rotator.sh`, `.yaml.tmpl`) no longer list
      `jenkins-admin`; `shellcheck` clean.
- [x] LDIF sanity: every remaining group block in `bootstrap-basic-schema.ldif` has ≥1 `member:`
      (`it-devops`→1, `developers`→1).

## What NOT to do

- Do NOT remove or ungate the `ldap.sh` Jenkins generator or any other kept Jenkins feature code.
- Do NOT delete the `it-devops` or `developers` groups — they are not Jenkins-specific.
- Do NOT edit the live directory (`kubectl`/`ldapmodify`); this is a seed-source cleanup only.
