# Bug: appset-deploy loop defaults `APP_CLUSTER_NAME` to `ubuntu-hostinger` → istio-ambient/observability-acg render against a nonexistent cluster

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/plugins/argocd.sh`
**Classification:** Bugfix in `docs/bugs/` (exempt from the max-5-plan limit).

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "istio-ambient dest validation" OPEN blocker on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/plugins/argocd.sh` — the whole `_argocd_deploy_applicationsets` function
    (currently starts at line ~1159), especially the `APP_CLUSTER_NAME` default and the
    `_active_app_cluster` resolution block right below it.
  - `scripts/plugins/istio_ambient.sh` line 21 and `scripts/etc/argocd/vars.sh` line 65 —
    both already default the app-cluster name to `ubuntu-k3s`; `argocd.sh` is the outlier.
  - `scripts/lib/provider.sh` — `_acg_provider_context` (line ~92) and `_acg_resolve_provider`
    (line ~121): for `CLUSTER_PROVIDER=k3s-aws` they resolve to `ubuntu-k3s`, for
    `k3s-hostinger` to `ubuntu-hostinger`, etc.
- Implement exactly what is written — no interpretation, no scope expansion.

---

## Problem

On a fresh `k3s-aws` hub rebuild the `istio-ambient` ApplicationSet never generates its
Applications. The appset status shows:

```
ErrorOccurred=True :: application destination spec is invalid:
  there are no clusters with this name: ubuntu-hostinger (and 3 more)
ParametersGenerated=True :: Successfully generated parameters for all Applications
```

The generated Applications target cluster **`ubuntu-hostinger`**, which is not registered on a
`k3s-aws` hub (only `ubuntu-k3s` is). So istiod/ztunnel/istio-cni/istio-base are never created and
the ambient mesh never installs — even though the data-layer and services appsets sync fine.

**Root cause:** the `istio-ambient` and `observability-acg` ApplicationSets are the only appsets
that consume `${APP_CLUSTER_NAME}` directly as their `destination.name` (the data/services appsets
use a `clusters` label-selector generator instead, so they are unaffected). During `make up` these
appsets are rendered and applied by the generic `_argocd_deploy_applicationsets` loop in
`scripts/plugins/argocd.sh` (a `find … -name '*.yaml'` glob over the appsets dir —
`deploy_istio_ambient` is **not** called in the up flow). That function defaults:

```bash
APP_CLUSTER_NAME="${APP_CLUSTER_NAME:-ubuntu-hostinger}"
```

`ubuntu-hostinger` is the wrong default for any non-hostinger provider — and it is the outlier:
`istio_ambient.sh:21` and `vars.sh:65` both default to `ubuntu-k3s`. Worse, the function already
resolves the correct active cluster into `_active_app_cluster` (via
`_acg_provider_context "$(_acg_resolve_provider)"` → `ubuntu-k3s` for `k3s-aws`) a few lines later,
but only uses it for the role-label — it never feeds it back into `APP_CLUSTER_NAME` before the
render loop. So the appsets render against the hardcoded `ubuntu-hostinger` regardless of provider.

**Confirmed live before writing this spec (fresh k3s-aws hub, acct `739527292320`):**
- The live `istio-ambient` appset had `template.spec.destination.name: ubuntu-hostinger` and
  `template.metadata.name: {{ .name }}-ubuntu-hostinger`, and `ErrorOccurred=True :: there are no
  clusters with this name: ubuntu-hostinger (and 3 more)`.
- Re-applying the appset rendered with `APP_CLUSTER_NAME=ubuntu-k3s` (via
  `deploy_istio_ambient --confirm`, the intended standalone path, which defaults to `ubuntu-k3s`)
  cleared the error immediately: `ErrorOccurred=False :: All applications have been generated
  successfully`; the four Applications generated with `dest=ubuntu-k3s`; **istiod came up 1/1
  Running** on the spoke (proving the `1af15217` istiod right-size) and istio-cni-node 1/1 ×3.
- `_acg_provider_context "$(_acg_resolve_provider)"` returns `ubuntu-k3s` for `CLUSTER_PROVIDER=k3s-aws`
  and `ubuntu-hostinger` for `k3s-hostinger`, so deriving the default from it preserves hostinger
  behavior while fixing k3s-aws.

This is the appset **destination-validation** blocker. It is SEPARATE from the still-open
istio-cni conf/bin dir mismatch (`docs/bugs/2026-07-17-ambient-istio-cni-conf-bin-dir-mismatch.md`),
which blocks ztunnel AFTER the Applications generate — do NOT touch that here.

---

## Fix

### Change 1 — `scripts/plugins/argocd.sh`: derive `APP_CLUSTER_NAME` from the resolved active cluster

Resolve `_active_app_cluster` FIRST, then use it as the default for `APP_CLUSTER_NAME`, falling back
to `ubuntu-k3s` (matching `istio_ambient.sh` and `vars.sh`) instead of `ubuntu-hostinger`. An
explicit `APP_CLUSTER_NAME` from the environment still wins.

**Exact old block:**

```bash
   APP_CLUSTER_NAME="${APP_CLUSTER_NAME:-ubuntu-hostinger}"
   export APP_CLUSTER_NAME
   local _active_app_cluster=""
   if declare -f _acg_provider_context >/dev/null 2>&1 && declare -f _acg_resolve_provider >/dev/null 2>&1; then
      _active_app_cluster="$(_acg_provider_context "$(_acg_resolve_provider)" 2>/dev/null)"
   fi
   _active_app_cluster="${_active_app_cluster:-${APP_CLUSTER_NAME}}"
   _argocd_set_active_app_cluster "${_active_app_cluster}"
```

**Exact new block:**

```bash
   local _active_app_cluster=""
   if declare -f _acg_provider_context >/dev/null 2>&1 && declare -f _acg_resolve_provider >/dev/null 2>&1; then
      _active_app_cluster="$(_acg_provider_context "$(_acg_resolve_provider)" 2>/dev/null)"
   fi
   APP_CLUSTER_NAME="${APP_CLUSTER_NAME:-${_active_app_cluster:-ubuntu-k3s}}"
   export APP_CLUSTER_NAME
   _active_app_cluster="${_active_app_cluster:-${APP_CLUSTER_NAME}}"
   _argocd_set_active_app_cluster "${_active_app_cluster}"
```

Do NOT touch any other line of `_argocd_deploy_applicationsets`, any other function, any appset
YAML, or `istio_ambient.sh`/`vars.sh`.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/argocd.sh` | `_argocd_deploy_applicationsets` derives `APP_CLUSTER_NAME` from the resolved active app cluster (fallback `ubuntu-k3s`), not the hardcoded `ubuntu-hostinger` |

---

## Rules

- **Disappearance gate:** `grep -c 'APP_CLUSTER_NAME:-ubuntu-hostinger' scripts/plugins/argocd.sh` → **`0`**
  (the hardcoded hostinger default is gone).
- **Appearance gate:** `grep -c 'APP_CLUSTER_NAME:-${_active_app_cluster:-ubuntu-k3s}' scripts/plugins/argocd.sh` → **`1`**
- `shellcheck -S warning scripts/plugins/argocd.sh` — **0 warnings** (baseline on
  `origin/k3d-manager-v1.16.0` is 0; must stay 0).
- `bats scripts/tests/plugins/argocd.bats` — all tests pass (capture the `N tests, 0 failures` line).
- `./scripts/k3d-manager _agent_audit` — exit 0
- `git show --stat` shows exactly ONE file changed
- No other files touched

---

## Definition of Done

- [ ] `_argocd_deploy_applicationsets` resolves `_active_app_cluster` before defaulting
      `APP_CLUSTER_NAME`, with fallback `ubuntu-k3s`
- [ ] `grep -c 'APP_CLUSTER_NAME:-ubuntu-hostinger'` → `0`; `grep -c 'APP_CLUSTER_NAME:-${_active_app_cluster:-ubuntu-k3s}'` → `1` (record outputs)
- [ ] `shellcheck -S warning scripts/plugins/argocd.sh` — 0 warnings (record baseline + after)
- [ ] `bats scripts/tests/plugins/argocd.bats` — 0 failures (record the summary line)
- [ ] `_agent_audit` exit 0
- [ ] `git show --stat` shows exactly ONE file changed
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status (separate commit)

**Commit message (exact):**
```
fix(argocd): derive appset APP_CLUSTER_NAME from active cluster, not hardcoded hostinger
```

---

## What NOT to Do

- Do NOT change the istio-cni conf/bin paths or anything in `istio-ambient.yaml` — that is a
  SEPARATE, already-specced blocker (`2026-07-17-ambient-istio-cni-conf-bin-dir-mismatch.md`).
- Do NOT change `istio_ambient.sh`, `vars.sh`, `observability.sh`, or any appset YAML.
- Do NOT touch the render loop, the `_unset` var-guard, or `_argocd_set_active_app_cluster`.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the one listed target
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (do NOT delegate)

Live verify was already performed BEFORE this spec (re-applying the appset with
`APP_CLUSTER_NAME=ubuntu-k3s` cleared the dest-validation error and generated the four Applications
against `ubuntu-k3s`; istiod 1/1 Running). After the commit lands, Claude confirms the committed
`argocd.sh` renders the appsets with `ubuntu-k3s` on a `k3s-aws` hub (no manual override). The
NEXT, still-open blocker this spec does NOT fix: the istio-cni conf/bin dir mismatch that keeps
ztunnel in `ContainerCreating` (`failed to find plugin "istio-cni"`) — spec
`2026-07-17-ambient-istio-cni-conf-bin-dir-mismatch.md` (unassigned).
