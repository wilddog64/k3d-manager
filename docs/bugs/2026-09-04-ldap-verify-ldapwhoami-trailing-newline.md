# Bug: LDAP password seed verify fails — `ldapwhoami -y` file carries a trailing newline

## Symptom

On a fresh-hub `make up`, Step 10d.5/14 (Seeding Keycloak LDAP user passwords in LDAP + Vault)
aborts the whole bring-up after the password *set* succeeds but the *verify* bind fails for every
user:

```
INFO: [acg-up] Step 10d.5/14 — Seeding Keycloak LDAP user passwords in LDAP + Vault...
WARN: [acg-up] LDAP password verification failed for user 'admin'
WARN: [acg-up] LDAP password verification failed for user 'developer'
WARN: [acg-up] LDAP password verification failed for user 'operator'
ERROR: [acg-up] LDAP password seed failed verification; checkpoint not written
make: *** [up] Error 1
```

Observed live 2026-09-04 on the v1.28.0 two-cloud validation, immediately after the argocd
platform-ops guard fix (`5f4526fd`) unblocked the app-cluster registration and identity stack.

## Root cause

`bin/cluster-up` seeds each LDAP user password in two operations against `openldap-0`
(`app.kubernetes.io/name=openldap-stack-ha`):

1. **set** — `ldappasswd -S`, fed `printf '%s\n%s\n'` (new + confirm). Correct: `-S` reads the
   new password from the prompt line, the newline is the line delimiter and is NOT stored.
2. **verify** — `ldapwhoami -y <file>`, where the file is written by piping
   `printf '%s\n' "${_ldap_user_pass}"` into `cat > "${_ldap_password_file}"` (bin/cluster-up:1045).

`ldapwhoami -y` uses the **complete contents** of the password file as the bind password and does
**not** strip a trailing newline. So verify binds with `<password>\n` while the entry stores
`<password>` → `ldap_bind: Invalid credentials (49)` → "verification failed" for every user, even
though the set succeeded.

Reproduced live against `openldap-0` (read-only, admin credential):

```
-y file with trailing newline (printf '%s\n')  → ldap_bind: Invalid credentials (49)
-y file without trailing newline (printf '%s')  → dn:cn=ldap-admin,dc=home,dc=org  (rc=0)
```

## Fix

`bin/cluster-up:1045` — drop the newline from the verify pipe so the `-y` file holds exactly the
password bytes:

```bash
# before
        if printf '%s\n' "${_ldap_user_pass}" | \
# after
        if printf '%s' "${_ldap_user_pass}" | \
```

The `ldappasswd -S` set step (lines 1037–1044) is unchanged — its two newlines are prompt
delimiters, not part of the stored password.

## Definition of Done

- [ ] `bin/cluster-up:1045` verify pipe uses `printf '%s'` (no trailing newline).
- [ ] `shellcheck bin/cluster-up` clean (no new warnings).
- [ ] `bats scripts/tests/bin/cluster_up.bats` green.
- [ ] Fresh-hub `make up` clears Step 10d.5/14 (all three users "password set and verified") and
      writes the `step-10d5-ldap-passwords` checkpoint (live-verified on the v1.28.0 two-cloud
      bring-up).

## What NOT to do

- Do NOT touch the `ldappasswd -S` set step's `printf '%s\n%s\n'` — those newlines are required
  prompt delimiters; removing them breaks the set.
- Do NOT switch verify to `-w "${_ldap_user_pass}"` — that would put the generated password on the
  argv/command line inside the pod (secret-hygiene violation); keep it in the `-y` file.
- Do NOT widen scope to the second observation below in this fix.

## Follow-up observation (separate, do NOT fix here)

Two LDAP instances coexist in the `identity` namespace on the hub:
`openldap-0` (Helm `openldap-stack-ha` StatefulSet — the seed target, holds all real user entries)
and a fresh `ldap` Deployment (`app.kubernetes.io/name=ldap`, `component=directory`). The seed and
verify both hit `openldap-0`, so this is immaterial to the newline bug, but it matters for Keycloak
LDAP federation (Step 10d.6): confirm the realm's federation provider binds to `openldap-0`, not the
stray `ldap` Deployment. File separately if federation points at the wrong instance.
