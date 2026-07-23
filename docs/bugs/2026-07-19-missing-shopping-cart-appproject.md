# Bug: `shopping-cart` AppProject referenced but never created — data-layer + services never sync

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl` (NEW), `scripts/plugins/argocd.sh`
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "missing `shopping-cart` AppProject" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/etc/argocd/projects/platform.yaml.tmpl` — the sibling AppProject; copy its
    structure and conventions (envsubst `${ARGOCD_NAMESPACE}`, `managed-by: k3d-manager` label).
  - `scripts/plugins/argocd.sh` — the whole `_argocd_deploy_appproject` function
    (currently lines ~1053–1072) and `_cleanup_trap_command` usage.
  - `scripts/etc/argocd/applicationsets/data-git.yaml` and `services-git.yaml` — the two
    appsets that set `project: shopping-cart`.
  - `scripts/tests/plugins/argocd.bats` — the `_argocd_deploy_appproject fails when template
    missing` test (line ~177). Your change must keep it passing.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

On a true fresh-hub rebuild (`make down` deletes the hub, `make up` recreates it), the app tier
never comes up. `make up` fails at:

```
ERROR: [acg-up] data-layer ArgoCD Application did not reach Synced after force-sync + 180s retry
make: *** [up] Error 1
```

**Root cause:** the `data-git` and `services-git` ApplicationSets both set
`spec.template.spec.project: shopping-cart`, but **no `shopping-cart` AppProject is ever
defined or deployed**. `scripts/etc/argocd/projects/` contains only `platform.yaml.tmpl`, and
`_argocd_deploy_appproject` deploys only that one file. ArgoCD therefore refuses to create the
generated Applications:

```
data-git    ErrorOccurred=True :: application references project shopping-cart which does not exist
services-git ErrorOccurred=True :: error getting project shopping-cart: AppProject.argoproj.io "shopping-cart" not found
```

So `ubuntu-k3s-data-layer` (postgres orders/payment) and every `shopping-cart` service
Application are never generated. This is **latent since v1.7.1 / PR #96 (2026-06-19)** — prior
rebuilds reused an existing hub, masking it; the first clean fresh-hub bootstrap exposes it.

Confirmed live before writing this spec:
- Existing AppProjects on the hub: only `default` and `platform`.
- `data-git` deploys to namespace `shopping-cart-data` (repo `shopping-cart-infra.git`, path `data-layer`).
- `services-git` deploys to namespace `shopping-cart-apps` (repo `k3d-manager`, `services/*`), and
  its `ignoreDifferences` also references namespace `shopping-cart-payment`.
- Both appsets use a `clusters` generator selecting `k3d-manager/role: app-cluster`, so their
  Applications currently target only the registered app cluster (`ubuntu-k3s`).
- The `platform` AppProject already lists `ubuntu-hostinger`/`ubuntu-gcp`/`ubuntu-azure` in its
  destinations even though those clusters are not registered, and its appsets generate fine —
  so listing not-yet-registered clusters in a project's `destinations` is harmless.

---

## Fix

### Change 1 — NEW file `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl`

Create it with EXACTLY this content (mirrors `platform.yaml.tmpl` conventions, scoped to the
three shopping-cart namespaces on all four app clusters for parity/future-proofing):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: shopping-cart
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    managed-by: k3d-manager
    project-type: shopping-cart
spec:
  description: Shopping-cart application workloads managed by k3d-manager
  sourceRepos:
    - '*'
  destinations:
    - namespace: shopping-cart-apps
      name: ubuntu-k3s
    - namespace: shopping-cart-apps
      name: ubuntu-hostinger
    - namespace: shopping-cart-apps
      name: ubuntu-gcp
    - namespace: shopping-cart-apps
      name: ubuntu-azure
    - namespace: shopping-cart-data
      name: ubuntu-k3s
    - namespace: shopping-cart-data
      name: ubuntu-hostinger
    - namespace: shopping-cart-data
      name: ubuntu-gcp
    - namespace: shopping-cart-data
      name: ubuntu-azure
    - namespace: shopping-cart-payment
      name: ubuntu-k3s
    - namespace: shopping-cart-payment
      name: ubuntu-hostinger
    - namespace: shopping-cart-payment
      name: ubuntu-gcp
    - namespace: shopping-cart-payment
      name: ubuntu-azure
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
    - group: ''
      kind: PersistentVolume
  namespaceResourceWhitelist:
    - group: '*'
      kind: '*'
  orphanedResources:
    warn: false
```

### Change 2 — `scripts/plugins/argocd.sh`: deploy BOTH projects

`_argocd_deploy_appproject` currently hardcodes `platform`. Replace the whole function with a
loop over both project templates (single trap over all rendered temp files via the multi-path
`_cleanup_trap_command`).

**Exact old block:**

```bash
function _argocd_deploy_appproject() {
   _info "[argocd] Deploying platform AppProject"

   local appproject_tmpl="$ARGOCD_CONFIG_DIR/projects/platform.yaml.tmpl"

   if [[ ! -f "$appproject_tmpl" ]]; then
      _err "[argocd] AppProject file not found: $appproject_tmpl"
      return 1
   fi

   local rendered
   rendered=$(mktemp -t argocd-appproject.XXXXXX.yaml)
   trap '$(_cleanup_trap_command "$rendered")' EXIT
   envsubst '$ARGOCD_NAMESPACE' < "$appproject_tmpl" > "$rendered"
   _kubectl apply --server-side -f "$rendered" >/dev/null
   trap '$(_cleanup_trap_command "$rendered")' RETURN

   _info "[argocd] AppProject deployed: platform"
   return 0
}
```

**Exact new block:**

```bash
function _argocd_deploy_appproject() {
   local -a appprojects=(platform shopping-cart)
   local -a rendered_files=()
   local proj appproject_tmpl rendered

   for proj in "${appprojects[@]}"; do
      _info "[argocd] Deploying ${proj} AppProject"

      appproject_tmpl="$ARGOCD_CONFIG_DIR/projects/${proj}.yaml.tmpl"
      if [[ ! -f "$appproject_tmpl" ]]; then
         _err "[argocd] AppProject file not found: $appproject_tmpl"
         return 1
      fi

      rendered=$(mktemp -t argocd-appproject.XXXXXX.yaml)
      rendered_files+=("$rendered")
      trap '$(_cleanup_trap_command "${rendered_files[@]}")' EXIT RETURN
      envsubst '$ARGOCD_NAMESPACE' < "$appproject_tmpl" > "$rendered"
      _kubectl apply --server-side -f "$rendered" >/dev/null

      _info "[argocd] AppProject deployed: ${proj}"
   done

   return 0
}
```

Do NOT touch any other function, the readiness list in `_argocd_bootstrap_is_ready`, or the
appsets. The order matters: `platform` first (an empty `projects/` dir must still fail on the
first iteration, preserving the existing BATS test).

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl` | NEW — `shopping-cart` AppProject definition |
| `scripts/plugins/argocd.sh` | `_argocd_deploy_appproject` loops over `platform` + `shopping-cart` |

---

## Rules

- `yq eval '.' scripts/etc/argocd/projects/shopping-cart.yaml.tmpl >/dev/null` — parses clean
  (this box's `python3` has no PyYAML; use `yq`, which is installed).
- **Presence gate:** `grep -c 'name: shopping-cart' scripts/etc/argocd/projects/shopping-cart.yaml.tmpl` → **`1`**
- **Presence gate:** `grep -c 'appprojects=(platform shopping-cart)' scripts/plugins/argocd.sh` → **`1`**
- **Disappearance gate:** `grep -c 'Deploying platform AppProject' scripts/plugins/argocd.sh` → **`0`**
  (the hardcoded single-project log line is gone; it is now `Deploying ${proj} AppProject`).
- `shellcheck -S warning scripts/plugins/argocd.sh` — **no NEW warnings** vs the pre-edit baseline
  (record the baseline warning count on `origin/k3d-manager-v1.16.0` before editing, and the
  post-edit count — they must match).
- `bats scripts/tests/plugins/argocd.bats` — all tests pass (esp. `_argocd_deploy_appproject
  fails when template missing`). Capture the summary line (`N tests, 0 failures`).
- `./scripts/k3d-manager _agent_audit` — exit 0
- No other files touched

---

## Definition of Done

- [ ] `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl` created with the exact content above
- [ ] `_argocd_deploy_appproject` deploys `platform` then `shopping-cart`
- [ ] `yq eval` parses the new template clean
- [ ] `grep` presence + disappearance gates pass (record outputs)
- [ ] `shellcheck -S warning scripts/plugins/argocd.sh` — no new warnings (record baseline + after)
- [ ] `bats scripts/tests/plugins/argocd.bats` — 0 failures (record the summary line)
- [ ] `_agent_audit` exit 0
- [ ] `git show --stat` shows exactly TWO files changed
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status (separate commit)

**Commit message (exact):**
```
fix(argocd): add shopping-cart AppProject so data-layer and services can sync
```

---

## What NOT to Do

- Do NOT change the `project: shopping-cart` field in the appsets — the fix is to CREATE the
  project, not repoint the appsets.
- Do NOT add resource *limits* or roles/RBAC groups to the new project — keep it to the blocks above.
- Do NOT change the `platform.yaml.tmpl` file.
- Do NOT touch `_argocd_bootstrap_is_ready` or any other function.
- Do NOT reorder the appprojects array (`platform` must be first).
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (do NOT delegate)

Live verify. After the commit lands, Claude re-runs `deploy_argocd_bootstrap` (or a targeted
re-apply of the project) on the live hub and confirms:

- `kubectl -n cicd get appproject shopping-cart` exists.
- `data-git` and `services-git` appsets clear `ErrorOccurred` and generate `ubuntu-k3s-data-layer`
  + the service Applications.
- The data-layer Application progresses to Synced (postgres orders/payment scheduling on
  `ubuntu-k3s` is a SEPARATE downstream concern if it still fails — file separately).
- Note the SEPARATE, still-open blocker this spec does NOT fix: the `istio-ambient` appset's
  destination validation error (`no clusters with this name: ubuntu-hostinger (and 3 more)`),
  which blocks the live istiod/ztunnel `1af15217` pod-level verify.
