# Bugfix: 2026-07-18 — split trivy panels to app-cluster Grafana + fix k3dm dashboard flicker

**Branch:** `k3d-manager-v1.16.0`
**Files:**
- `scripts/etc/grafana/dashboards/trivy-security-configmap.yaml` (NEW)
- `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` (remove trivy panels)
- `scripts/plugins/observability.sh` (apply new dashboard to app cluster)
- `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` (flicker fix)
- `scripts/tests/plugins/trivy_operator_observability.bats` (update dashboard assertions)

---

## Problem

The public Grafana that users actually reach on `k3s-aws` is the **app-cluster (ubuntu-k3s)**
Grafana: `bin/cluster-up:1518` points `com.k3d-manager.grafana-port-forward` (`:3001`, which
`grafana.3ai-talk.org` tunnels to) at `svc/acg-kube-prometheus-stack-grafana` context `ubuntu-k3s`.

The trivy panels live in `grafana-dashboard-argocd.yaml` (uid `argocd-image-updater-hub`), which the
observability plugin applies **only to the hub** (`observability.sh:83`,
`_observability_apply_argocd_dashboard "${_hub_context}"`) and **explicitly removes from the app
cluster** (`observability.sh:336`, `_observability_remove_argocd_dashboard "${_app_context}"`).

**Net effect (verified live 2026-07-18):** on the app-cluster Grafana the trivy panels are absent,
even though the app-cluster Prometheus HAS the trivy metrics (`trivy_image_vulnerabilities` = 265
series, `trivy_resource_configaudits` = 384 series, plus `trivy_role_rbacassessments`,
`trivy_clusterrole_clusterrbacassessments`, `trivy_cluster_compliance`, scrape target `up`). So the
data is present but has no dashboard where the user looks → "trivy metric is missing".

**Decision (user, 2026-07-18):** SPLIT the dashboard. Keep `:3001` pointed at the app cluster.
Move the **trivy-operator** panels into a new, self-contained dashboard applied to the **app-cluster**
Grafana (where the trivy data + the exposed Grafana coincide). Leave the ArgoCD / Image-Updater /
App-CVE-Scan panels on the hub dashboard (they query hub-only metrics like `argocd_app_info`).

**Secondary bug — k3dm dashboard flicker:** the app-cluster Grafana provisioning provider runs with
`disableDeletion: false` (chart default; not overridden in the acg values) and the sidecar's reload
endpoint intermittently returns `Connection refused` during Grafana restarts / observability churn
(observed in `grafana-sc-dashboard` logs). When a dashboard file transiently drops from
`/tmp/dashboards`, Grafana deletes the dashboard and only re-adds it on the next 30s provisioning
scan — so `k3dm Deployment Metrics` (and any imperatively-applied dashboard) flickers in and out.

---

## Fix

### Change 1 — NEW `scripts/etc/grafana/dashboards/trivy-security-configmap.yaml`

Create a self-contained Grafana dashboard ConfigMap for the app-cluster Grafana. Model it exactly on
the EXISTING `scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml` (same
`kind: ConfigMap`, `namespace: monitoring`, `labels: { grafana_dashboard: "1" }` shape — copy that
file's metadata/label structure verbatim, only change `name:` and the embedded JSON).

- ConfigMap `metadata.name: trivy-security-dashboard`, namespace `monitoring`,
  label `grafana_dashboard: "1"`.
- Data key: `trivy-security.json`.
- Dashboard `uid: trivy-security`, `title: "Trivy Security"`, `tags: ["trivy","security"]`.
- **Panels:** copy these panel objects VERBATIM (JSON, exprs, datasources, gridPos) from
  `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`'s embedded
  `argocd-image-updater-hub.json`, renumbering `y` positions from 0 so they stack cleanly:
  - id `13` **Trivy Infra High/Critical Findings** (`sum(trivy_role_rbacassessments{severity=~"High|Critical"}) + sum(trivy_clusterrole_clusterrbacassessments{severity=~"High|Critical"})`)
  - id `14` **Trivy Cluster Compliance Failures** (`sort_desc(sum by (title,description,status) (trivy_cluster_compliance{status="Fail"}) > 0)`)
  - id `15` **Trivy Drilldown Banner** (text panel)
  - id `18` **Trivy Infra Findings Drilldown** (the `label_replace(...)` rbac/clusterrole table)
  - id `11` **Trivy Scan Job Failures (30m)** (`sum(increase(kube_job_status_failed{namespace="trivy-system",job_name=~"scan-.*"}[30m]))`)
- **Loki panel handling — VERIFY BEFORE INCLUDING:** panel id `12` **Trivy Operator Job Reconcile
  Errors** is a Loki `logs` panel (`{namespace="trivy-system",pod=~"trivy-operator.*"} | json | ...`).
  Only include it if the app-cluster Grafana has a working `loki` datasource with trivy-system logs
  (check: `kubectl --context ubuntu-k3s get datasources` via the Grafana API, or the acg values
  `additionalDataSources`). If no app-cluster Loki datasource exists, OMIT panel 12 and note it in
  the commit body — do NOT ship a panel that renders "Datasource loki not found".
- Reuse the panels' existing `datasource` uids exactly (`prometheus` for the metric panels). Do not
  invent new uids.

### Change 2 — `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`: remove the moved panels

Delete panel objects `id 11, 12, 13, 14, 15, 18` (the Trivy panels) from the embedded
`argocd-image-updater-hub.json`. **Keep** panels `1–9` (Image Updater + Watched App + App CVE Scan) —
those query hub-only metrics (`argocd_app_info`, `argocd_app_sync_total`, image-updater deployment,
`app-cve-scan` jobs) and stay on the hub dashboard. Ensure the resulting JSON is still valid
(no dangling commas) and the dashboard `uid`/`title` are unchanged.

### Change 3 — `scripts/plugins/observability.sh`: apply the trivy dashboard to the app cluster

Add a new apply helper modeled on the existing k3dm apply block (near line 415) and call it in the
app-cluster deploy flow (the same function that runs `_observability_remove_argocd_dashboard
"${_app_context}"` at line 336, and/or right after the k3dm apply). Exact new function:

```bash
function _observability_apply_trivy_dashboard() {
  local _app_context
  _app_context="$(_observability_acg_context "${1:-}")"
  local _dashboard_cm="${SCRIPT_DIR}/etc/grafana/dashboards/trivy-security-configmap.yaml"
  if [[ -f "${_dashboard_cm}" ]]; then
    _kubectl apply --context "${_app_context}" -f "${_dashboard_cm}" >/dev/null \
      && _info "[observability] Trivy security dashboard applied on ${_app_context}"
  fi
}
```

Call it in the app-cluster deploy path (same `_app_context` used by
`_observability_remove_argocd_dashboard`). Use `apply` (idempotent) — do NOT add any delete step.

### Change 4 — `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml`: stop the flicker

Under the existing `grafana:` key (line 17), set the dashboards sidecar provider to not delete
dashboards when a file transiently disappears:

```yaml
grafana:
  sidecar:
    dashboards:
      provider:
        disableDelete: true
```

Merge into the existing `grafana:` block (do not duplicate the key). This makes Grafana retain
provisioned dashboards across sidecar reload failures, eliminating the k3dm/trivy flicker. Tradeoff
(acceptable here): dashboards removed from configmaps are not auto-pruned from Grafana until a
restart — acceptable because these dashboards are configmap-managed and stable.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/grafana/dashboards/trivy-security-configmap.yaml` | NEW app-cluster trivy dashboard (panels 11,13,14,15,18[,12 if loki]) |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` | remove trivy panels 11,12,13,14,15,18 (keep 1–9) |
| `scripts/plugins/observability.sh` | add `_observability_apply_trivy_dashboard` + call it for the app cluster |
| `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` | `grafana.sidecar.dashboards.provider.disableDelete: true` |
| `scripts/tests/plugins/trivy_operator_observability.bats` | move the trivy-panel assertions to the new dashboard file; assert the argocd dashboard no longer contains them |

---

## Rules

- `bash -n scripts/plugins/observability.sh` — clean.
- `shellcheck -S warning scripts/plugins/observability.sh` — zero new warnings.
- YAML parses: `yq eval '.' scripts/etc/grafana/dashboards/trivy-security-configmap.yaml >/dev/null`
  and `yq eval '.' scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml >/dev/null`
  both exit 0. (`python3 -c "import yaml"` is NOT available — use `yq`.)
- Embedded dashboard JSON is valid: extract the `.data["trivy-security.json"]` value and
  `python3 -c "import json,sys; json.load(sys.stdin)"` exit 0; same for the edited
  `argocd-image-updater-hub.json` in the hub dashboard.
- Disappearance gate (hub dashboard no longer has the moved trivy titles):
  `grep -c 'Trivy Cluster Compliance Failures' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` → **0**.
- Presence gate (new dashboard has them):
  `grep -c 'Trivy Cluster Compliance Failures' scripts/etc/grafana/dashboards/trivy-security-configmap.yaml` → **1**.
- Kept-panel gate (hub keeps ArgoCD panels):
  `grep -c 'Watched App Health / Sync' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` → **1**.
- `grep -c '_observability_apply_trivy_dashboard' scripts/plugins/observability.sh` → **2** (definition + call).
- `grep -c 'disableDelete: true' scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` → **1**.
- `bats scripts/tests/plugins/trivy_operator_observability.bats` — passes.
- `./scripts/k3d-manager _agent_audit` — exit 0.

---

## Definition of Done

- [ ] New app-cluster trivy dashboard configmap created; panels copied verbatim (loki panel 12 only
      if an app-cluster loki datasource exists — else omitted and noted in commit body).
- [ ] Trivy panels removed from the hub dashboard; ArgoCD/Image-Updater/App-CVE panels retained;
      both embedded JSONs still valid.
- [ ] `observability.sh` applies the trivy dashboard to the app cluster (idempotent `apply`).
- [ ] `disableDelete: true` set under `grafana.sidecar.dashboards.provider` in the acg values.
- [ ] All gates pass.
- [ ] Committed and pushed to `k3d-manager-v1.16.0`.
- [ ] memory-bank updated with commit SHA and task status.

**Commit message (exact):**
```
fix(observability): split trivy panels to app-cluster Grafana + stop dashboard flicker
```

---

## What NOT to Do

- Do NOT repoint the `:3001` Grafana port-forward (`bin/cluster-up:1518`) — the split keeps `:3001`
  on the app cluster by design. (A separate hub-route parity fix is deliberately NOT in scope.)
- Do NOT `kubectl apply` / touch any live cluster — Claude runs the live verify.
- Do NOT change the dashboard `uid` of the hub dashboard (`argocd-image-updater-hub`).
- Do NOT create a PR.
- Do NOT skip pre-commit hooks (`--no-verify`).
- Do NOT modify any file outside the listed targets.
- Do NOT commit to `main` — work on `k3d-manager-v1.16.0`.

---

## Claude-only: live verify (NOT Codex)

After Codex pushes, Claude runs `make observability` (or applies the new configmap directly) against
the live app cluster, confirms `trivy-security-dashboard` configmap lands on `ubuntu-k3s` monitoring
ns, the "Trivy Security" dashboard registers in the app-cluster Grafana API with the trivy panels
populated (metrics already present: 265 + 384 series), and that `k3dm Deployment Metrics` no longer
disappears after a Grafana sidecar reload.
