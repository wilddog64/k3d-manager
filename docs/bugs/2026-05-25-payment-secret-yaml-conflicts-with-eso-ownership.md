# Bugfix: shopping-cart-payment secret.yaml conflicts with ESO ownership — ArgoCD OutOfSync

**Branch (k3d-manager spec):** `k3d-manager-v1.4.10`
**Branch (work):** `fix/payment-remove-placeholder-secret` in `shopping-cart-payment`
**Files:** `k8s/base/kustomization.yaml`, `k8s/base/secret.yaml`

---

## Before You Start

```bash
# Step 1 — get the spec
git -C ~/src/gitrepo/personal/k3d-manager pull origin k3d-manager-v1.4.10

# Step 2 — read this spec in full before touching anything

# Step 3 — create the work branch in shopping-cart-payment
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-payment \
  checkout -b fix/payment-remove-placeholder-secret origin/main

# Step 4 — read both target files before editing:
# k8s/base/kustomization.yaml
# k8s/base/secret.yaml
```

---

## Problem

`shopping-cart-payment` and `shopping-cart-order` ArgoCD apps show **OutOfSync** on
`payment-db-credentials` and `payment-encryption-secret` Secrets.

ArgoCD diff shows the git version has placeholder values (`CHANGE_ME`) and stale labels
(`component: backend`, `name: payment-service`), while the live cluster has real Vault
values (via ESO) and correct labels (`component: database-credentials`,
`name: postgres-credentials`).

ArgoCD cannot reconcile the diff because ESO owns both secrets via
`creationPolicy: Owner` — ArgoCD's apply is rejected, leaving the app permanently OutOfSync.

**Root cause:** `k8s/base/secret.yaml` in `shopping-cart-payment` contains placeholder
`Secret` manifests for `payment-db-credentials` and `payment-encryption-secret`. These
secrets are fully managed by ESO ExternalSecrets in the `data-layer` ArgoCD app
(`postgres-payment-app` → `payment-db-credentials`, `payment-encryption-secret` →
`payment-encryption-secret`). The placeholder file was never removed after ESO
integration was set up.

---

## Reproduction

1. `argocd app get cicd/shopping-cart-payment` shows OutOfSync on
   `payment-db-credentials` and `payment-encryption-secret`.
2. `argocd app diff cicd/shopping-cart-payment` shows label and value drift caused by
   the placeholder secrets in git.
3. ArgoCD sync fails or leaves drift because ESO's `creationPolicy: Owner` blocks the
   apply.

---

## Fix

### Change 1 — `k8s/base/kustomization.yaml`: remove `secret.yaml` from resources

**Exact old block (lines 12–19):**

```yaml
resources:
- serviceaccount.yaml
- configmap.yaml
- secret.yaml
- deployment.yaml
- service.yaml
- networkpolicy.yaml
```

**Exact new block:**

```yaml
resources:
- serviceaccount.yaml
- configmap.yaml
- deployment.yaml
- service.yaml
- networkpolicy.yaml
```

### Change 2 — `k8s/base/secret.yaml`: delete the file entirely

The file contains only placeholder secrets that ESO now owns. Delete it:

```bash
git -C ~/src/gitrepo/personal/shopping-carts/shopping-cart-payment \
  rm k8s/base/secret.yaml
```

---

## Files Changed

| File | Change |
|------|--------|
| `k8s/base/kustomization.yaml` | Remove `- secret.yaml` from resources list |
| `k8s/base/secret.yaml` | Delete — ESO owns both secrets via ExternalSecret |

---

## Rules

- Code change limited to `k8s/base/kustomization.yaml` and `k8s/base/secret.yaml`
- No other files touched

---

## Definition of Done

- [ ] `- secret.yaml` removed from `k8s/base/kustomization.yaml` resources list
- [ ] `k8s/base/secret.yaml` deleted via `git rm`
- [ ] Copilot tagged on the PR: `gh api repos/wilddog64/shopping-cart-payment/pulls/<n>/requested_reviewers -X POST -f 'reviewers[]=copilot-pull-request-reviewer[bot]'`
- [ ] Committed and pushed to `fix/payment-remove-placeholder-secret` in `shopping-cart-payment`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(payment): remove placeholder secret.yaml — ESO owns payment-db-credentials and payment-encryption-secret
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `k8s/base/kustomization.yaml` and `k8s/base/secret.yaml`
- Do NOT commit to `main` — work on `fix/payment-remove-placeholder-secret` in `shopping-cart-payment`
- Do NOT run `npm install` or change any dependencies
