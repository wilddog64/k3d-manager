# Issue: Keycloak admin client update preserves stale PKCE client attributes

## What was observed

The live `argocd` client in Keycloak still had the PKCE client attribute after the realm JSON was updated to remove it:

```text
bd6e4eb4-7f95-4d6b-b774-0bc77008d3cf|argocd|pkce.code.challenge.method|S256
bd6e4eb4-7f95-4d6b-b774-0bc77008d3cf|argocd|post.logout.redirect.uris|+
```

I then tried the admin REST `PUT` path using the updated client representation. Keycloak accepted the update:

```text
PUT=204
```

but the PKCE attribute was still present afterwards:

```text
{
  "post.logout.redirect.uris": "+",
  "pkce.code.challenge.method": "S256"
}
```

Deleting the row directly from Postgres removed it immediately:

```text
DELETE 1
argocd|post.logout.redirect.uris|+
```

## Root cause

Keycloak’s client update path is preserving existing client attributes instead of removing `pkce.code.challenge.method` when the realm JSON stops specifying it. That leaves the live `argocd` client enforcing PKCE even after the source config has been corrected.

## Fix

- [`scripts/plugins/keycloak.sh`](/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/plugins/keycloak.sh) now removes the stale `pkce.code.challenge.method` row from the live Keycloak database during realm reconciliation.
- [`bin/acg-up`](/Users/cliang/src/gitrepo/personal/k3d-manager/bin/acg-up) now calls that cleanup after reconciling the `argocd` client.

## Follow-up

- Keep the `argocd` client PKCE attribute removed from the source realm JSON in `shopping-cart-infra`.
- Re-run `make up` and verify that the live client no longer contains `pkce.code.challenge.method`.
