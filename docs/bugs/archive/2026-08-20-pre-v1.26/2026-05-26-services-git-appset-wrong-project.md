# Bugfix: v1.4.10 — services-git ApplicationSet assigns wrong ArgoCD project

**Branch:** `k3d-manager-v1.4.10`
**Files:** `scripts/etc/argocd/applicationsets/services-git.yaml`, `bin/acg-up`

---

## Problem

The `services-git` ApplicationSet (which creates all k3d-manager-managed shopping-cart
Application objects: `shopping-cart-basket`, `shopping-cart-frontend`, `shopping-cart-order`,
`shopping-cart-payment`, `shopping-cart-product-catalog`, `shopping-cart-namespace`) sets
`spec.project: platform` in its template.

Because ArgoCD continuously reconciles Applications back to their ApplicationSet template,
any manual patch to change `project` on individual apps is immediately reverted. This means
all shopping-cart service apps land in the `platform` project instead of `shopping-cart`,
blocking users with `platform-developer`/`platform-operator` roles scoped to
`shopping-cart/*` from syncing or viewing them.

The `shopping-cart-identity` Application in `bin/acg-up` (Keycloak + LDAP) also uses
`project: platform`. Identity is a platform-level service (shared SSO, LDAP) and stays in
`platform` — no change needed there.

**Root cause:** `scripts/etc/argocd/applicationsets/services-git.yaml` line 38 hardcodes
`project: platform` in the Application template.

---

## Reproduction

```
argocd app sync shopping-cart/data-layer
# → permission denied: applications, sync, platform/data-layer
```

Or: patch any shopping-cart-* app to `project: shopping-cart` and watch ArgoCD revert it
within seconds.

---

## Fix

### Change 1 — `scripts/etc/argocd/applicationsets/services-git.yaml`: change project

**Exact old block (line 38):**

```yaml
      project: platform
```

**Exact new block:**

```yaml
      project: shopping-cart
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/applicationsets/services-git.yaml` | `project: platform` → `project: shopping-cart` (line 38) |

---

## Rules

- `shellcheck` does not apply (YAML-only change)
- No other files touched
- Do NOT change `platform-helm.yaml` or `demo-rollout.yaml` — those are platform infra and belong in `platform`
- Do NOT change `bin/acg-up` line 758 (`shopping-cart-identity`) — identity stack stays in `platform`

---

## Definition of Done

- [ ] `scripts/etc/argocd/applicationsets/services-git.yaml` line 38 reads `project: shopping-cart`
- [ ] No other files modified
- [ ] Committed and pushed to `k3d-manager-v1.4.10`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(argocd): assign shopping-cart services to shopping-cart project in services-git ApplicationSet
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/etc/argocd/applicationsets/services-git.yaml`
- Do NOT change `platform-helm.yaml`, `demo-rollout.yaml`, or `bin/acg-up`
- Do NOT commit to `main` — work on `k3d-manager-v1.4.10`
