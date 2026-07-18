# Bug: Grafana dashboards are imperative — do not survive a cluster rebuild

**Branch:** `k3d-manager-v1.16.0`
**Scope:** Phase 1 only — ADDITIVE. Do not delete any existing imperative apply.

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this is the
  "ArgoCD-managed Grafana dashboards" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read these files IN FULL before editing:
  - `scripts/etc/argocd/applicationsets/observability-acg.yaml` (the app-cluster appset model)
  - `scripts/etc/argocd/applicationsets/data-git.yaml` (the `clusters` generator + `path` model)
  - `scripts/etc/argocd/applicationsets/observability.yaml` (the hub appset model)
  - `scripts/plugins/observability.sh` (lines 1–17 hub apply block, 313–333 acg apply block)
- Implement exactly what is written — no interpretation, no extra refactors.

---

## Problem

Every Grafana dashboard reaches its cluster through a `kubectl apply` in a shell plugin:

| Dashboard | Applied by |
|---|---|
| `k3dm-deployment-metrics` | `observability.sh` `_deploy_pushgateway_acg` |
| `trivy-security-dashboard` | `observability.sh` `_observability_apply_trivy_dashboard` |
| `grafana-dashboard-argocd` | `observability.sh` `_observability_apply_argocd_dashboard` **and** `argocd.sh:1390` |

Nothing reconciles them. Verified live on `ubuntu-k3s` 2026-07-18: the observability
stack carries `argocd.argoproj.io/tracking-id` but **no ArgoCD exists on any cluster** and
there is no Helm release — the stack is orphaned. Any dashboard lost to a rebuild stays
lost until a human re-runs a deploy function.

**Root cause:** dashboards are not in the ArgoCD-managed set, so they have no reconciler.

---

## Fix

Add two ApplicationSets that sync the dashboard manifests from git. Both use
`prune: true` + `selfHeal: true`, so a rebuilt cluster re-materialises its dashboards with
no human step.

### Change 1 — NEW file `scripts/etc/argocd/applicationsets/grafana-dashboards-acg.yaml`

App clusters. Uses the `clusters` generator so **every** cluster registered with
`k3d-manager/role: app-cluster` is covered automatically — including `ubuntu-hostinger`
once it is rebuilt and registered. No per-cluster edit is ever needed.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: grafana-dashboards-acg
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    managed-by: k3d-manager
    app-type: observability
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            k3d-manager/role: app-cluster
  goTemplate: true
  goTemplateOptions:
    - missingkey=error
  template:
    metadata:
      name: '{{.name}}-grafana-dashboards'
      labels:
        app-type: observability
    spec:
      project: platform
      destination:
        name: '{{.name}}'
        namespace: monitoring
      source:
        repoURL: https://github.com/wilddog64/k3d-manager
        targetRevision: '${K3D_MANAGER_BRANCH}'
        path: scripts/etc/grafana/dashboards
        directory:
          recurse: false
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: false
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
```

### Change 2 — NEW file `scripts/etc/argocd/applicationsets/grafana-dashboards-hub.yaml`

Hub only. The hub dashboard lives in `platform-ops/` alongside CronJobs, RBAC and
PrometheusRules — so this uses `directory.include` to sync **only** the dashboard file.
Do NOT move `grafana-dashboard-argocd.yaml`; `argocd.sh:1390` and four BATS suites
reference its current path.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: grafana-dashboards-hub
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    managed-by: k3d-manager
    app-type: observability
spec:
  generators:
    - list:
        elements:
          - name: hub-grafana-dashboards
  goTemplate: true
  template:
    metadata:
      name: '{{.name}}'
      labels:
        app-type: observability
    spec:
      project: platform
      destination:
        server: https://kubernetes.default.svc
        namespace: monitoring
      source:
        repoURL: https://github.com/wilddog64/k3d-manager
        targetRevision: '${K3D_MANAGER_BRANCH}'
        path: scripts/etc/argocd/platform-ops
        directory:
          recurse: false
          include: 'grafana-dashboard-argocd.yaml'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
          allowEmpty: false
        syncOptions:
          - CreateNamespace=true
          - ServerSideApply=true
```

### Change 3 — `scripts/plugins/observability.sh`: apply the hub appset

In `deploy_observability()`, immediately AFTER the existing hub `if envsubst ... fi` block
(the one ending with `return 1` / `fi` at line ~17), insert:

```bash
  local _dash_appset="${SCRIPT_DIR}/etc/argocd/applicationsets/grafana-dashboards-hub.yaml"
  # shellcheck disable=SC2016
  if envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH' < "${_dash_appset}" | _kubectl apply -f -; then
    _info "[observability] Hub Grafana dashboard ApplicationSet applied"
  else
    _err "[observability] Failed to apply Hub Grafana dashboard ApplicationSet"
    return 1
  fi
```

### Change 4 — `scripts/plugins/observability.sh`: apply the app-cluster appset

In `deploy_observability_acg()`, immediately AFTER the existing acg
`if envsubst ... fi` block (the one logging `ACG ApplicationSet applied`), insert:

```bash
  local _dash_appset="${SCRIPT_DIR}/etc/argocd/applicationsets/grafana-dashboards-acg.yaml"
  # shellcheck disable=SC2016
  if envsubst '$ARGOCD_NAMESPACE $K3D_MANAGER_BRANCH' < "${_dash_appset}" | _kubectl apply -f -; then
    _info "[observability] App-cluster Grafana dashboard ApplicationSet applied"
  else
    _err "[observability] Failed to apply app-cluster Grafana dashboard ApplicationSet"
    return 1
  fi
```

Note: the acg appset block exports `APP_CLUSTER_NAME` too, but this appset does not use
it — keep the `envsubst` allowlist to exactly the two variables shown.

### Change 5 — NEW test `scripts/tests/plugins/grafana_dashboard_appsets.bats`

```bash
#!/usr/bin/env bats

ACG="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/grafana-dashboards-acg.yaml"
HUB="${BATS_TEST_DIRNAME}/../../etc/argocd/applicationsets/grafana-dashboards-hub.yaml"
PLUGIN="${BATS_TEST_DIRNAME}/../../plugins/observability.sh"

@test "acg dashboard appset targets app-cluster role" {
  run yq -r '.spec.generators[0].clusters.selector.matchLabels["k3d-manager/role"]' "${ACG}"
  [ "$status" -eq 0 ]
  [ "$output" = "app-cluster" ]
}

@test "acg dashboard appset syncs the dashboards directory" {
  run yq -r '.spec.template.spec.source.path' "${ACG}"
  [ "$output" = "scripts/etc/grafana/dashboards" ]
}

@test "hub dashboard appset includes only the argocd dashboard" {
  run yq -r '.spec.template.spec.source.directory.include' "${HUB}"
  [ "$output" = "grafana-dashboard-argocd.yaml" ]
}

@test "both dashboard appsets self-heal" {
  run yq -r '.spec.template.spec.syncPolicy.automated.selfHeal' "${ACG}"
  [ "$output" = "true" ]
  run yq -r '.spec.template.spec.syncPolicy.automated.selfHeal' "${HUB}"
  [ "$output" = "true" ]
}

@test "observability plugin applies both dashboard appsets" {
  run grep -c 'grafana-dashboards-\(acg\|hub\).yaml' "${PLUGIN}"
  [ "$output" = "2" ]
}
```

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/applicationsets/grafana-dashboards-acg.yaml` | NEW — app-cluster dashboards appset |
| `scripts/etc/argocd/applicationsets/grafana-dashboards-hub.yaml` | NEW — hub dashboard appset |
| `scripts/plugins/observability.sh` | +2 apply blocks (hub + acg) |
| `scripts/tests/plugins/grafana_dashboard_appsets.bats` | NEW — 5 tests |

---

## Rules

- `bash -n scripts/plugins/observability.sh` — clean
- `shellcheck -S warning scripts/plugins/observability.sh` — zero NEW warnings
- `yq eval '.' <each new yaml>` — parses
- `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` — 5/5 pass
- `bats scripts/tests/lib/observability.bats scripts/tests/plugins/trivy_operator_observability.bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats scripts/tests/plugins/observability_no_exit_remove.bats`
  — **all must still pass unchanged.** These assert the imperative applies. If any fails,
  you deleted something you were told to keep — revert it.
- `./scripts/k3d-manager _agent_audit` — exit 0
- No other files touched

---

## Definition of Done

- [ ] Both ApplicationSet files exist and parse
- [ ] `observability.sh` applies both, each guarded by its own `if/else/fi`
- [ ] New BATS suite passes 5/5
- [ ] The four pre-existing observability BATS suites still pass — zero edits to them
- [ ] `grep -c '_observability_apply_trivy_dashboard' scripts/plugins/observability.sh` → `2`
      (proves the imperative path was NOT removed)
- [ ] shellcheck + `bash -n` + `_agent_audit` clean
- [ ] Committed and pushed to `k3d-manager-v1.16.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
feat(observability): manage Grafana dashboards via ArgoCD ApplicationSets
```

---

## What NOT to Do

- Do NOT remove or modify any existing `kubectl apply` of a dashboard — Phase 1 is additive.
  The imperative path is the bootstrap fallback for a cluster that has no ArgoCD yet.
- Do NOT move or rename `grafana-dashboard-argocd.yaml` — `argocd.sh:1390` and four BATS
  suites reference its path.
- Do NOT edit any existing BATS file.
- Do NOT add a `loki` datasource or any panel — this task is delivery only, not content.
- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files outside the four listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`

---

## Claude-only (NOT Codex)

- Live-apply both appsets after the ArgoCD hub is rebuilt; confirm each Application reaches
  `Synced/Healthy`.
- Confirm `ubuntu-hostinger` is registered with label `k3d-manager/role: app-cluster` — the
  `clusters` generator picks it up only if that label is present on its cluster Secret.
- Phase 2 (separate spec, later): remove the imperative applies and retarget the four BATS
  suites, once ArgoCD delivery is proven across a full rebuild of both app clusters.
