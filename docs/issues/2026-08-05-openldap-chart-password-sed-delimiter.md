# OpenLDAP stack-ha init-schema rejects delimiter-bearing passwords

## What was attempted

Ran the user-authorized OpenLDAP migration using:

```text
./scripts/k3d-manager deploy_ldap --confirm
```

Helm successfully upgraded the `identity/openldap` release to
`jp-gouin/openldap-stack-ha` 4.3.3, but `openldap-0` did not become ready.

## Actual output

```text
pod/openldap-0   0/1   Init:Error
sed: -e expression #1, char 41: unknown option to `s'
sed: -e expression #1, char 54: unknown option to `s'
```

The chart's `init-schema` container substitutes both Vault-derived passwords
into LDIF files using an unescaped `sed s///` replacement. The existing
base64-formatted secret contains a delimiter character, so initialization exits
before the LDAP container starts.

## Resolution

`scripts/plugins/ldap.sh` now retains only delimiter-safe existing passwords
and generates 48-character hexadecimal values when a rotation is necessary.
The replacement is safe for the chart's unescaped `sed` substitution and does
not log a secret value. Regression coverage is in
`scripts/tests/plugins/ldap_chart_passwords.bats`.
