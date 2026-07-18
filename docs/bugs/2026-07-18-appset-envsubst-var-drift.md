# Bug: `_argocd_deploy_applicationsets` envsubst list drifts from ApplicationSet variables

**Branch:** `k3d-manager-v1.16.0`
**Files:** `scripts/plugins/argocd.sh` (primary), plus a new BATS guard

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "appset envsubst var drift" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read IN FULL before editing:
  - `scripts/plugins/argocd.sh` — the `_argocd_deploy_applicationsets` function (~line 1160-1204)
  - `scripts/plugins/istio_ambient.sh` — lines 15-38, the CORRECT targeted apply for comparison
  - every file in `scripts/etc/argocd/applicationsets/`
- Implement exactly what is written — no interpretation, no extra refactors.

---

## Problem

`_argocd_deploy_applicationsets` applies every `*.yaml` in
`scripts/etc/argocd/applicationsets/` through a **hardcoded three-variable** envsubst list:

```bash
envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH $APP_CLUSTER_NAME' < "$file" | _kubectl apply -f -
```

`istio-ambient.yaml` references a fourth variable, `${AMBIENT_ISTIO_VERSION}`. It is not in
the list, so the bootstrap path applies that ApplicationSet with the literal string
`${AMBIENT_ISTIO_VERSION}` in `spec.template.spec.source.targetRevision`.

**Live evidence (hub `k3d-k3d-cluster`, 2026-07-18):**

```
$ kubectl --context k3d-k3d-cluster get applicationset istio-ambient -n cicd \
    -o jsonpath='{.spec.template.spec.source.targetRevision}'
${AMBIENT_ISTIO_VERSION}

$ kubectl --context k3d-k3d-cluster get applications -n cicd
istio-base-ubuntu-hostinger   Unknown   Healthy
istio-cni-ubuntu-hostinger    Unknown   Healthy
istiod-ubuntu-hostinger       Unknown   Healthy

ComparisonError: Failed to load target state: failed to generate manifest for source 1 of 1:
rpc error: code = Unknown desc = invalid revision: failed to determine semver constraint:
improper constraint: ${AMBIENT_ISTIO_VERSION}
```

**Root cause:** the envsubst allow-list is maintained by hand in a generic loop, while the
set of variables used across ApplicationSet files grows independently. `istio_ambient.sh:32`
does include `$AMBIENT_ISTIO_VERSION` in its own targeted apply, so the two paths disagree
and whichever ran last wins. This is not stale state — the bootstrap path reproduces it.

**Why it matters beyond istio:** any future ApplicationSet that introduces a new variable
silently ships an unsubstituted literal to the cluster. Nothing fails loudly; the appset
applies successfully and the generated Applications go `Unknown`.

---

## Fix

### Change 1 — `scripts/plugins/argocd.sh`: derive the envsubst list from the file

**Exact old block (line 1196):**

```bash
      if envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH $APP_CLUSTER_NAME' < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
```

**Exact new block:**

```bash
      local _vars
      _vars="$(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' "$file" 2>/dev/null \
         | tr -d '${}' | sort -u | sed 's/^/$/' | tr '\n' ' ')"
      if envsubst "${_vars}" < "$file" | _kubectl apply -f - >/dev/null 2>&1; then
```

This keeps envsubst restricted to an explicit allow-list (so Go template `{{...}}` and any
`$`-literals in the manifest are still safe), but derives that list from the file being
applied instead of a hand-maintained constant.

### Change 2 — NEW `scripts/tests/plugins/appset_envsubst_coverage.bats`

A guard that fails when any ApplicationSet references a variable the deploy path cannot
substitute. Write exactly this file:

```bash
#!/usr/bin/env bats

APPSETS="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets"
ARGOCD="${BATS_TEST_DIRNAME}/../../plugins/argocd.sh"

@test "appset deploy derives envsubst vars from each file" {
  run grep -c "envsubst '\$ARGOCD_NAMESPACE \$K3D_MANAGER_BRANCH \$APP_CLUSTER_NAME'" "${ARGOCD}"
  [ "${output}" -eq 0 ]
}

@test "every appset variable is exported by some deploy path" {
  local missing=""
  for f in "${APPSETS}"/*.yaml; do
    for v in $(grep -oh '\${[A-Za-z_][A-Za-z0-9_]*}' "$f" | tr -d '${}' | sort -u); do
      grep -rqh "export .*${v}\|: \"\${${v}:=" "${BATS_TEST_DIRNAME}/../../plugins/" \
        || missing="${missing} $(basename "$f"):${v}"
    done
  done
  [ -z "${missing}" ] || { echo "unexported appset vars:${missing}"; false; }
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/plugins/argocd.sh` | derive envsubst allow-list per file instead of hardcoding three vars |
| `scripts/tests/plugins/appset_envsubst_coverage.bats` | NEW — guard against future var drift |

---

## Rules

- `bash -n scripts/plugins/argocd.sh` — clean
- `shellcheck -S warning scripts/plugins/argocd.sh` — zero NEW warnings
- `bats scripts/tests/plugins/appset_envsubst_coverage.bats` — 2/2 pass
- `bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats` — `15/15`, unchanged
- `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` — `5/5`, unchanged
- `./scripts/k3d-manager _agent_audit` — exit 0
- Disappearance gate:
  `grep -c "envsubst '\$ARGOCD_NAMESPACE \$K3D_MANAGER_BRANCH \$APP_CLUSTER_NAME'" scripts/plugins/argocd.sh` → **`0`**
- No other files touched

---

## Definition of Done

- [ ] `argocd.sh` derives the envsubst list per file
- [ ] New BATS guard passes 2/2
- [ ] All listed pre-existing suites still pass unchanged
- [ ] `git show --stat` shows exactly TWO files changed
- [ ] shellcheck + `bash -n` + `_agent_audit` clean
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(argocd): derive appset envsubst vars per file to stop version drift
```

---

## What NOT to Do

- Do NOT switch to bare `envsubst` with no allow-list. ApplicationSet files contain Go
  templates (`{{.name}}`) and an unrestricted envsubst would mangle any `$`-bearing literal.
- Do NOT "fix" this by appending `$AMBIENT_ISTIO_VERSION` to the hardcoded list. That
  repeats the defect for the next variable — the point is to stop maintaining the list by hand.
- Do NOT edit any file in `scripts/etc/argocd/applicationsets/`.
- Do NOT re-apply anything to a live cluster — Claude does live verification, not agents.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (do NOT delegate)

After the fix lands, Claude re-runs the bootstrap appset deploy against the hub and confirms
`istio-ambient`'s `targetRevision` resolves to a real version and the three
`istio-*-ubuntu-hostinger` Applications leave `Unknown`.
