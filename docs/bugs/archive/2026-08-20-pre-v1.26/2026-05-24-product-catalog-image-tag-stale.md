# Bug: product-catalog kustomization image tag stale — running PR #22 code, missing init_db fix

**Date:** 2026-05-24
**File:** `shopping-cart-product-catalog/k8s/base/kustomization.yaml`
**Branch:** `docs/next-improvements` (shopping-cart-product-catalog)

---

## Problem

`k8s/base/kustomization.yaml` has `newTag: sha-28955c89245d82111f2e0801723b49fe32cee730`
which is the image built from PR #22. CI builds and pushes a new image on every merge to
main but does NOT auto-commit the updated tag back to the repo.

As a result the Deployment is running the PR #22 image, which does not contain:
- `fix(db): create products_search_vector in init_db at startup` (PR #26)

Without `products_search_vector` in the database, the `product-catalog-fts-index` PostSync
job fails with:
```
ERROR: function products_search_vector(character varying, text, character varying) does not exist
```
and hits `BackoffLimitExceeded`, blocking every ArgoCD sync.

The latest image was built by CI from the PR #29 merge commit
`6ca5e88d587d845217a51cb0b79b906d26f7b7ee` and is available at:
`ghcr.io/wilddog64/shopping-cart-product-catalog:sha-6ca5e88d587d845217a51cb0b79b906d26f7b7ee`

---

## Fix

### Change 1 — `k8s/base/kustomization.yaml`: update image tag to PR #29 SHA

**Exact old block (lines 36–39):**

```yaml
images:
  - name: shopping-cart-product-catalog
    newName: ghcr.io/wilddog64/shopping-cart-product-catalog
    newTag: sha-28955c89245d82111f2e0801723b49fe32cee730
```

**Exact new block:**

```yaml
images:
  - name: shopping-cart-product-catalog
    newName: ghcr.io/wilddog64/shopping-cart-product-catalog
    newTag: sha-6ca5e88d587d845217a51cb0b79b906d26f7b7ee
```

---

## Files Changed

| File | Change |
|------|--------|
| `k8s/base/kustomization.yaml` | Update `newTag` from `sha-28955c8...` to `sha-6ca5e88d...` |

---

## Rules

- `kubectl kustomize k8s/base/` must produce zero warnings after change
- No other files touched

---

## Definition of Done

- [ ] `k8s/base/kustomization.yaml` updated — `newTag` is `sha-6ca5e88d587d845217a51cb0b79b906d26f7b7ee`
- [ ] `kubectl kustomize k8s/base/` produces no warnings
- [ ] Committed with message: `fix(k8s): bump product-catalog image tag to sha-6ca5e88d — deploy init_db fix`
- [ ] Pushed to `origin docs/next-improvements`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(k8s): bump product-catalog image tag to sha-6ca5e88d — deploy init_db fix
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `k8s/base/kustomization.yaml`
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT change `newName` — only `newTag`
