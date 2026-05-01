# Bug: Bitnami OpenLDAP re-hashes SSHA userPassword from LDIF — password unusable at boot

**Date:** 2026-04-26
**Severity:** High — no LDAP user can log in after a clean bootstrap
**Spec type:** bug
**Branch:** `k3d-manager-v1.2.0`

---

## Problem

After a clean LDAP bootstrap, no user can authenticate. The LDIF provides pre-hashed
`{SSHA}` passwords but Bitnami OpenLDAP treats the `{SSHA}...` string as plaintext and
re-hashes it, producing an unknown hash. The result is that the stored password hash
never matches `test1234` or any known input.

**Observed:**
```
ldap_bind: Invalid credentials (49)
```

**Stored hash in LDAP** (base64-decoded from `userPassword` attribute):
```
{SSHA}Bc3IV5n2L7zCIx4mxtJ7Si2c6wv2MVaf   ← unknown plaintext
```

**Expected hash from LDIF** (`bootstrap-basic-schema.ldif` line 49):
```
{SSHA}Fvoa1XMaBL4y9QP0E6KcYYQUO901vjJg   ← SSHA of "test1234"
```

---

## Root Cause

Bitnami OpenLDAP (`openldap-bitnami`) enables password hashing at the slapd layer via
the `ppolicy` or `loglevel` overlay. When a `userPassword` value is provided in the LDIF
during import, slapd re-hashes it using the configured hash scheme before storing, even
when the value already has an `{SSHA}` prefix.

The LDIF import path (via `ldapadd`) bypasses the check that would detect a pre-encoded
hash, so every user ends up with a double-hashed password that cannot be reproduced.

This bug is compounded by the parent bug (`2026-04-26-ldap-users-hardcoded-test-password.md`)
which uses static passwords in the first place. The correct fix for both bugs combined is:
- Remove `userPassword` from LDIF entirely
- Generate unique passwords post-deploy via `ldappasswd` (which correctly handles hashing)
- Store each password in Vault

---

## Immediate Workaround (applied 2026-04-26)

Set `chengkai.liang` password manually:
```bash
ldappasswd -x -H ldap://localhost:1389 \
  -D "cn=ldap-admin,dc=home,dc=org" -w "<admin-pw>" \
  -s "ChangeMe123!" "cn=chengkai.liang,ou=users,dc=home,dc=org"
```

Current usable credential: `chengkai.liang` / `ChangeMe123!` (ephemeral — lost on rebuild).

---

## Permanent Fix

This bug is resolved as a side-effect of `docs/bugs/2026-04-26-ldap-users-hardcoded-test-password.md`:
- Remove `userPassword:` lines from `bootstrap-basic-schema.ldif`
- Add `_ldap_rotate_user_passwords` to `ldap.sh` — uses `ldappasswd` (correct path, no double-hash)
- Passwords stored in Vault `secret/ldap/users/<username>`

No separate fix is needed beyond what is already specced in the parent bug doc.

---

## What NOT to Do

- Do NOT set `userPassword` as a pre-hashed SSHA value in any LDIF — Bitnami re-hashes it
- Do NOT use `ldapadd`/`ldapmodify` with `userPassword:` to set passwords — use `ldappasswd`
