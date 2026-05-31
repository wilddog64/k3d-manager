# Bugfix: remove redundant payment-db-credentials-eso ExternalSecret

**Branch:** `k3d-manager-v1.4.9`
**Files:**
- `services/shopping-cart-payment/kustomization.yaml`
- `services/shopping-cart-payment/postgres-payment-apps-externalsecret.yaml` (delete)

---

## Before You Start

```bash
# Step 1 — get the spec
git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.9

# Step 2 — read this spec in full before touching anything

# Step 3 — read the target files before editing
# services/shopping-cart-payment/kustomization.yaml
# services/shopping-cart-payment/postgres-payment-apps-externalsecret.yaml
```

---

## Problem

`payment-db-credentials-eso` ExternalSecret in namespace `shopping-cart-payment` reports:

```
unable to mutate secret payment-db-credentials: secret is owned by another ExternalSecret: postgres-payment-app
```

**Root cause:** Two ExternalSecrets target the same Kubernetes Secret `payment-db-credentials`:

1. `postgres-payment-app` (from shopping-cart-infra `data-layer/secrets/postgres-payment-externalsecret.yaml`) —
   `creationPolicy: Owner`, syncs `username`, `password`, `DB_USERNAME`, `DB_PASSWORD`,
   `RABBITMQ_USERNAME`, `RABBITMQ_PASSWORD`, `connection-string`, `database`, `host`, `port`

2. `payment-db-credentials-eso` (from k3d-manager `services/shopping-cart-payment/postgres-payment-apps-externalsecret.yaml`) —
   `creationPolicy: Merge`, attempts to sync `username`, `password`

ESO v1 enforces single ownership. `postgres-payment-app` already provides every key that
`payment-db-credentials-eso` intended to add. The k3d-manager ESO is completely redundant.

---

## Fix

### Change 1 — `services/shopping-cart-payment/kustomization.yaml`: remove ESO resource

**Exact old content:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-payment//k8s/base?ref=main
  - postgres-payment-apps-externalsecret.yaml
patches:
  - patch: |-
      - op: add
        path: /spec/template/spec/imagePullSecrets
        value:
          - name: ghcr-pull-secret
    target:
      kind: Deployment
```

**Exact new content:**

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-payment//k8s/base?ref=main
patches:
  - patch: |-
      - op: add
        path: /spec/template/spec/imagePullSecrets
        value:
          - name: ghcr-pull-secret
    target:
      kind: Deployment
```

### Change 2 — delete `services/shopping-cart-payment/postgres-payment-apps-externalsecret.yaml`

```bash
git rm services/shopping-cart-payment/postgres-payment-apps-externalsecret.yaml
```

---

## Files Changed

| File | Change |
|------|--------|
| `services/shopping-cart-payment/kustomization.yaml` | Remove `postgres-payment-apps-externalsecret.yaml` from resources |
| `services/shopping-cart-payment/postgres-payment-apps-externalsecret.yaml` | Delete via `git rm` |

---

## Rules

- Only the two listed files touched — no other files
- `kubectl apply --dry-run=client -k services/shopping-cart-payment/` must succeed after the change

---

## Definition of Done

- [ ] `postgres-payment-apps-externalsecret.yaml` removed via `git rm`
- [ ] `kustomization.yaml` no longer references `postgres-payment-apps-externalsecret.yaml`
- [ ] `kubectl apply --dry-run=client -k services/shopping-cart-payment/` passes
- [ ] Committed and pushed to `k3d-manager-v1.4.9`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(payment): remove redundant payment-db-credentials-eso — postgres-payment-app already owns the secret
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.4.9`
- Do NOT edit the shopping-cart-infra ESO — `postgres-payment-app` is correct as-is
