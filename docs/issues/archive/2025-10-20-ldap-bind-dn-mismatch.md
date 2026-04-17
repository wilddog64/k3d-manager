# LDAP Admin Bind DN mismatch after Vault sync

## Summary
`deploy_ldap` succeeded in reseeding Vault and restarting the chart, but the post-deploy smoke test continued to fail with `ldap_bind: Invalid credentials (49)`. We were still binding to the default DN (`cn=ldap-admin,dc=home,dc=org`), while the chart created/rotated the admin entry under a different DN.

## Root Cause
The bootstrap script always assumed the admin entry lived under `cn=ldap-admin,<baseDN>`. After we rotated the password inside the pod, the real account remained at its Bitnami-generated DN (e.g. `uid=ldap-admin,ou=users,...`). Vault stored the correct password, but every subsequent bind used the wrong DN so authentication failed.

## Fix
1. `_ldap_sync_admin_password` now discovers the actual admin entry inside the pod, updates it, verifies the credentials with `ldapwhoami`, and exports the discovered DN via `LDAP_BINDDN`.
2. The smoke helper in `scripts/tests/plugins/openldap.sh` prefers the exported DN (or the value replicated into the `openldap-admin` secret). If it is unavailable, it queries the directory for both `cn=<user>` and `uid=<user>` before falling back to the original default.

With both changes, `deploy_ldap` completes successfully, the stored password is verified, and the smoke test proves the admin credentials work end-to-end.
