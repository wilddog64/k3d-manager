# Bug: shopping-cart pods ImagePullBackOff — ghcr-pull-secret never applied

**Date:** 2026-04-26
**Severity:** High — all 5 shopping-cart services fail to start on ubuntu-k3s
**Status:** Open
**Assignee:** Codex
**Branch:** `k3d-manager-v1.2.0`

---

## Symptom

All shopping-cart pods on ubuntu-k3s show `ImagePullBackOff`:

```
payment-service-<hash>   0/1   ImagePullBackOff   0   16m
```

ArgoCD reports the Application as degraded.

## Root Cause

Two compounding gaps:

**Gap 1 — `ghcr-pull-secret` never created.**
`acg-up` Step 5 creates the secret, but only if `GHCR_PAT` env var is set. When unset,
`_err` exits immediately. The user rotates their `gh` CLI PAT via `pat-rotate.sh`, which
updates `~/.config/gh/hosts.yml` on the Mac only — the cluster has no knowledge of it.
The Vault fallback path does not exist yet.

**Gap 2 — Deployments do not reference the pull secret.**
`services/shopping-cart-*/kustomization.yaml` in k3d-manager reference the upstream base
with no overlay. The upstream `Deployment` manifests have no `imagePullSecrets`. The
`shopping-cart-infra` Applications used to patch this in, but that deployment path is no
longer in use.

## Before You Start

1. Read `memory-bank/activeContext.md` and `memory-bank/progress.md`
2. `git pull origin k3d-manager-v1.2.0`
3. Read all target files listed below

**Branch:** `k3d-manager-v1.2.0` (all work in this repo only)

---

## Fix

### Part A — `bin/acg-up`: fall back to Vault for GHCR PAT

**File:** `bin/acg-up`

**Exact old block (lines ~194–198):**
```bash
_ghcr_pat="${GHCR_PAT:-}"
_github_user="${GITHUB_USERNAME:-wilddog64}"
if [[ -z "$_ghcr_pat" ]]; then
  _err "[acg-up] GHCR_PAT env var not set — set it to a GitHub PAT with read:packages scope and re-run"
fi
```

**Exact new block:**
```bash
_ghcr_pat="${GHCR_PAT:-}"
_github_user="${GITHUB_USERNAME:-wilddog64}"
if [[ -z "$_ghcr_pat" ]]; then
  _info "[acg-up] GHCR_PAT not in env — reading from Vault secret/github/ghcr-pull-token"
  _ghcr_pat=$(vault kv get -field=token secret/github/ghcr-pull-token 2>/dev/null || true)
  if [[ -z "$_ghcr_pat" ]]; then
    _err "[acg-up] GHCR_PAT not set and Vault secret/github/ghcr-pull-token not found. Seed it once: vault kv put secret/github/ghcr-pull-token token=<PAT-with-read:packages>"
  fi
fi
```

### Part B — `services/` kustomizations: add `imagePullSecrets` patch

Apply the same change to all 5 files. Each file currently contains only a `resources` block.
Add a `patches` block after `resources`.

**File: `services/shopping-cart-basket/kustomization.yaml`**

Old:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-basket//k8s/base?ref=main
```

New:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-basket//k8s/base?ref=main
patches:
  - patch: |-
      - op: add
        path: /spec/template/spec/imagePullSecrets
        value:
          - name: ghcr-pull-secret
    target:
      kind: Deployment
```

**File: `services/shopping-cart-frontend/kustomization.yaml`**

Old:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-frontend//k8s/base?ref=main
```

New:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-frontend//k8s/base?ref=main
patches:
  - patch: |-
      - op: add
        path: /spec/template/spec/imagePullSecrets
        value:
          - name: ghcr-pull-secret
    target:
      kind: Deployment
```

**File: `services/shopping-cart-order/kustomization.yaml`**

Old:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-order//k8s/base?ref=main
```

New:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-order//k8s/base?ref=main
patches:
  - patch: |-
      - op: add
        path: /spec/template/spec/imagePullSecrets
        value:
          - name: ghcr-pull-secret
    target:
      kind: Deployment
```

**File: `services/shopping-cart-payment/kustomization.yaml`**

Old:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-payment//k8s/base?ref=main
```

New:
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

**File: `services/shopping-cart-product-catalog/kustomization.yaml`**

Old:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-product-catalog//k8s/base?ref=main
```

New:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/wilddog64/shopping-cart-product-catalog//k8s/base?ref=main
patches:
  - patch: |-
      - op: add
        path: /spec/template/spec/imagePullSecrets
        value:
          - name: ghcr-pull-secret
    target:
      kind: Deployment
```

---

## One-Time Manual Setup (run once before next `make up`)

Store a GitHub PAT with `read:packages` scope in Vault:
```bash
vault kv put secret/github/ghcr-pull-token token=<your-PAT>
```

The PAT needs only `read:packages` — a fine-grained PAT scoped to
`wilddog64/shopping-cart-*` packages is sufficient. It is separate from the
`gh` CLI PAT (which needs broader scopes).

---

## Definition of Done

- [ ] `bin/acg-up` Step 5 reads `GHCR_PAT` from Vault `secret/github/ghcr-pull-token` when env var is not set
- [ ] All 5 `services/shopping-cart-*/kustomization.yaml` files have the `imagePullSecrets` patch block
- [ ] `shellcheck` passes with zero new warnings on `bin/acg-up`
- [ ] Commit message: `fix(acg-up): read GHCR_PAT from Vault and patch imagePullSecrets into services kustomizations`
- [ ] `git push origin k3d-manager-v1.2.0` — do NOT report done until push succeeds
- [ ] Update `memory-bank/activeContext.md` and `memory-bank/progress.md` with commit SHA and task status

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.2.0`
- Do NOT modify `bin/pat-rotate.sh` — the gh CLI PAT and the GHCR pull token are separate concerns
- Do NOT add `GHCR_PAT` to any file in git — tokens stay in Vault only
