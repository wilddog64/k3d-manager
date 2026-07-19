# Bug: `shopping-cart` AppProject missing `secrets` namespace destination — data-layer sync blocked on `vault-bridge`

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl`
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).
**Follow-up to:** `docs/bugs/2026-07-19-missing-shopping-cart-appproject.md` (`e118f664`) — that spec
CREATED the `shopping-cart` AppProject; this one adds the one destination namespace it omitted.

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "shopping-cart AppProject missing `secrets` destination" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl` — the file you are editing (created by `e118f664`).
  - `scripts/etc/argocd/projects/platform.yaml.tmpl` lines 13–23 — the sibling project already lists
    `namespace: secrets` destinations for the same four app clusters. Mirror that exact pattern.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

On a true fresh-hub rebuild (`make down` → `make up CLUSTER_PROVIDER=k3s-aws`), the `shopping-cart`
AppProject is now created (thanks to `e118f664`), the `data-git`/`services-git` appsets clear
`ErrorOccurred`, and `ubuntu-k3s-data-layer` is generated — **but the data-layer sync fails**:

```
ERROR: [acg-up] data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry
make: *** [up] Error 1  (UP_EXIT=2)
```

ArgoCD per-resource sync result:

```
Service/vault-bridge [SyncFailed] namespace secrets is not permitted in project 'shopping-cart'
```

**Root cause:** the `data-layer` manifest tree (repo `shopping-cart-infra.git`, path `data-layer`)
includes `data-layer/secrets/vault-bridge-svc.yaml` — a `Service/vault-bridge` in the **`secrets`**
namespace (the stable DNS `vault-bridge.secrets.svc.cluster.local:8201` for the Vault socat bridge).
The `shopping-cart` AppProject created by `e118f664` permits only the three `shopping-cart-*`
namespaces, so ArgoCD rejects the whole sync at the `vault-bridge` task and nothing in the
data-layer deploys.

The data-layer spans FOUR namespaces (`kubectl ... application ubuntu-k3s-data-layer -o
jsonpath='{.status.resources[*].namespace}' | sort -u`): `secrets`, `shopping-cart-apps`,
`shopping-cart-data`, `shopping-cart-payment`. Only `secrets` is missing from the project.

**Confirmed live before writing this spec:**
- Patching the live `shopping-cart` AppProject to add the four `secrets` destinations, then
  re-syncing, made `ubuntu-k3s-data-layer` reach **`Synced / Healthy`** with all 7 pods
  1/1 Running (minio, postgresql-orders/payment/products, rabbitmq, redis-cart, redis-orders-cache)
  and **zero remaining per-resource sync failures**. `secrets` was the only missing destination.
- The `platform` AppProject already lists `namespace: secrets` for `ubuntu-k3s`/`-hostinger`/`-gcp`/
  `-azure` (`platform.yaml.tmpl` lines 16–23) and syncs fine — this is an established, correct pattern.
- The `secrets` namespace is created by `k3d-manager` (`bin/acg-up` Step 6), not by ArgoCD, and is
  `Active` on the app cluster at sync time.

The live patch is EPHEMERAL — the next rebuild recreates the AppProject from the template and
reintroduces the blocker. This spec makes the fix permanent in the template.

---

## Fix

### Change 1 — `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl`: add `secrets` destinations

Append four `secrets` destinations (one per app cluster) to the end of the `destinations:` list,
immediately after the last `shopping-cart-payment` entry and before `clusterResourceWhitelist:`.

**Exact old block:**

```yaml
    - namespace: shopping-cart-payment
      name: ubuntu-k3s
    - namespace: shopping-cart-payment
      name: ubuntu-hostinger
    - namespace: shopping-cart-payment
      name: ubuntu-gcp
    - namespace: shopping-cart-payment
      name: ubuntu-azure
  clusterResourceWhitelist:
```

**Exact new block:**

```yaml
    - namespace: shopping-cart-payment
      name: ubuntu-k3s
    - namespace: shopping-cart-payment
      name: ubuntu-hostinger
    - namespace: shopping-cart-payment
      name: ubuntu-gcp
    - namespace: shopping-cart-payment
      name: ubuntu-azure
    - namespace: secrets
      name: ubuntu-k3s
    - namespace: secrets
      name: ubuntu-hostinger
    - namespace: secrets
      name: ubuntu-gcp
    - namespace: secrets
      name: ubuntu-azure
  clusterResourceWhitelist:
```

Do NOT touch `scripts/plugins/argocd.sh` (the deploy loop already handles this template), the
`platform.yaml.tmpl` file, or any appset. Do NOT change the `clusterResourceWhitelist`,
`namespaceResourceWhitelist`, or `orphanedResources` blocks.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl` | Add four `secrets` namespace destinations (one per app cluster) |

---

## Rules

- `yq eval '.' scripts/etc/argocd/projects/shopping-cart.yaml.tmpl >/dev/null` — parses clean
  (this box's `python3` has no PyYAML; use `yq`, which is installed).
- **Appearance gate:** `grep -c 'namespace: secrets' scripts/etc/argocd/projects/shopping-cart.yaml.tmpl` → **`4`**
  (was `0` before this change — `secrets` did not appear in this file at all).
- **Unchanged gate:** `grep -c 'namespace: shopping-cart-' scripts/etc/argocd/projects/shopping-cart.yaml.tmpl` → **`12`** (unchanged — the three shopping-cart-* namespaces × four clusters).
- `bats scripts/tests/plugins/argocd.bats` — all tests pass (capture the `N tests, 0 failures` line).
- `./scripts/k3d-manager _agent_audit` — exit 0
- `git show --stat` shows exactly ONE file changed
- No other files touched

---

## Definition of Done

- [ ] Four `secrets` destinations added to `shopping-cart.yaml.tmpl`, after the payment block
- [ ] `yq eval` parses the template clean
- [ ] `grep -c 'namespace: secrets'` → `4`; `grep -c 'namespace: shopping-cart-'` → `12` (record outputs)
- [ ] `bats scripts/tests/plugins/argocd.bats` — 0 failures (record the summary line)
- [ ] `_agent_audit` exit 0
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status (separate commit)

**Commit message (exact):**
```
fix(argocd): permit secrets namespace in shopping-cart AppProject for vault-bridge
```

---

## What NOT to Do

- Do NOT add resource limits, roles/RBAC, or a hub (`server: https://kubernetes.default.svc`)
  destination — the data-layer targets only the app clusters by name.
- Do NOT change `platform.yaml.tmpl`, `scripts/plugins/argocd.sh`, or any appset.
- Do NOT reorder or alter the existing `shopping-cart-*` destinations.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the one listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (do NOT delegate)

Live verify was already performed BEFORE this spec (live AppProject patch → data-layer reached
`Synced / Healthy`, all 7 pods Running). After the commit lands, Claude confirms the committed
template renders identically to the proven live patch. A full fresh-hub e2e re-run is optional
(the live proof already covers the sync path). The SEPARATE, still-open blocker this spec does
NOT fix: the `istio-ambient` appset's destination validation error (`no clusters with this name:
ubuntu-hostinger (and 3 more)`), which blocks the live istiod/ztunnel `1af15217` pod-level verify.
