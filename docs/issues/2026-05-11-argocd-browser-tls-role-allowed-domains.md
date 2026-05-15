# Argo CD browser TLS role creation fails with a full hostname

Status: FIXED

## What was attempted

During `make up`, the Argo CD browser TLS bootstrap failed while creating the Vault PKI role:

```text
ERROR: failed to execute kubectl -n secrets exec -i vault-0 -c vault -- sh -lc vault\ write\ pki/roles/argocd-browser-tls\ allowed_domains=argocd.shopping-cart.local\ allow_subdomains=true\ enforce_hostnames=true\ max_ttl=720h: 2ERROR: [vault] failed to create/update role argocd-browser-tls at pki
make: *** [up] Error 1
```

## Root cause

The browser TLS helper was writing the Vault role with the full host as `allowed_domains`:

```text
allowed_domains=argocd.shopping-cart.local
allow_subdomains=true
```

That shape is inconsistent with the other PKI helpers in this repo, which derive a parent domain for multi-label hosts before enabling `allow_subdomains`.

## Fixed by

- [`scripts/plugins/argocd.sh`](/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/plugins/argocd.sh) now derives `allowed_domains=shopping-cart.local` for `argocd.shopping-cart.local` and keeps `allow_subdomains=true` for the browser TLS PKI role.
- [`scripts/tests/plugins/argocd.bats`](/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/tests/plugins/argocd.bats) now asserts the derived parent-domain role shape.
