# Bug: Hostinger deploy/refresh never provisions `ghcr-pull-secret` → shopping-cart ImagePullBackOff

**Date:** 2026-06-26
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`
**Affects:** `k3d-manager` (`scripts/lib/providers/k3s-hostinger.sh`)
**Files (code):** `scripts/lib/providers/k3s-hostinger.sh`

> Follow-up to `docs/bugs/2026-06-14-bugfix-ghcr-pull-secret-hardcoded-context.md`.
> That bugfix made `shopping_cart_create_ghcr_pull_secret` provider-aware (resolves
> `${APP_CONTEXT:-$(_acg_provider_context "$(_acg_resolve_provider)")}` instead of hardcoded
> `ubuntu-k3s`) and explicitly left "run the provisioning against Hostinger" as an **operator
> follow-on that was never executed**. This spec makes that step automatic for Hostinger so it
> stops being a manual, forgettable action.

---

## Problem

On `ubuntu-hostinger`, the `shopping-cart-apps` pods sit in `ErrImagePull` / `ImagePullBackOff`
against `ghcr.io/wilddog64/shopping-cart-*:latest` (`401 Unauthorized`, anonymous pull of private
packages). Root: the `ghcr-pull-secret` docker-registry secret **does not exist** in the Hostinger
app namespaces.

`ghcr-pull-secret` is created imperatively by `shopping_cart_create_ghcr_pull_secret`
(`scripts/plugins/shopping_cart.sh:331`) — wrapped by `shopping_cart_provision_ghcr_pull_secret`
(`:372`, which resolves the PAT first via env → Vault → `gh auth token`). Its only automatic caller
is **`acg-up` Step 5/12** (`shopping_cart.sh:619`) — the ACG bring-up path. The Hostinger provider's
deploy/refresh flow (`_hostinger_reconcile_vault_cluster_store`, `k3s-hostinger.sh:651`, called from
`:801`) sets up the Vault bridge + ESO ClusterSecretStore but **never provisions the pull secret**.
So on Hostinger the secret is never created.

**Why frontend specifically stays broken even once the secret exists elsewhere:** `order-service`,
`basket-service`, `product-catalog` reference `ghcr-pull-secret` via their **named** ServiceAccounts
(patched in `services/shopping-cart-*/kustomization.yaml`), so they self-heal the moment the secret
exists. `frontend` runs under the **`default`** ServiceAccount with no `imagePullSecrets`.
`shopping_cart_create_ghcr_pull_secret` patches the `default` SA's `imagePullSecrets` in each
namespace — so provisioning on the Hostinger context fixes frontend too.

**Root cause:** the Hostinger deploy/refresh flow has no step that provisions `ghcr-pull-secret`
on the Hostinger context.

---

## Reproduction

```bash
kubectl --context ubuntu-hostinger -n shopping-cart-apps get secret ghcr-pull-secret
#   -> Error from server (NotFound)
kubectl --context ubuntu-hostinger -n shopping-cart-apps get pods
#   -> frontend / order-service / basket-service / product-catalog: ImagePullBackOff
```

---

## Fix

### Change 1 — `scripts/lib/providers/k3s-hostinger.sh`: provision `ghcr-pull-secret` in the Hostinger reconcile flow

Add one best-effort provisioning step at the end of `_hostinger_reconcile_vault_cluster_store`,
forcing `APP_CONTEXT` to the Hostinger context so the secret lands on `ubuntu-hostinger` (not the
ACG-resolved default). `scripts/plugins/shopping_cart.sh` is already sourced at the top of this file
(`:8`), so `shopping_cart_provision_ghcr_pull_secret` is in scope.

Best-effort (`|| _warn`, not `|| return 1`): a missing/invalid GHCR PAT is an operator-config issue
and must not abort an otherwise-healthy platform refresh — but it must be loud.

**Exact old block (`_hostinger_reconcile_vault_cluster_store`, the tail through its closing brace):**

```bash
  _info "[k3s-hostinger] Ensuring vault-token + ClusterSecretStore on ${_HOSTINGER_KUBE_CONTEXT}..."
  shopping_cart_apply_vault_token_and_cluster_secret_store || return 1
  _info "[k3s-hostinger] Forcing ExternalSecret reconcile on ${_HOSTINGER_KUBE_CONTEXT}..."
  shopping_cart_force_vault_secret_reconcile "${_HOSTINGER_KUBE_CONTEXT}" >/dev/null || return 1
}
```

**Exact new block:**

```bash
  _info "[k3s-hostinger] Ensuring vault-token + ClusterSecretStore on ${_HOSTINGER_KUBE_CONTEXT}..."
  shopping_cart_apply_vault_token_and_cluster_secret_store || return 1
  _info "[k3s-hostinger] Forcing ExternalSecret reconcile on ${_HOSTINGER_KUBE_CONTEXT}..."
  shopping_cart_force_vault_secret_reconcile "${_HOSTINGER_KUBE_CONTEXT}" >/dev/null || return 1
  _info "[k3s-hostinger] Ensuring ghcr-pull-secret on ${_HOSTINGER_KUBE_CONTEXT}..."
  if ! APP_CONTEXT="${_HOSTINGER_KUBE_CONTEXT}" shopping_cart_provision_ghcr_pull_secret; then
    _warn "[k3s-hostinger] ghcr-pull-secret not provisioned on ${_HOSTINGER_KUBE_CONTEXT} (no valid GHCR PAT?) — shopping-cart pods may stay in ImagePullBackOff; set GHCR_PAT or store a PAT in Vault and re-run"
  fi
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-hostinger.sh` | `_hostinger_reconcile_vault_cluster_store` provisions `ghcr-pull-secret` on the Hostinger context (best-effort, with warning) |

---

## Rules

- `shellcheck -S warning scripts/lib/providers/k3s-hostinger.sh` — zero new warnings
- `bash -n scripts/lib/providers/k3s-hostinger.sh` — clean
- `./scripts/k3d-manager _agent_audit` — exit 0
- Only `_hostinger_reconcile_vault_cluster_store` changes; no other function or file touched
- Do NOT hardcode a kube-context string — use `${_HOSTINGER_KUBE_CONTEXT}`
- Do NOT echo or log the resolved GHCR PAT (the existing resolver already handles secret hygiene)

---

## Definition of Done

- [ ] `_hostinger_reconcile_vault_cluster_store` calls `shopping_cart_provision_ghcr_pull_secret`
      with `APP_CONTEXT="${_HOSTINGER_KUBE_CONTEXT}"`, best-effort with a `_warn` on failure.
- [ ] No `|| return 1` on the provisioning call (missing PAT must not abort the refresh).
- [ ] `shellcheck` + `bash -n` + `_agent_audit` clean.
- [ ] Committed + pushed to `feat/v1.8.0-acg-absorb-phase2-agy`; memory-bank updated with SHA.

**Commit message (exact):**
```
fix(hostinger): provision ghcr-pull-secret during app-cluster reconcile
```

---

## What NOT to Do

- Do NOT introduce an ExternalSecret / GitOps mechanism for `ghcr-pull-secret` — it is created
  imperatively by `shopping_cart_provision_ghcr_pull_secret`; do not build a parallel path.
- Do NOT change `scripts/plugins/shopping_cart.sh` or any `services/shopping-cart-*` overlay.
- Do NOT make the provisioning fatal (`|| return 1`).
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify files outside `scripts/lib/providers/k3s-hostinger.sh`.
- Do NOT commit to `main` — work on `feat/v1.8.0-acg-absorb-phase2-agy`.

---

## Operator note (NOT part of this commit)

This change provisions the secret only when `_hostinger_reconcile_vault_cluster_store` next runs
(a Hostinger deploy/refresh). To green the **currently** broken cluster immediately, run the
provisioning by hand against the Hostinger context with a valid GHCR PAT:

```bash
APP_CONTEXT=ubuntu-hostinger GHCR_PAT=<read:packages PAT> \
  ./scripts/k3d-manager shopping_cart_provision_ghcr_pull_secret
```
(omit `GHCR_PAT` to fall back to the Vault / `gh auth token` resolution chain).
