# Bug: ArgoCD SharedResourceWarning — Duplicate Namespace/shopping-cart-apps

**Date:** 2026-04-26
**Severity:** Medium — causes `shopping-cart-product-catalog` to stay OutOfSync
**Status:** Open
**Assignee:** Codex

---

## Symptom

`shopping-cart-product-catalog` shows `OutOfSync` in ArgoCD with a `SharedResourceWarning`:

```
SharedResourceWarning: Resource Namespace/shopping-cart-apps is already
managed by application shopping-cart-order
```

`shopping-cart-order` syncs cleanly; all other shopping-cart apps are unaffected.

---

## Root Cause

Both `shopping-cart-order` and `shopping-cart-product-catalog` include a `namespace.yaml`
in their `k8s/base/` directory, both creating `Namespace/shopping-cart-apps`:

**shopping-cart-order/k8s/base/namespace.yaml:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: shopping-cart-apps
  labels:
    app.kubernetes.io/part-of: shopping-cart
    istio-injection: enabled
```

**shopping-cart-product-catalog/k8s/base/namespace.yaml:**
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: shopping-cart-apps
  labels:
    app.kubernetes.io/part-of: shopping-cart
    app.kubernetes.io/managed-by: kustomize
```

ArgoCD tracks resource ownership per Application. When two Applications both render the
same `Namespace` resource (same apiVersion/kind/name, cluster-scoped), the second one to
sync raises `SharedResourceWarning` and refuses to manage that resource.

Additionally, the two namespace definitions have divergent labels (`istio-injection: enabled`
in order vs `app.kubernetes.io/managed-by: kustomize` in product-catalog), meaning one will
always overwrite what the other set on every sync cycle.

---

## Why Other Apps Are Unaffected

`shopping-cart-basket`, `shopping-cart-frontend`, and `shopping-cart-payment` do not have
a `namespace.yaml` in their `k8s/base/`. They rely on ArgoCD's `CreateNamespace=true`
syncOption (configured in the ApplicationSet) to create the namespace on first deploy.

---

## Fix

### Preferred approach: dedicated namespace Application

Remove `namespace.yaml` from both repos and introduce a dedicated `services/shopping-cart-namespace/`
Application in k3d-manager that owns the namespace with the correct merged labels.

**Step 1 — remove namespace.yaml from shopping-cart-order:**

File: `k8s/base/kustomization.yaml`
```yaml
# Remove this line from resources:
- namespace.yaml
```
Delete `k8s/base/namespace.yaml`.

**Step 2 — remove namespace.yaml from shopping-cart-product-catalog:**

File: `k8s/base/kustomization.yaml`
```yaml
# Remove this line from resources:
- namespace.yaml
```
Delete `k8s/base/namespace.yaml`.

**Step 3 — create dedicated namespace Application in k3d-manager:**

New file: `services/shopping-cart-namespace/namespace.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: shopping-cart-apps
  labels:
    app.kubernetes.io/part-of: shopping-cart
    app.kubernetes.io/managed-by: argocd
    istio-injection: enabled
```

New file: `services/shopping-cart-namespace/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
```

The existing `services-git` ApplicationSet generator (`services/*`) will automatically
discover `services/shopping-cart-namespace/` and create an Application for it.

---

## Repos Requiring PRs

| Repo | Change |
|------|--------|
| `shopping-cart-order` | Remove `namespace.yaml` + remove from kustomization.yaml resources |
| `shopping-cart-product-catalog` | Remove `namespace.yaml` + remove from kustomization.yaml resources |
| `k3d-manager` | Add `services/shopping-cart-namespace/` with namespace.yaml + kustomization.yaml |

**Branch (all work repos):** `fix/argocd-shared-namespace`

---

## Definition of Done

- [ ] `namespace.yaml` removed from `shopping-cart-order/k8s/base/`
- [ ] `namespace.yaml` removed from `shopping-cart-product-catalog/k8s/base/`
- [ ] `kustomization.yaml` resources list updated in both repos (no reference to namespace.yaml)
- [ ] `services/shopping-cart-namespace/` added to k3d-manager with namespace.yaml + kustomization.yaml
- [ ] ArgoCD shows `shopping-cart-product-catalog` as Synced (no SharedResourceWarning)
- [ ] ArgoCD shows a new `shopping-cart-namespace` Application managing the Namespace
- [ ] Commit message (all repos): `fix(argocd): remove duplicate Namespace/shopping-cart-apps to resolve SharedResourceWarning`

---

## What NOT to Do

- Do NOT delete the Namespace from the cluster — only remove it from kustomization resources
- Do NOT use `CreateNamespace=true` as the sole namespace owner — the `istio-injection: enabled` label must be set explicitly; ArgoCD's CreateNamespace creates the namespace without labels
- Do NOT create a PR until all three repos have commits pushed
- Do NOT commit to `main` — use `fix/argocd-shared-namespace` branch in each repo
- Do NOT skip pre-commit hooks (`--no-verify`)
