# Bug: LDAP password seed checkpoint hides Vault credential drift

## Symptom

The passwords returned by `bin/get-keycloak-password` could not log in to the frontend.
All three were rejected by LDAP, even though their Keycloak accounts were enabled and
LDAP-federated. Vault entries dated from July 20 while every LDAP user was modified on
July 25.

## Root cause

`bin/cluster-up` Step 10d.5 warned when `ldappasswd` failed but still wrote its
`step-10d5-ldap-passwords` checkpoint. Later runs skipped the repair, leaving Vault as
the advertised source of credentials while LDAP held a different password. The step
also had no post-write authentication check.

## Fix

Step 10d.5 now verifies each updated password with an LDAP bind. Any update or bind
failure exits non-zero without writing the checkpoint, so the next run retries instead
of declaring the seed complete. A missing LDAP pod is likewise fatal rather than
checkpointed as skipped.

## Live remediation

Reset the three LDAP passwords from the existing Vault values, then verify their binds.
This source change deliberately does not mutate the currently running directory.
