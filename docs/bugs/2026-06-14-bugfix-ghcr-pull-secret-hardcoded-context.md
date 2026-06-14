# Bugfix: v1.7.1 — `ghcr-pull-secret` provisioned on hardcoded `ubuntu-k3s`, not the active provider

**Branch:** `k3d-manager-v1.7.1`
**Files:** `scripts/plugins/shopping_cart.sh`

---

## Problem

After the ACG→Hostinger migration (ApplicationSets retargeted to `ubuntu-hostinger`), shopping-cart
pods on Hostinger are in `ImagePullBackOff`. `shopping_cart_create_ghcr_pull_secret`
(`scripts/plugins/shopping_cart.sh:320`) creates the `ghcr-pull-secret` and patches the default
ServiceAccount, but every `kubectl` call has **`--context ubuntu-k3s` hardcoded** — so the secret
lands on the decommissioned ACG cluster, never on `ubuntu-hostinger`. The pods on the active
provider have no pull secret and cannot pull from ghcr.io.

**Root cause:** the function predates provider-aware context resolution. The migrated code
(`bin/cluster-status`) already resolves the active context via `_acg_resolve_provider` +
`_acg_provider_context` (`scripts/lib/provider.sh:110,92`); this function never adopted it.

> Distinct from `docs/bugs/2026-04-26-shopping-cart-imagepullbackoff-no-ghcr-pull-secret.md`
> (secret never created / deployments missing `imagePullSecrets` — both already fixed). This bug is
> the **wrong target context**.

---

## Reproduction

```bash
# After deploy_argocd_bootstrap retargets apps to ubuntu-hostinger:
kubectl get pods -n shopping-cart-apps --context ubuntu-hostinger
#   -> ImagePullBackOff
kubectl get secret ghcr-pull-secret -n shopping-cart-apps --context ubuntu-hostinger
#   -> NotFound  (the secret was created on ubuntu-k3s instead)
```

---

## Fix

### Change 1 — `scripts/plugins/shopping_cart.sh`: resolve the active context, drop hardcoded `ubuntu-k3s`

**Exact old block (lines 320–358):**

```bash
function shopping_cart_create_ghcr_pull_secret() {
  local ns
  for ns in shopping-cart-apps shopping-cart-payment shopping-cart-data; do
    kubectl create namespace "$ns" --context ubuntu-k3s \
      --dry-run=client -o yaml \
      | kubectl apply --context ubuntu-k3s -f - >/dev/null
    case "$ns" in
      shopping-cart-data)
        kubectl label namespace "$ns" --context ubuntu-k3s \
          app.kubernetes.io/component=data \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
      shopping-cart-apps)
        kubectl label namespace "$ns" --context ubuntu-k3s \
          app.kubernetes.io/component=application \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
      shopping-cart-payment)
        kubectl label namespace "$ns" --context ubuntu-k3s \
          app.kubernetes.io/component=payment \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
    esac
    kubectl create secret docker-registry ghcr-pull-secret \
      --docker-server=ghcr.io \
      --docker-username="${_github_user}" \
      --docker-password="${_ghcr_pat}" \
      --context ubuntu-k3s \
      -n "$ns" \
      --dry-run=client -o yaml \
      | kubectl apply --context ubuntu-k3s -f -
    _info "[acg-up] ghcr-pull-secret applied in namespace: ${ns}"
  done
  for ns in shopping-cart-apps shopping-cart-payment shopping-cart-data; do
    kubectl patch serviceaccount default -n "$ns" \
      --context ubuntu-k3s \
      -p '{"imagePullSecrets": [{"name": "ghcr-pull-secret"}]}'
  done
}
```

**Exact new block:**

```bash
function shopping_cart_create_ghcr_pull_secret() {
  local ns _ctx
  _ctx="${APP_CONTEXT:-$(_acg_provider_context "$(_acg_resolve_provider)")}"
  for ns in shopping-cart-apps shopping-cart-payment shopping-cart-data; do
    kubectl create namespace "$ns" --context "${_ctx}" \
      --dry-run=client -o yaml \
      | kubectl apply --context "${_ctx}" -f - >/dev/null
    case "$ns" in
      shopping-cart-data)
        kubectl label namespace "$ns" --context "${_ctx}" \
          app.kubernetes.io/component=data \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
      shopping-cart-apps)
        kubectl label namespace "$ns" --context "${_ctx}" \
          app.kubernetes.io/component=application \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
      shopping-cart-payment)
        kubectl label namespace "$ns" --context "${_ctx}" \
          app.kubernetes.io/component=payment \
          app.kubernetes.io/part-of=shopping-cart \
          --overwrite >/dev/null ;;
    esac
    kubectl create secret docker-registry ghcr-pull-secret \
      --docker-server=ghcr.io \
      --docker-username="${_github_user}" \
      --docker-password="${_ghcr_pat}" \
      --context "${_ctx}" \
      -n "$ns" \
      --dry-run=client -o yaml \
      | kubectl apply --context "${_ctx}" -f -
    _info "[acg-up] ghcr-pull-secret applied in namespace: ${ns} (context ${_ctx})"
  done
  for ns in shopping-cart-apps shopping-cart-payment shopping-cart-data; do
    kubectl patch serviceaccount default -n "$ns" \
      --context "${_ctx}" \
      -p '{"imagePullSecrets": [{"name": "ghcr-pull-secret"}]}'
  done
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/shopping_cart.sh` | `shopping_cart_create_ghcr_pull_secret` resolves `APP_CONTEXT`/active provider context instead of hardcoded `ubuntu-k3s` |

---

## Rules

- `shellcheck -S warning scripts/plugins/shopping_cart.sh` — zero new warnings
- `bash -n scripts/plugins/shopping_cart.sh` — clean
- `./scripts/k3d-manager _agent_audit` — passes
- Only this one function changed; the other `ubuntu-k3s` references in the file are out of scope (tracked separately)

---

## Definition of Done

- [ ] `shopping_cart_create_ghcr_pull_secret` targets `${APP_CONTEXT:-$(_acg_provider_context "$(_acg_resolve_provider)")}`
- [ ] No `--context ubuntu-k3s` remains in this function
- [ ] `shellcheck` + `bash -n` + `_agent_audit` clean
- [ ] Committed and pushed to `k3d-manager-v1.7.1`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(shopping-cart): provision ghcr-pull-secret on the active provider context, not ubuntu-k3s
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/plugins/shopping_cart.sh`
- Do NOT touch the other 50+ `ubuntu-k3s` references in this file — separate bug
- Do NOT commit to `main` — work on `k3d-manager-v1.7.1`

---

## Operator follow-on (NOT part of this commit)

- Resolve a GHCR PAT (env `GHCR_PAT`, Vault, or `gh auth token`) and run the provisioning against
  Hostinger so the secret lands on `ubuntu-hostinger`; then the `shopping-cart-apps` pods leave
  `ImagePullBackOff`.
