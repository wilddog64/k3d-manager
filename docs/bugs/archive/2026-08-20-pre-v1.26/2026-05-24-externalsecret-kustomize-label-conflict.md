# Bug: externalsecret.yaml labels conflict with kustomize-managed labels

**Date:** 2026-05-24
**File:** `shopping-cart-product-catalog/k8s/base/externalsecret.yaml`
**Branch:** `docs/next-improvements` (shopping-cart-product-catalog)
**Copilot finding:** PR #28, comment ID 3295039818 on line 13

---

## Problem

`k8s/base/kustomization.yaml` applies these labels to all resources via `includeSelectors: true`:
- `app.kubernetes.io/name: product-catalog`
- `app.kubernetes.io/part-of: shopping-cart`

`k8s/base/externalsecret.yaml` sets conflicting values for those same keys:
- `app.kubernetes.io/name: external-secret`  ← kustomize overwrites to `product-catalog`
- `app.kubernetes.io/part-of: shopping-cart` ← duplicate (kustomize sets this anyway)

The `app.kubernetes.io/name: external-secret` value is misleading — it will never appear
on the live resource; kustomize silently replaces it on every build.

---

## Fix

### Change 1 — `k8s/base/externalsecret.yaml`: remove kustomize-controlled labels

**Exact old labels block (lines 9–13):**

```yaml
  labels:
    app.kubernetes.io/name: external-secret
    app.kubernetes.io/instance: product-catalog-secrets
    app.kubernetes.io/component: credentials
    app.kubernetes.io/part-of: shopping-cart
```

**Exact new labels block:**

```yaml
  labels:
    app.kubernetes.io/instance: product-catalog-secrets
    app.kubernetes.io/component: credentials
```

---

## Files Changed

| File | Change |
|------|--------|
| `k8s/base/externalsecret.yaml` | Remove `app.kubernetes.io/name` and `app.kubernetes.io/part-of` from labels — kustomize controls both |

---

## Rules

- `kubectl kustomize k8s/base/` must produce zero warnings after change
- No other files touched

---

## Definition of Done

- [ ] `k8s/base/externalsecret.yaml` updated — labels block has only `instance` and `component`
- [ ] `kubectl kustomize k8s/base/` produces no warnings
- [ ] Committed with message: `fix(k8s): remove kustomize-controlled labels from externalsecret.yaml`
- [ ] Pushed to `origin docs/next-improvements`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(k8s): remove kustomize-controlled labels from externalsecret.yaml
```

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `k8s/base/externalsecret.yaml`
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT remove `app.kubernetes.io/instance` or `app.kubernetes.io/component`
