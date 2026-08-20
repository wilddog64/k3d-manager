# Bugfix: v1.16.0 — `make refresh` on hostinger drops the istio-ambient ApplicationSet

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/lib/providers/k3s-hostinger.sh`

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — the Hostinger ambient
  section records that ambient is live on `ubuntu-hostinger` (HBONE + mTLS proven), and that this
  reapply gap is the last durability hole in the milestone.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/lib/providers/k3s-hostinger.sh` — the whole
    `_hostinger_reapply_gitops_applicationsets` function (currently lines 778–810), especially the
    `appsets` array and the `envsubst` allowlist inside the loop.
  - `scripts/etc/argocd/applicationsets/istio-ambient.yaml` — note every `${VAR}` it references.
  - `scripts/etc/argocd/vars.sh` — confirm `AMBIENT_ISTIO_VERSION`, `AMBIENT_CNI_CONF_DIR`,
    `AMBIENT_CNI_BIN_DIR` are defaulted+exported there (they are, post spec (d) `a08911b3`).
  - `docs/bugs/2026-07-21-ambient-cni-vars-missing-from-argocd-vars.md` — the sibling spec that
    established the two-layer defaulting rule this fix depends on.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

`_hostinger_reapply_gitops_applicationsets` in `scripts/lib/providers/k3s-hostinger.sh` is the
function `make refresh` (and any hub re-registration) uses to re-assert the hostinger
ApplicationSets onto the hub ArgoCD. Its `appsets` array lists exactly three files:

```bash
  local -a appsets=(
    "data-git.yaml"
    "services-git.yaml"
    "platform-helm.yaml"
  )
```

`istio-ambient.yaml` is **not** in the list. Ambient enrollment (istio-cni, ztunnel, istiod, and
the `shopping-cart-apps` ambient labeling that carries live HBONE traffic today) was applied to the
hub only via `deploy_istio_ambient`. The moment `make refresh` runs, the three listed appsets are
re-asserted and the ambient appset is **not** — so the ambient dataplane stops being reconciled
from git and drifts out of GitOps control. A subsequent hub rebuild (which de-registers and
re-registers the spoke) then never re-applies ambient at all.

**Root cause:** the reapply list was written before the ambient milestone and was never extended
when ambient became part of the hostinger deployment.

### Second, load-bearing detail — the envsubst allowlist

The loop renders each appset through a fixed `envsubst` allowlist (currently line 802):

```bash
    if ! envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH $APP_CLUSTER_NAME' < "${appset_path}" | "${hub_kubectl[@]}" apply -f - >/dev/null 2>&1; then
```

`istio-ambient.yaml` references three variables the current allowlist does **not** name —
`${AMBIENT_ISTIO_VERSION}`, `${AMBIENT_CNI_CONF_DIR}`, `${AMBIENT_CNI_BIN_DIR}`. `envsubst` with a
restrictive allowlist leaves any variable *not* in the list untouched, so simply adding
`istio-ambient.yaml` to the array without widening the allowlist would apply a manifest containing
literal `${AMBIENT_CNI_CONF_DIR}` strings — broken. Both changes are required together.

The three `AMBIENT_*` variables are already present in the environment on this code path:
`_hostinger_reapply_gitops_applicationsets` calls `_hostinger_load_argocd_plugin`, which sources
`scripts/plugins/argocd.sh`, which sources `scripts/etc/argocd/vars.sh` at load time — and that
file defaults+exports all three (post spec (d)). This fix therefore does **not** re-declare the
defaults (spec (d) is the single source of truth); it only widens the allowlist to name them.

---

## Reproduction

Static — no cluster required. From the repo root:

**Before the fix — the appset is absent from the reapply list:**

```bash
grep -n 'istio-ambient.yaml' scripts/lib/providers/k3s-hostinger.sh
```
→ prints nothing (the array does not contain it).

**Render check — the widened allowlist must fully resolve istio-ambient.yaml (no residual
placeholders):**

```bash
env -i HOME="${HOME}" PATH="${PATH}" bash -c '
  cd "'"$(pwd)"'"
  source scripts/etc/argocd/vars.sh
  export ARGOCD_NAMESPACE=cicd K3D_MANAGER_BRANCH=k3d-manager-v1.16.0 APP_CLUSTER_NAME=ubuntu-hostinger
  for f in data-git services-git platform-helm istio-ambient; do
    residual=$(envsubst "\$ARGOCD_NAMESPACE \$K3D_MANAGER_BRANCH \$APP_CLUSTER_NAME \$AMBIENT_ISTIO_VERSION \$AMBIENT_CNI_CONF_DIR \$AMBIENT_CNI_BIN_DIR" \
      < "scripts/etc/argocd/applicationsets/${f}.yaml" | grep -c "\${")
    echo "${f} residual=${residual}"
  done'
```

Expected after the fix: **every** line reads `residual=0`. If `istio-ambient residual` is nonzero,
the allowlist is missing one of the `AMBIENT_*` names.

---

## Fix

### Change 1 — add `istio-ambient.yaml` to the reapply list

**Exact old block (lines 789–793):**

```bash
  local -a appsets=(
    "data-git.yaml"
    "services-git.yaml"
    "platform-helm.yaml"
  )
```

**Exact new block:**

```bash
  local -a appsets=(
    "data-git.yaml"
    "services-git.yaml"
    "platform-helm.yaml"
    "istio-ambient.yaml"
  )
```

> Apply order to the hub is not load-bearing — ArgoCD reconciles each ApplicationSet
> independently via its own sync-waves. Appending is correct; do not reorder the existing three.

### Change 2 — widen the `envsubst` allowlist to cover the ambient variables

**Exact old block (line 802):**

```bash
    if ! envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH $APP_CLUSTER_NAME' < "${appset_path}" | "${hub_kubectl[@]}" apply -f - >/dev/null 2>&1; then
```

**Exact new block:**

```bash
    if ! envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH $APP_CLUSTER_NAME $AMBIENT_ISTIO_VERSION $AMBIENT_CNI_CONF_DIR $AMBIENT_CNI_BIN_DIR' < "${appset_path}" | "${hub_kubectl[@]}" apply -f - >/dev/null 2>&1; then
```

> A superset allowlist is safe: `envsubst` only substitutes a listed variable where it actually
> appears, so naming the `AMBIENT_*` vars does not affect the three git appsets that never use them.

### Change 3 — update the summary log line to name the fourth appset

**Exact old block (line 808):**

```bash
  _info "[k3s-hostinger] reapplied data-git, services-git, and platform-helm ApplicationSets for ${_HOSTINGER_KUBE_CONTEXT}"
```

**Exact new block:**

```bash
  _info "[k3s-hostinger] reapplied data-git, services-git, platform-helm, and istio-ambient ApplicationSets for ${_HOSTINGER_KUBE_CONTEXT}"
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/lib/providers/k3s-hostinger.sh` | add `istio-ambient.yaml` to the reapply list; widen the `envsubst` allowlist with the three `AMBIENT_*` vars; update the summary log line |

---

## Rules

- `shellcheck -S warning scripts/lib/providers/k3s-hostinger.sh` — zero new warnings.
- `bash -n scripts/lib/providers/k3s-hostinger.sh` — must parse.
- **Render gate** — the Reproduction "render check" command must print `residual=0` for **all four**
  appsets. Paste the full four-line output.
- **Absent-default gate** — the fix must NOT add any `export AMBIENT_CNI_CONF_DIR=`,
  `export AMBIENT_CNI_BIN_DIR=`, or `export AMBIENT_ISTIO_VERSION=` line to
  `k3s-hostinger.sh`. Those defaults live only in `scripts/etc/argocd/vars.sh` (spec (d)); this
  function inherits them via the argocd plugin load. Verify and paste:
  ```bash
  grep -c 'export AMBIENT_' scripts/lib/providers/k3s-hostinger.sh
  ```
  → must print `0`.
- No other function touched; no reordering of the three existing appsets.
- Do NOT run `make refresh`, `deploy_argocd_bootstrap`, `deploy_istio_ambient`, or any `kubectl`
  against a live cluster. Codex has no live-cluster verification role here; static gates only.
  Claude runs the live check (below).

---

## Definition of Done

- [ ] `appsets` array contains all four files, `istio-ambient.yaml` last.
- [ ] `envsubst` allowlist names the three `AMBIENT_*` vars in addition to the original three.
- [ ] Summary log line names istio-ambient.
- [ ] Render gate prints `residual=0` for all four appsets.
- [ ] `grep -c 'export AMBIENT_' scripts/lib/providers/k3s-hostinger.sh` → `0`.
- [ ] `shellcheck -S warning` clean; `bash -n` clean.
- [ ] No other file modified — `git show <sha> --stat` shows exactly one file.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`; push verified with pasted
      `git log origin/k3d-manager-v1.16.0 --oneline -1`.
- [ ] memory-bank updated with commit SHA and task status — as a **separate commit**, never
      bundled with the code change.

**Commit message (exact):**
```
fix(hostinger): reapply istio-ambient ApplicationSet on refresh
```

### Live re-verify — Claude runs this after the push (NOT Codex)

Run `make refresh CLUSTER_PROVIDER=k3s-hostinger` and confirm the log line now names istio-ambient,
the hub carries the `istio-ambient` ApplicationSet after refresh, and the generated
`istio-cni-ubuntu-hostinger` / `ztunnel-ubuntu-hostinger` Applications render concrete rancher CNI
paths (no literal `${AMBIENT_*}`), so ambient survives a refresh.

---

## What NOT to Do

- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file other than `scripts/lib/providers/k3s-hostinger.sh`.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.
- Do NOT add `export AMBIENT_*` defaults to `k3s-hostinger.sh` — they belong only in
  `scripts/etc/argocd/vars.sh`; a third copy risks the defaults drifting apart.
- Do NOT reorder or rename the three existing appsets, and do NOT touch any other function in the
  file (`_hostinger_reconcile_vault_cluster_store`, etc.).
- Do NOT change the `k3s-oci.sh` bootstrap allowlist — that is a separate, deeper bug with its own
  spec/decision; fixing it here would be scope creep.
