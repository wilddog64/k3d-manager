# Bug: product-catalog-secrets OutOfSync — ArgoCD tracking-id persists after secret.yaml removed

**Date:** 2026-05-24
**File:** `shopping-cart-product-catalog/k8s/base/externalsecret.yaml`
**Branch:** `docs/next-improvements` (shopping-cart-product-catalog)

---

## Problem

After `secret.yaml` was removed from kustomize resources (PR #27), the `product-catalog-secrets`
Secret retained the `argocd.argoproj.io/tracking-id` annotation from ArgoCD's last apply.
ArgoCD still tracks the Secret as a managed resource, but it no longer appears in the git
manifests — so ArgoCD flags it as OutOfSync indefinitely.

Additionally, ESO's `creationPolicy: Owner` means the Secret exists on the cluster and will
never match what ArgoCD expects (nothing in git), so the OutOfSync state is permanent.

**Immediate fix (already applied manually):**
The tracking annotation was removed directly:
```bash
kubectl annotate secret product-catalog-secrets -n shopping-cart-apps --context ubuntu-k3s \
  argocd.argoproj.io/tracking-id- kubectl.kubernetes.io/last-applied-configuration-
```

**Long-term fix needed:** The ExternalSecret must propagate
`argocd.argoproj.io/compare-options: IgnoreExtraneous` to the target Secret via the
`spec.target.template.metadata.annotations` block. This is self-healing — if ArgoCD ever
re-adds its tracking annotation, the compare-options annotation ensures ArgoCD ignores the
Secret on all future syncs.

---

## Fix

### Change 1 — `k8s/base/externalsecret.yaml`: add target template annotations

**Exact old block (lines 14–18):**

```yaml
  target:
    name: product-catalog-secrets
    creationPolicy: Owner
```

**Exact new block:**

```yaml
  target:
    name: product-catalog-secrets
    creationPolicy: Owner
    template:
      metadata:
        annotations:
          argocd.argoproj.io/compare-options: IgnoreExtraneous
```

---

## Files Changed

| File | Change |
|------|--------|
| `k8s/base/externalsecret.yaml` | Add `spec.target.template.metadata.annotations` with `IgnoreExtraneous` |

---

## Rules

- `kubectl kustomize k8s/base/` must produce zero warnings after change
- No other files touched

---

## Definition of Done

- [ ] `k8s/base/externalsecret.yaml` updated — target template annotations block added
- [ ] `kubectl kustomize k8s/base/` produces no warnings
- [ ] Committed with message: `fix(k8s): add IgnoreExtraneous annotation to ExternalSecret target — prevent ArgoCD OutOfSync`
- [ ] Pushed to `origin docs/next-improvements`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(k8s): add IgnoreExtraneous annotation to ExternalSecret target — prevent ArgoCD OutOfSync
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `k8s/base/externalsecret.yaml`
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT remove `creationPolicy: Owner`
