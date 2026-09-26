# Vector store credentials

ArgoCD bootstrap seeds the Vault KV v2 path `secret/vectordb/postgres` with the `username` and
`password` fields needed by the vectordb Postgres component. The seed is idempotent: if the entry
already exists, bootstrap does not rotate it. Rotation would publish a credential that an already
initialised Postgres data directory does not accept.

The `vectordb-postgres` ExternalSecret reads the path through the `vault-backend`
ClusterSecretStore. ESO publishes the fields to the pod as `POSTGRES_USER` and
`POSTGRES_PASSWORD`. The ESO read is granted by `LDAP_VAULT_POLICY_PREFIX` in
`scripts/etc/ldap/vars.sh`; that grant is applied to a running hub by `deploy_ldap`, so editing
`vars.sh` alone changes nothing live.

After a hub rebuild, bootstrap reseeds the credential when the path is absent. No manual Vault
write is required.

## Still to be written (WS6)

- What is deployed and where
- The index as a rebuildable cache
- Re-indexing cost
- Health verification
- Why a vector store at this scale
