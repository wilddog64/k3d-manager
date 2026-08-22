# E2E substrate pins a product-catalog image tag that no longer exists in ghcr (404) (2026-08-22)

**Severity:** medium (blocks every E2E: product-catalog never rolls out).
**Component:** `scripts/etc/e2e/kustomization.yaml` (`images:` pins).
**Found while:** the v1.27.0 plan #2 live-acceptance passing run on M2, after the ghcr
`read:packages` auth fix. With auth working, basket and order pulled but
product-catalog stayed `ImagePullBackOff`.

## Symptom

```
Failed to pull image "ghcr.io/wilddog64/shopping-cart-product-catalog:sha-6ca5e88d587d845217a51cb0b79b906d26f7b7ee":
... 403 Forbidden        # before the read:packages fix
... manifests/sha-6ca5e88d... : 404   # after auth fixed — tag genuinely absent
```

## Root cause

`scripts/etc/e2e/kustomization.yaml` pinned:

| image | pinned tag | in registry? |
|-------|-----------|--------------|
| shopping-cart-product-catalog | `sha-6ca5e88d587d845217a51cb0b79b906d26f7b7ee` | **NO (404)** |
| shopping-cart-basket | `sha-f70d5801a4078434128d0a17b55cf2e93a028304` | yes |
| shopping-cart-order | `sha-56033880a16e77ad5df0752eac8ad1c00c4a258a` | yes |

The product-catalog SHA aged out of the ghcr package (retention/cleanup); the other two
pins are still present. The `tags/list` for the package shows the current head is
`sha-505f758a6ab83b72aa78073e6a368dd760a9e08b` — the merge SHA of product-catalog PR #49
(merged 2026-08-22).

## Fix

Bump the product-catalog pin to a tag that exists (current head):

```yaml
- name: shopping-cart-product-catalog
  newName: ghcr.io/wilddog64/shopping-cart-product-catalog
  newTag: sha-505f758a6ab83b72aa78073e6a368dd760a9e08b
```

Left basket/order untouched (their pins still resolve) — minimal patch.

## Follow-up

The pins are hand-maintained and silently rot when ghcr prunes old tags. Options: pin by
immutable digest (`@sha256:...`) with a documented refresh step, or have the E2E resolve
the current `main` image tag at run time instead of a frozen SHA. Until then, a stale pin
recurs whenever a package's retention window passes.
