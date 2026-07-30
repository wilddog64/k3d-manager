# Keycloak frontend credentials: Vault and LDAP password drift

## What was tested

`bin/get-keycloak-password` was used to obtain the three documented shopping-cart
user passwords without recording their values. Each value was tested both against
Keycloak's `k3dm-smoke` direct-grant client and directly against the LDAP directory.

```text
admin       401 invalid_grant Invalid user credentials
developer   401 invalid_grant Invalid user credentials
operator    401 invalid_grant Invalid user credentials

admin       rejected
developer   rejected
operator    rejected
```

The users are not disabled or incomplete. The live Keycloak realm reports all three
as enabled, LDAP-federated users with no required actions.

## Root cause

The retrieval command reads `secret/keycloak/users/<user>` from Vault, but those
values were created at `2026-07-20T22:57:04Z`. LDAP records for all three users have
the same later modification time, `2026-07-25T11:51:46Z`, and reject the Vault values.
Therefore the LDAP passwords were changed as a group after the Vault values were
written, without updating the corresponding Vault entries.

This is not a frontend OIDC-client problem: `frontend` correctly disables direct
access grants because it is an authorization-code SPA. The direct LDAP bind proves
the values presented by `bin/get-keycloak-password` are stale before Keycloak is
involved.

`bin/cluster-up` Step 10d.5 makes this drift easy to preserve: it writes a checkpoint
even if an `ldappasswd` update only emits a warning, and later runs skip the step.
It also does not currently verify that each Vault value authenticates after seeding.

## Recommended follow-up

1. Choose a single source of truth, preferably the Vault values, then atomically reset
   the three LDAP user passwords from that source.
2. Make Step 10d.5 fail without writing its checkpoint if any LDAP update fails.
3. Add a post-seed, credentialed LDAP bind check for every user so Vault/LDAP drift is
   detected before reporting the credentials to an operator.
4. Re-test the frontend authorization-code login after the LDAP reset.

No credentials are included in this record.
