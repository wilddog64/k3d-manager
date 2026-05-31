# Bugfix: Remove Redis placeholder secrets — ESO owns them, ArgoCD drift is permanent

**Branch (shopping-cart-infra):** `fix/remove-redis-placeholder-secrets` (create from `main`)
**Repo:** `~/src/gitrepo/personal/shopping-carts/shopping-cart-infra/`
**Files:**
- `data-layer/redis/cart/secret.yaml` (delete)
- `data-layer/redis/orders-cache/secret.yaml` (delete)
- `CHANGELOG.md` (update `[Unreleased]`)

---

## Problem

`data-layer/redis/cart/secret.yaml` and `data-layer/redis/orders-cache/secret.yaml` are
placeholder Secrets with `password: "CHANGE_ME"`. They were committed as dev scaffolding with a
`# NOTE: In production, use ExternalSecret` comment.

ESO is already in production — the `redis-cart` and `redis-orders-cache` ExternalSecrets in
`data-layer/secrets/` own these same Secret names (`creationPolicy: Owner`). ESO overwrites:
- `/data` — fills `password`, `host`, `port`, `connection-string` from Vault
- `/metadata/labels` — ESO template labels differ from git labels
- `/metadata/annotations` — adds `reconcile.external-secrets.io/data-hash` and `created-by`

ArgoCD sees perpetual drift between the git placeholder (password: "CHANGE_ME", 1 data key,
git labels) and the live ESO-managed Secret (real Vault password, 4 data keys, ESO labels).
Auto-sync with `selfHeal: true` keeps trying to reset the Secret to the placeholder — this
fights ESO in a continuous loop and keeps `data-layer` Application OutOfSync indefinitely.

**Root cause:** Two owners for the same Secret — git (placeholder) and ESO (ExternalSecret).
The git placeholder is obsolete; ESO took ownership when the ExternalSecrets were added.

---

## Fix

Delete both placeholder files. ArgoCD will prune the Secrets on next sync. ESO's ExternalSecrets
will immediately recreate them from Vault. The recreated Secrets will NOT have
`argocd.argoproj.io/tracking-id`, so ArgoCD will no longer track or manage them. Drift stops.

The ExternalSecrets that replace these files are already in git and working:
- `data-layer/secrets/redis-cart-externalsecret.yaml` → creates `redis-cart-secret`
- `data-layer/secrets/redis-orders-cache-externalsecret.yaml` → creates `redis-orders-cache-secret`

### Change 1 — Delete `data-layer/redis/cart/secret.yaml`

**Action:** `git rm data-layer/redis/cart/secret.yaml`

**Exact file being deleted:**

```yaml
---
# Redis password secret for cart instance
# In production, store this in Vault and sync via ExternalSecret
apiVersion: v1
kind: Secret
metadata:
  name: redis-cart-secret
  namespace: shopping-cart-data
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/instance: cart
    app.kubernetes.io/component: cache
    app.kubernetes.io/part-of: shopping-cart
type: Opaque
stringData:
  password: "CHANGE_ME"
```

### Change 2 — Delete `data-layer/redis/orders-cache/secret.yaml`

**Action:** `git rm data-layer/redis/orders-cache/secret.yaml`

**Exact file being deleted:**

```yaml
---
# Redis password secret for orders-cache instance
# In production, store this in Vault and sync via ExternalSecret
apiVersion: v1
kind: Secret
metadata:
  name: redis-orders-cache-secret
  namespace: shopping-cart-data
  labels:
    app.kubernetes.io/name: redis
    app.kubernetes.io/instance: orders-cache
    app.kubernetes.io/component: cache
    app.kubernetes.io/part-of: shopping-cart
type: Opaque
stringData:
  password: "CHANGE_ME"
```

### Change 3 — Update `CHANGELOG.md`

Add under `## [Unreleased]` → `### Fixed`:

```
- Remove placeholder `redis-cart-secret` and `redis-orders-cache-secret` Secret manifests from
  `data-layer/redis/cart/` and `data-layer/redis/orders-cache/` — ESO ExternalSecrets in
  `data-layer/secrets/` own these secrets and overwrite the placeholder data with real Vault
  values, causing perpetual ArgoCD `data-layer` OutOfSync. Deleting the placeholders lets ESO
  fully own the secrets without conflict.
```

---

## Files Changed

| File | Change |
|------|--------|
| `data-layer/redis/cart/secret.yaml` | Deleted |
| `data-layer/redis/orders-cache/secret.yaml` | Deleted |
| `CHANGELOG.md` | Add Fixed entry under `[Unreleased]` |

---

## Rules

- No other files touched — do NOT modify the ExternalSecrets or the StatefulSets
- Do NOT add `ignoreDifferences` to any ArgoCD Application — deleting the files is the fix
- `git rm` both files (not just deleting from disk) so git tracks the deletion

---

## Definition of Done

- [ ] `data-layer/redis/cart/secret.yaml` deleted from git
- [ ] `data-layer/redis/orders-cache/secret.yaml` deleted from git
- [ ] `CHANGELOG.md` updated under `[Unreleased]` → `### Fixed`
- [ ] Committed and pushed to `fix/remove-redis-placeholder-secrets` on `shopping-cart-infra`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(data-layer): remove redis placeholder secrets — ESO owns them, ArgoCD drift permanent
```

---

## What NOT to Do

- Do NOT create a PR (Claude will handle that)
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the three listed targets
- Do NOT commit to `main` — work on `fix/remove-redis-placeholder-secrets`
- Do NOT delete the ExternalSecrets — they are the correct owners and must stay
- Do NOT touch any other redis files (statefulset.yaml, service.yaml)
