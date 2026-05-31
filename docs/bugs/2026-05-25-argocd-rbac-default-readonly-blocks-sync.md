# Bugfix: ArgoCD RBAC default role blocks sync for authenticated users

**Branch:** `k3d-manager-v1.4.9` (spec only — code changes in shopping-cart-infra)
**Files:** `argocd/config/argocd-rbac-cm.yaml`

---

## Before You Start

**Branch (work repo):** `docs/next-improvements` in `shopping-cart-infra`

```bash
# Step 1 — get the spec (k3d-manager repo)
git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.9

# Step 2 — read this spec in full before touching anything

# Step 3 — check out the branch in the work repo
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-infra \
  checkout docs/next-improvements

# Step 4 — read the target file before editing
# argocd/config/argocd-rbac-cm.yaml
```

---

## Problem

Clicking **SYNC** in the ArgoCD UI returns:

```
Unable to sync: permission denied: applications, sync, platform/shopping-cart-payment,
sub: 35062490-298c-4a2c-b418-65034a7fd938
```

**Root cause:** `argocd-rbac-cm` sets `policy.default: role:readonly`. Any authenticated
user not in a mapped Keycloak group (`argocd-admins`, `argocd-developers`, etc.) gets
read-only access. The `shopping-cart-payment` app lives in the `platform` AppProject
(managed from k3d-manager), which is not covered by any group grant in the RBAC configmap.
The result: the owner cannot sync their own cluster from the UI.

This is a single-owner dev cluster. Any authenticated user should be able to sync.

---

## Fix

Change `policy.default` from `role:readonly` to `role:argocd-developer`.

The `role:argocd-developer` role already exists in the policy and grants:
- `applications, get, */*, allow`
- `applications, sync, */*, allow`
- `applications, action/*, */*, allow`
- `logs, get, */*, allow`

This is appropriate for a single-owner dev cluster — authenticated users can sync but
cannot modify RBAC, cluster config, or projects.

**Exact old line:**

```yaml
  policy.default: role:readonly
```

**Exact new line:**

```yaml
  policy.default: role:argocd-developer
```

---

## Files Changed

| File | Change |
|------|--------|
| `argocd/config/argocd-rbac-cm.yaml` | Change `policy.default` from `role:readonly` to `role:argocd-developer` |

---

## Rules

- Only `argocd/config/argocd-rbac-cm.yaml` touched — no other files
- `kubectl apply --dry-run=client -f argocd/config/argocd-rbac-cm.yaml` must succeed

---

## Definition of Done

- [ ] `policy.default: role:argocd-developer` in `argocd-rbac-cm.yaml`
- [ ] `kubectl apply --dry-run=client -f argocd/config/argocd-rbac-cm.yaml` passes
- [ ] Committed and pushed to `docs/next-improvements` on `origin`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(argocd): set default RBAC role to argocd-developer — allow authenticated users to sync
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `argocd/config/argocd-rbac-cm.yaml`
- Do NOT commit to `main` — work on `docs/next-improvements`
- Do NOT change any of the group-to-role mappings — only the `policy.default` line
