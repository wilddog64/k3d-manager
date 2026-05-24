# Bug: secret.yaml placeholder causes perpetual ESO-ArgoCD OutOfSync loop

**Date:** 2026-05-24
**File:** `shopping-cart-product-catalog/k8s/base/kustomization.yaml`
**Branch:** `docs/next-improvements` (shopping-cart-product-catalog)

---

## Problem

`shopping-cart-product-catalog` ArgoCD app is permanently `OutOfSync` on
`product-catalog-secrets`:

```
Secret  shopping-cart-apps  product-catalog-secrets  OutOfSync  secret/product-catalog-secrets configured
```

**Root cause:** `k8s/base/secret.yaml` is a placeholder Secret with `CHANGE_ME` values.
ArgoCD applies it on every sync. ESO's ExternalSecret immediately detects the change and
re-syncs real credentials from Vault. On the next ArgoCD sync, git (CHANGE_ME) differs
from live (real values) → OutOfSync → ArgoCD applies CHANGE_ME again → infinite loop.

**Why removing it is safe:** The `product-catalog-secrets` Secret is fully managed by an
ESO ExternalSecret (`ClusterSecretStore: vault-backend`, `refreshInterval: 24h`,
status: `SecretSynced`). The placeholder `secret.yaml` serves no purpose in production
and actively corrupts ESO's work on every ArgoCD sync.

---

## Fix

### Change 1 — `k8s/base/kustomization.yaml`: remove `secret.yaml` from resources

**Exact old resources block:**

```yaml
resources:
- serviceaccount.yaml
- secret.yaml
- deployment.yaml
- service.yaml
- seed-job-configmap.yaml
- seed-job.yaml
- fts-index-job.yaml
```

**Exact new resources block:**

```yaml
resources:
- serviceaccount.yaml
- deployment.yaml
- service.yaml
- seed-job-configmap.yaml
- seed-job.yaml
- fts-index-job.yaml
```

---

## Files Changed

| File | Change |
|------|--------|
| `k8s/base/kustomization.yaml` | Remove `- secret.yaml` from resources list |

---

## Rules

- `kubectl kustomize k8s/base/` must produce zero warnings after change
- No other files touched
- Do NOT delete `secret.yaml` from disk — only remove it from the resources list

---

## Definition of Done

- [ ] `k8s/base/kustomization.yaml` updated — `- secret.yaml` line removed from resources
- [ ] `kubectl kustomize k8s/base/` produces no warnings
- [ ] Committed with message: `fix(kustomize): remove placeholder secret.yaml — ESO manages product-catalog-secrets`
- [ ] Pushed to `origin docs/next-improvements`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(kustomize): remove placeholder secret.yaml — ESO manages product-catalog-secrets
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT delete `k8s/base/secret.yaml` from disk
- Do NOT modify any file other than `k8s/base/kustomization.yaml`
- Do NOT commit to `main` — work on `docs/next-improvements`
