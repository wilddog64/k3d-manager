# Bug: `cluster-up` Step 10b applies a deleted manifest and waits on a renamed Application

**Branch:** `k3d-manager-v1.16.0`
**Files:** `bin/cluster-up` (ONLY)

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "cluster-up Step 10b stale data-layer" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `bin/cluster-up` — the Step 10b block, roughly lines 725-790
  - `scripts/etc/argocd/applicationsets/data-git.yaml` — the ApplicationSet that now owns
    the data layer, and the `{{.name}}-data-layer` naming from `f03df202`
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

`CLUSTER_PROVIDER=k3s-aws make up` fails at Step 10b with:

```
error: the path ".../shopping-carts/shopping-cart-infra/argocd/applications/data-layer.yaml" does not exist
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

**The failure is spurious.** Measured live on 2026-07-19 at the moment of the abort, the data
layer was already fully deployed on `ubuntu-k3s` by the GitOps path:

```
shopping-cart-data   minio-0                1/1 Running
shopping-cart-data   postgresql-orders-0    1/1 Running
shopping-cart-data   postgresql-payment-0   1/1 Running
shopping-cart-data   postgresql-products-0  1/1 Running
shopping-cart-data   rabbitmq-0             1/1 Running
shopping-cart-data   redis-cart-0           1/1 Running
shopping-cart-data   redis-orders-cache-0   1/1 Running
```

and on the hub `ubuntu-k3s-data-layer` was `Synced`. All 22 pods on the cluster were
`Running` with zero failures. Step 10b aborted a bringup whose work had already succeeded
via a different, correct path.

### Two independent staleness defects in the same block

**1. Line 741 applies a manifest that was deleted on purpose.** In `shopping-cart-infra`:

```
9ebd775 fix(argocd): remove static data-layer app — delivered by k3d-manager data-git ApplicationSet (#84)
```

The file is not missing by accident and must not be restored. The `data-git` ApplicationSet
in this repo supersedes it.

**2. Line 744 waits for an Application named bare `data-layer`.** Phase 3 (`f03df202`)
renamed it to `{{.name}}-data-layer` to fix a multi-cluster name collision. The live app is
`ubuntu-k3s-data-layer`. Even with the apply removed, this wait can never match — it would
hang the full 300s, force-sync a nonexistent app, then hang another 180s.

Both defects date from before the `data-git` migration. The early-exit at line 735 (4
StatefulSets already ready) is why this was not caught sooner: on a warm cluster the block
short-circuits and never reaches the broken path. It only fires on a genuinely fresh
cluster, where the StatefulSets are seconds old and not yet ready.

---

## Fix

### Change 1 — `bin/cluster-up`: drop the imperative apply, wait on the per-cluster name

**Exact old block (lines 739-745):**

```bash
    _info "[acg-up] Applying data-layer ArgoCD Application so sync starts before wait loop..."
    _run_command -- kubectl apply --context k3d-k3d-cluster \
      -f "${REPO_ROOT}/../shopping-carts/shopping-cart-infra/argocd/applications/data-layer.yaml"
    _info "[acg-up] Waiting for ArgoCD to sync data-layer Application (max 300s)..."
    _dl_sync_deadline=$(( $(date +%s) + 300 ))
    until kubectl get application data-layer -n cicd --context k3d-k3d-cluster \
        -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q "Synced"; do
```

**Exact new block:**

```bash
    _dl_app_name="${APP_CLUSTER_NAME:-ubuntu-k3s}-data-layer"
    _info "[acg-up] data-layer is delivered by the data-git ApplicationSet — waiting for ${_dl_app_name} (max 300s)..."
    _dl_sync_deadline=$(( $(date +%s) + 300 ))
    until kubectl get application "${_dl_app_name}" -n cicd --context k3d-k3d-cluster \
        -o jsonpath='{.status.sync.status}' 2>/dev/null | grep -q "Synced"; do
```

Do NOT restore `data-layer.yaml` in `shopping-cart-infra`. Do NOT add a fallback that
re-creates the Application imperatively. The ApplicationSet is the single owner.

### Change 2 — `bin/cluster-up`: retarget the remaining bare `data-layer` references

Every other reference in the Step 10b block that names the Application `data-layer` must use
`"${_dl_app_name}"` instead. This includes at minimum the inner retry wait (~line 755) and
the `argocd app sync data-layer` force-sync (~line 748):

```bash
        argocd app sync "${_dl_app_name}" \
```

Locate them by reading the block — line numbers shift as you edit. **Only** rename references
to the ArgoCD *Application*. Do NOT rename the `shopping-cart-data` namespace, the
StatefulSet names, or the `path: data-layer` repo path — those are unrelated and correct.

---

## Files Changed

| File | Change |
|------|--------|
| `bin/cluster-up` | drop deleted-manifest apply; wait on `${APP_CLUSTER_NAME}-data-layer` |

---

## Rules

- `bash -n bin/cluster-up` — clean
- `shellcheck -S warning bin/cluster-up` — zero NEW warnings
- **Disappearance gate:** `grep -c 'applications/data-layer.yaml' bin/cluster-up` → **`0`**
- **Disappearance gate:** `grep -c 'application data-layer ' bin/cluster-up` → **`0`**
- **Presence gate:** `grep -c '_dl_app_name' bin/cluster-up` → at least `4`
- **Unchanged gate:** `grep -c 'shopping-cart-data' bin/cluster-up` must be the SAME before
  and after — record both numbers. A change here means the namespace was renamed by mistake.
- `./scripts/k3d-manager _agent_audit` — exit 0
- No other files touched

---

## Definition of Done

- [ ] Imperative apply of the deleted manifest removed
- [ ] All ArgoCD Application references use `${APP_CLUSTER_NAME}-data-layer`
- [ ] Namespace / StatefulSet / repo-path references untouched (gate recorded both counts)
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] `_agent_audit` exit 0
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(cluster-up): stop applying deleted data-layer manifest in Step 10b
```

---

## What NOT to Do

- Do NOT restore `data-layer.yaml` in `shopping-cart-infra` — `9ebd775` deleted it deliberately.
- Do NOT add an imperative fallback that creates the Application when the ApplicationSet has
  not generated it yet. Waiting is correct; racing the ApplicationSet is not.
- Do NOT rename the `shopping-cart-data` namespace or the StatefulSets.
- Do NOT remove the line-735 early-exit that skips the wait when the StatefulSets are ready.
- Do NOT touch the Vault profile logic — that is a separate, already-filed bug
  (`2026-07-07-app-cluster-vault-portability.md`).
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the single listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (do NOT delegate)

Live re-verification: re-run `CLUSTER_PROVIDER=k3s-aws make up` against a fresh ACG sandbox
and confirm it reaches exit 0. Agents do not touch the live cluster or provision sandboxes.
