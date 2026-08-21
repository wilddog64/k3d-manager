# Spec: shopping-cart-infra data-layer sync fix — CHANGELOG update

**Repo:** shopping-cart-infra
**Branch:** docs/next-improvements
**Status:** fix committed at `8c5de2d`; CHANGELOG entry missing

## Context

Two commits are already on `docs/next-improvements` but neither has a CHANGELOG entry:

- `ad32b5f` — `docs(bugs): StatefulSet volumeClaimTemplates immutable field causes data-layer sync failure`
- `8c5de2d` — `fix(argocd): ignore volumeClaimTemplates storageClassName diff to unblock data-layer sync`

The fix adds `ignoreDifferences` for `storageClassName` and `volumeMode` in StatefulSet
`volumeClaimTemplates` to `argocd/applications/data-layer.yaml`. This stops ArgoCD from
trying to patch an immutable field and allows the data-layer Application to sync cleanly.

## Before You Start

```bash
git pull origin docs/next-improvements  # in shopping-cart-infra
```

Read this spec in full before touching anything.

Branch: `docs/next-improvements` (shopping-cart-infra)

## Task

Add a CHANGELOG entry in `CHANGELOG.md` under `## [Unreleased] → ### Fixed`.

**Exact entry to add** (insert after the existing `storageClassName` line under `### Fixed`):

```
- `argocd/applications/data-layer.yaml`: add `ignoreDifferences` for StatefulSet `volumeClaimTemplates.storageClassName` and `volumeClaimTemplates.volumeMode` — prevents ArgoCD from patching immutable fields on existing StatefulSets, unblocking the data-layer Application sync loop
```

## Target File

`CHANGELOG.md` — add one line under `## [Unreleased] → ### Fixed`.

### Before (relevant section)

```
### Fixed
- Pin `storageClassName: local-path` in all StatefulSet volumeClaimTemplates (postgresql/orders, postgresql/products, postgresql/payment, redis/cart, redis/orders-cache, minio) to prevent ArgoCD data-layer OutOfSync on every cluster rebuild
```

### After

```
### Fixed
- Pin `storageClassName: local-path` in all StatefulSet volumeClaimTemplates (postgresql/orders, postgresql/products, postgresql/payment, redis/cart, redis/orders-cache, minio) to prevent ArgoCD data-layer OutOfSync on every cluster rebuild
- `argocd/applications/data-layer.yaml`: add `ignoreDifferences` for StatefulSet `volumeClaimTemplates.storageClassName` and `volumeClaimTemplates.volumeMode` — prevents ArgoCD from patching immutable fields on existing StatefulSets, unblocking the data-layer Application sync loop
```

## Definition of Done

- [ ] `CHANGELOG.md` updated with the exact entry above
- [ ] Committed on `docs/next-improvements` with message:
  `docs(changelog): add ignoreDifferences data-layer sync fix entry`
- [ ] Pushed: `git push origin docs/next-improvements` — do NOT report done until push succeeds
- [ ] Report back: commit SHA

## What NOT To Do

- Do NOT modify `argocd/applications/data-layer.yaml` — the fix is already committed
- Do NOT create a PR
- Do NOT commit to `main`
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `CHANGELOG.md`
- Do NOT update k3d-manager memory-bank
