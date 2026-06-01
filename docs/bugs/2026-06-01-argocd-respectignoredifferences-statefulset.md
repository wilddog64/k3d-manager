# Spec: shopping-cart-infra — add RespectIgnoreDifferences to data-layer syncOptions

**Repo:** shopping-cart-infra
**Branch:** docs/next-improvements
**Status:** ignoreDifferences in place; RespectIgnoreDifferences missing

## Context

PR #80 added `ignoreDifferences` for `storageClassName` and `volumeMode` in
`argocd/applications/data-layer.yaml`. This stops ArgoCD from detecting a diff on those
fields, so the application shows `Synced`. However, `ignoreDifferences` only affects diff
detection — if a sync is triggered for ANY other reason (e.g., a template spec change),
ArgoCD will still include `storageClassName` in the applied manifest, and Kubernetes will
reject it because `volumeClaimTemplates` is immutable.

`RespectIgnoreDifferences=true` extends the fix: ArgoCD v3.x strips the ignored fields
from the sync payload as well. The combination of `ignoreDifferences` + `RespectIgnoreDifferences`
makes the fix permanent — ArgoCD will never attempt to patch those immutable fields.

## Before You Start

```bash
git pull origin docs/next-improvements  # in shopping-cart-infra
```

Read this spec in full before touching anything.

**Branch (work repo):** `docs/next-improvements` in shopping-cart-infra

## Task

Add `- RespectIgnoreDifferences=true` to `syncOptions` in `argocd/applications/data-layer.yaml`.

## Target File

`argocd/applications/data-layer.yaml`

### Before (relevant section)

```yaml
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
```

### After

```yaml
    syncOptions:
      - CreateNamespace=true
      - PrunePropagationPolicy=foreground
      - PruneLast=true
      - RespectIgnoreDifferences=true
```

## CHANGELOG Entry

Add one line under `## [Unreleased] → ### Fixed` in `CHANGELOG.md` (after the existing
ignoreDifferences entry):

```
- `argocd/applications/data-layer.yaml`: add `RespectIgnoreDifferences=true` to syncOptions — prevents ArgoCD from including ignored immutable fields (`volumeClaimTemplates.storageClassName`, `volumeClaimTemplates.volumeMode`) in sync payloads, making the StatefulSet immutable-field protection permanent
```

## Definition of Done

- [ ] `argocd/applications/data-layer.yaml` updated with `RespectIgnoreDifferences=true` in `syncOptions`
- [ ] `CHANGELOG.md` updated with the exact entry above
- [ ] Committed on `docs/next-improvements` with message:
  `fix(argocd): add RespectIgnoreDifferences to data-layer syncOptions`
- [ ] Pushed: `git push origin docs/next-improvements` — do NOT report done until push succeeds
- [ ] Report back: commit SHA

## What NOT To Do

- Do NOT modify any other file besides `argocd/applications/data-layer.yaml` and `CHANGELOG.md`
- Do NOT modify the `ignoreDifferences` block — it must stay in place
- Do NOT create a PR
- Do NOT commit to `main`
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT update k3d-manager memory-bank
