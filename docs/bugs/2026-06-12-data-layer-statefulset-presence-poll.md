# Bugfix: v1.6.5 — poll for data-layer StatefulSet presence (Application Synced ≠ StatefulSets exist)

**Branch:** `k3d-manager-v1.6.5`
**Files:** `scripts/plugins/shopping_cart.sh`

---

## Problem

`acg-up` (AWS provision) fails at Step 10b/14 with:

```
INFO: [acg-up] data-layer Application Synced — proceeding to StatefulSet readiness check
ERROR: [shopping_cart] StatefulSet postgresql-orders not found in shopping-cart-data after ArgoCD sync
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
```

This is **not** the same bug as `v1.6.0-bugfix-data-layer-argocd-sync-wait.md` (already fixed —
`acg-up` does now wait for the `data-layer` Application to reach `Synced` on the k3d hub before
calling `deploy_shopping_cart_data`).

The residual race: the `data-layer` Application reaching **`Synced` on the k3d hub
(`k3d-k3d-cluster`)** does **not** guarantee the child StatefulSets already **exist on the spoke
cluster (`ubuntu-k3s`)**. There is hub→spoke propagation lag. But `deploy_shopping_cart_data`
checks StatefulSet presence with a **single, one-shot `kubectl get`** and hard-fails on the first
miss.

**Confirmed on the live cluster after the failure:** the namespace `shopping-cart-data` existed at
the time of the check, but all seven StatefulSets (`postgresql-orders/payment/products`, `minio`,
`rabbitmq`, `redis-cart`, `redis-orders-cache`) only became `1/1` Ready **~4 minutes later** — well
after the one-shot check ran and the provision had already exited and cleaned up.

**Root cause:** `scripts/plugins/shopping_cart.sh` lines 87–93 — the presence check is a one-shot
`if ! kubectl get statefulset/... ; then _err; return 1` with no retry/poll, so it reports a false
negative whenever the spoke hasn't yet materialised the StatefulSets created by ArgoCD.

---

## Reproduction

1. `make up` (CLUSTER_PROVIDER=k3s-aws) on a freshly registered cluster.
2. ArgoCD on the k3d hub flips `data-layer` to `Synced` quickly.
3. The spoke (`ubuntu-k3s`) has not yet created `postgresql-orders` → one-shot check fails →
   `acg-up` exits 1, even though the StatefulSets appear seconds-to-minutes later.

---

## Fix

### Change 1 — `scripts/plugins/shopping_cart.sh`: poll for StatefulSet presence with a deadline

**Exact old block (lines 85–93):**

```bash
  _info "[shopping_cart] Data layer managed by ArgoCD — verifying StatefulSet presence..."

  for pg in postgresql-orders postgresql-payment postgresql-products; do
    if ! kubectl get statefulset/"${pg}" \
        -n shopping-cart-data --context ubuntu-k3s >/dev/null 2>&1; then
      _err "[shopping_cart] StatefulSet ${pg} not found in shopping-cart-data after ArgoCD sync — check: kubectl get application data-layer -n cicd --context k3d-k3d-cluster"
      return 1
    fi
  done
```

**Exact new block:**

```bash
  _info "[shopping_cart] Data layer managed by ArgoCD — waiting for StatefulSets to appear (max 300s)..."

  local _sts_deadline
  _sts_deadline=$(( $(date +%s) + 300 ))
  for pg in postgresql-orders postgresql-payment postgresql-products; do
    until kubectl get statefulset/"${pg}" \
        -n shopping-cart-data --context ubuntu-k3s >/dev/null 2>&1; do
      if [[ $(date +%s) -ge ${_sts_deadline} ]]; then
        _err "[shopping_cart] StatefulSet ${pg} not created in shopping-cart-data within 300s of ArgoCD sync — check: kubectl get application data-layer -n cicd --context k3d-k3d-cluster"
        return 1
      fi
      _info "[shopping_cart] ${pg} not yet created by ArgoCD — waiting..."
      sleep 10
    done
  done
```

Once each StatefulSet **exists**, the subsequent `kubectl rollout status` loop (unchanged, just
below) handles readiness. The deadline is shared across the three PostgreSQL StatefulSets, matching
the 300s budget already used for the Application-Synced wait in `acg-up`.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/shopping_cart.sh` | one-shot StatefulSet presence check → bounded 300s poll |

---

## Rules

- `shellcheck -S warning scripts/plugins/shopping_cart.sh` — zero new warnings
  (note: declare `local _sts_deadline` on its own line before the `$(( ... ))` assignment to avoid
  SC2155)
- No other file touched
- Do NOT change the `rollout status` loop below — presence poll only
- Keep the error hint context `--context k3d-k3d-cluster` (the `data-layer` Application lives on the
  k3d hub, not on `ubuntu-k3s`)

---

## Definition of Done

- [ ] Presence check converted to a bounded `until` poll with a 300s shared deadline
- [ ] `shellcheck -S warning scripts/plugins/shopping_cart.sh` passes
- [ ] Only `scripts/plugins/shopping_cart.sh` modified
- [ ] Committed and pushed to `k3d-manager-v1.6.5`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(shopping_cart): poll for data-layer StatefulSet presence instead of one-shot check
```

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than `scripts/plugins/shopping_cart.sh`
- Do NOT touch the `rollout status` readiness loop
- Do NOT commit to `main` — work on `k3d-manager-v1.6.5`
