# Issue: Argo CD browser TLS role write returns 403 permission denied without a Vault login

## Summary
During `make up`, the browser TLS bootstrap for the canonical Argo CD host failed while writing the Vault PKI role:

```text
Error writing data to pki/roles/argocd-browser-tls: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/pki/roles/argocd-browser-tls
Code: 403. Errors:

* permission denied
command terminated with exit code 2
ERROR: failed to execute kubectl -n secrets exec -i vault-0 -c vault -- sh -lc vault\ write\ pki/roles/argocd-browser-tls\ allowed_domains=shopping-cart.local\ allow_subdomains=true\ enforce_hostnames=true\ max_ttl=720h: 2ERROR: [vault] failed to create/update role argocd-browser-tls at pki
```

## Root Cause
The browser TLS helper was attempting to upsert the PKI role before authenticating to Vault with the root token path that this repo already uses elsewhere. Without that login step, the in-pod `vault write` ran with insufficient privileges and Vault rejected the role write with `403 permission denied`.

## Fix
- [`scripts/plugins/argocd.sh`](/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/plugins/argocd.sh) now calls `_vault_login "$ns" "$release"` before upserting the browser TLS PKI role.
- [`scripts/tests/plugins/argocd.bats`](/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/tests/plugins/argocd.bats) now stubs `_vault_login` and verifies the browser TLS helper logs in before writing the role.

## Verification
- `shellcheck -S warning scripts/plugins/argocd.sh`
- `bats scripts/tests/plugins/argocd.bats`
- `_agent_audit`
