# Bugfix: 2026-07-18 — split trivy panels to app-cluster Grafana + fix k3dm dashboard flicker

**Branch:** `k3d-manager-v1.16.0`
**Files:**
- `scripts/etc/grafana/dashboards/trivy-security-configmap.yaml` (NEW)
- `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` (remove trivy panels)
- `scripts/plugins/observability.sh` (apply new dashboard to app cluster)
- `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` (flicker fix)
- `scripts/tests/plugins/trivy_operator_observability.bats` (update dashboard assertions)

---

## Before You Start

- Read `memory-bank/activeContext.md` and `memory-bank/progress.md` — this task is the
  "trivy dashboard split + k3dm flicker" item on branch `k3d-manager-v1.16.0`.
- `git pull origin k3d-manager-v1.16.0` — work on that branch, never `main`.
- Read every target file listed above IN FULL before editing:
  - `scripts/etc/grafana/dashboards/k3dm-deployments-configmap.yaml` (the model for Change 1's structure)
  - `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` (source of the panels to copy/remove)
  - `scripts/plugins/observability.sh` (lines ~336 remove-call, ~415 k3dm apply block)
  - `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` (the `grafana:` block, line ~17)
  - `scripts/tests/plugins/trivy_operator_observability.bats`
- Implement exactly what is written — no interpretation, no extra refactors.

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
- **Panels:** copy these panel objects VERBATIM (JSON, exprs, `datasource`, and `gridPos`
  `h`/`w`/`x`) from `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`'s embedded
  `argocd-image-updater-hub.json`. **The ONLY field you may change is `gridPos.y`** — set it to
  these exact values so the panels stack from the top with no gap (the originals start at y=36
  and straddle the removed loki panel):

  | panel id | title | keep h/w/x | NEW `gridPos.y` |
  |---|---|---|---|
  | 11 | Trivy Scan Job Failures (30m) | h=4 w=6 x=0 | **0** |
  | 13 | Trivy Infra High/Critical Findings | h=4 w=6 x=0 | **4** |
  | 14 | Trivy Cluster Compliance Failures | h=8 w=18 x=6 | **4** |
  | 15 | Trivy Drilldown Banner | h=4 w=24 x=0 | **12** |
  | 18 | Trivy Infra Findings Drilldown | h=8 w=24 x=0 | **16** |

  (13 and 14 share y=4 side-by-side, exactly as they do today.) Panel list, for reference:
  - id `13` **Trivy Infra High/Critical Findings** (`sum(trivy_role_rbacassessments{severity=~"High|Critical"}) + sum(trivy_clusterrole_clusterrbacassessments{severity=~"High|Critical"})`)
  - id `14` **Trivy Cluster Compliance Failures** (`sort_desc(sum by (title,description,status) (trivy_cluster_compliance{status="Fail"}) > 0)`)
  - id `15` **Trivy Drilldown Banner** (text panel)
  - id `18` **Trivy Infra Findings Drilldown** (the `label_replace(...)` rbac/clusterrole table)
  - id `11` **Trivy Scan Job Failures (30m)** (`sum(increase(kube_job_status_failed{namespace="trivy-system",job_name=~"scan-.*"}[30m]))`)
- **Loki panel id `12` — OMIT (confirmed 2026-07-18).** Panel id `12` **Trivy Operator Job Reconcile
  Errors** is a Loki `logs` panel. The app-cluster (ubuntu-k3s) Grafana has **NO `loki` datasource**
  — only `prometheus` (uid `prometheus`, default) + `alertmanager` (verified via
  `/api/datasources`). So a Loki panel would render "Datasource loki not found". **Do NOT include
  panel 12** in the new dashboard. (Follow-up, OUT of scope here: the app-cluster Grafana is missing
  a `loki` datasource entirely — every log panel is dead there; file separately if log panels are
  wanted on the app cluster.)
- **Datasource uid — verified present:** the moved metric panels hard-code
  `datasource: { type: prometheus, uid: "prometheus" }`, and the app-cluster Grafana's default
  Prometheus datasource uid is exactly `prometheus` — so the panels resolve and return data
  (verified live: Trivy Infra High/Critical = 45, Cluster Compliance Fail = 4, RBAC findings = 38).
- Reuse the panels' existing `datasource` uids exactly (`prometheus` for the metric panels; panel
  15 is a text panel with `"datasource": null` — keep it null). Do not invent new uids.
- **⚠️ TRAP — do NOT retarget to `prometheus-acg`.** `kube-prometheus-stack-acg-values.yaml`
  defines an `additionalDataSources` entry named `prometheus-acg` with uid `P5A1115AEDF367D43`.
  That is an *additional* datasource, NOT the default. The app-cluster Grafana's **default**
  Prometheus uid is `prometheus` (verified live via `/api/datasources`), which is what these
  panels already reference and what returns data. Because the new dashboard targets the "acg"
  cluster it is tempting to switch the uid to `prometheus-acg` — **do not.** Leave every
  `datasource.uid` exactly as copied.

### Change 2 — `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`: remove the moved panels

Delete panel objects `id 11, 13, 14, 15, 18` (the Prometheus-based Trivy panels — the ones being
moved to the app cluster) from the embedded `argocd-image-updater-hub.json`.

**KEEP** panel `id 12` (**Trivy Operator Job Reconcile Errors**) on the hub dashboard — it is a Loki
panel and the hub Grafana has a Loki datasource (the app cluster does not), so it works on the hub
and would be lost if removed. **KEEP** panels `1–9` (Image Updater + Watched App + App CVE Scan) —
hub-only metrics (`argocd_app_info`, `argocd_app_sync_total`, image-updater deployment, `app-cve-scan`
jobs). Ensure the resulting JSON is still valid (no dangling commas) and the dashboard `uid`/`title`
are unchanged (`uid: argocd-image-updater-hub`, `title: ArgoCD Apps & Image Updater Hub`).

**Close the layout gap:** panel 11 currently occupies `y=36..40` and panel 12 sits at `y=40`.
Once panel 11 is removed, panels 1–9 end at `y=36` and panel 12 leaves a 4-row hole. Set the
retained panel 12's `gridPos.y` from `40` → **`36`**. This is the ONLY gridPos edit permitted in
this file; leave panels 1–9 untouched.

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

### Change 3b — `scripts/tests/plugins/trivy_operator_observability.bats`: retarget the moved assertions

**This test WILL FAIL if not updated** — it currently asserts panel 11's title and expr live in the
hub dashboard, and panel 11 is being moved out. Exact required changes to the
`@test "trivy observability: dashboard exposes log and metric panels for trivy-system"` block
(lines ~55–67):

Add a second path var next to the existing `DASH` (line 7):

```bash
TRIVY_DASH="${BATS_TEST_DIRNAME}/../../etc/grafana/dashboards/trivy-security-configmap.yaml"
```

Then, within that test:

| line | assertion | action |
|---|---|---|
| 56 | `'Trivy Scan Job Failures (30m)'` | **retarget** `"${DASH}"` → `"${TRIVY_DASH}"` (panel 11 moved) |
| 59 | `'Trivy Operator Job Reconcile Errors'` | **leave on `"${DASH}"`** (panel 12 stays on hub) |
| 62 | the `controller=\"job\" \| msg=\"Reconciler error\"` loki expr | **leave on `"${DASH}"`** (panel 12) |
| 65 | the `kube_job_status_failed{namespace=\"trivy-system\",...}` expr | **retarget** → `"${TRIVY_DASH}"` (panel 11 moved) |

Also add one new disappearance assertion in the same test, proving the split actually happened:

```bash
  run grep -F -- 'Trivy Cluster Compliance Failures' "${DASH}"
  [ "$status" -ne 0 ]
  run grep -F -- 'Trivy Cluster Compliance Failures' "${TRIVY_DASH}"
  [ "$status" -eq 0 ]
```

Do NOT touch any other test in this file (the chart-pin, serviceMonitor, builtInTrivyServer,
appset, and prometheus-rule tests are all out of scope).

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
| `scripts/etc/grafana/dashboards/trivy-security-configmap.yaml` | NEW app-cluster trivy dashboard (Prometheus panels 11,13,14,15,18; NO loki panel — app cluster has no loki datasource) |
| `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` | remove trivy panels 11,13,14,15,18 (KEEP panel 12 loki + panels 1–9) |
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
- **Structural panel-split gate (authoritative — run this; the greps above are only a smoke check).**
  Verifies exact panel ids AND the prescribed `gridPos.y` in both files:

  ```bash
  python3 - <<'PY'
  import json,subprocess,sys
  def load(f,k):
      return json.loads(subprocess.run(['yq','-r','.data["%s"]'%k,f],
                        capture_output=True,text=True,check=True).stdout)
  hub=load('scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml','argocd-image-updater-hub.json')
  new=load('scripts/etc/grafana/dashboards/trivy-security-configmap.yaml','trivy-security.json')
  hub_ids=sorted(p['id'] for p in hub['panels'])
  new_ids=sorted(p['id'] for p in new['panels'])
  hub_y={p['id']:p['gridPos']['y'] for p in hub['panels']}
  new_y={p['id']:p['gridPos']['y'] for p in new['panels']}
  ok=True
  if hub_ids!=[1,2,3,4,5,6,7,8,9,12]: print("FAIL hub ids",hub_ids);ok=False
  if new_ids!=[11,13,14,15,18]:       print("FAIL new ids",new_ids);ok=False
  if hub_y.get(12)!=36:               print("FAIL hub panel12 y",hub_y.get(12));ok=False
  if new_y!={11:0,13:4,14:4,15:12,18:16}: print("FAIL new y",new_y);ok=False
  if hub['uid']!='argocd-image-updater-hub': print("FAIL hub uid changed");ok=False
  if new['uid']!='trivy-security':    print("FAIL new uid",new.get('uid'));ok=False
  bad=[p['id'] for p in new['panels']
       if isinstance(p.get('datasource'),dict) and p['datasource'].get('uid')!='prometheus']
  if bad: print("FAIL non-prometheus datasource on panels",bad);ok=False
  print("PASS" if ok else "FAILED"); sys.exit(0 if ok else 1)
  PY
  ```
  Must print `PASS` and exit 0.
- `grep -c '_observability_apply_trivy_dashboard' scripts/plugins/observability.sh` → **2** (definition + call).
- `grep -c 'disableDelete: true' scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` → **1**.
- `bats scripts/tests/plugins/trivy_operator_observability.bats` — passes.
- `./scripts/k3d-manager _agent_audit` — exit 0.

---

## Definition of Done

- [ ] New app-cluster trivy dashboard configmap created; Prometheus panels 11,13,14,15,18 copied
      verbatim; loki panel 12 OMITTED (confirmed 2026-07-18 — app cluster has no loki datasource).
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
