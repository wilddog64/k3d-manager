# Identity Troubleshooting

When Keycloak, LDAP, or Vault look stale during `make up`, these helpers give you a repeatable way to inspect the live pods without typing raw `kubectl exec` snippets.

## Vault

Run a shell or command inside the live Vault pod:

```bash
bin/vault-exec
bin/vault-exec -- vault status
bin/vault-exec -- vault kv list secret/
```

`bin/vault-exec -- vault ...` auto-authenticates with the live `vault-root`
token from the `vault-root` secret before running the command, so `vault kv`
inspection works without a manual login step.

## LDAP

Search the live LDAP directory through the running pod:

```bash
bin/ldap-search --filter '(mail=admin@shopping-cart.local)' mail uid cn sn givenName
bin/ldap-search --base-dn 'ou=users,dc=shopping-cart,dc=local' --filter '(uid=admin)'
```

## Logs

Tail the identity pod logs directly:

```bash
bin/keycloak-logs
bin/keycloak-logs --follow
bin/ldap-logs
```

## Notes

- These helpers use the shared `_run_command` wrapper for `kubectl` access, so they keep the repo's sudo and error-handling behavior consistent.
- `bin/ldap-search` reads the LDAP bind password from the live `openldap-admin` secret by default.
