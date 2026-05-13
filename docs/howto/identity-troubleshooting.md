# Identity Troubleshooting

When Keycloak, LDAP, or Vault look stale during `make up`, these helpers give you a repeatable way to inspect the live pods without typing raw `kubectl exec` snippets.

## Vault

Run a shell or command inside the live Vault pod:

```bash
bin/vault-exec.sh
bin/vault-exec.sh -- vault status
bin/vault-exec.sh -- vault kv list secret/
```

## LDAP

Search the live LDAP directory through the running pod:

```bash
bin/ldap-search.sh --filter '(mail=admin@shopping-cart.local)' mail uid cn sn givenName
bin/ldap-search.sh --base-dn 'ou=users,dc=shopping-cart,dc=local' --filter '(uid=admin)'
```

## Logs

Tail the identity pod logs directly:

```bash
bin/keycloak-logs.sh
bin/keycloak-logs.sh --follow
bin/ldap-logs.sh
```

## Notes

- These helpers use the shared `_run_command` wrapper for `kubectl` access, so they keep the repo's sudo and error-handling behavior consistent.
- `bin/ldap-search.sh` reads the LDAP bind password from the live `openldap-admin` secret by default.
