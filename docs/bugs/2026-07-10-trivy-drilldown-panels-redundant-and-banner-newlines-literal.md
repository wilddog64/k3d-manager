# Bugfix: v1.14.0 — Trivy drilldown banner renders literal `\n\n` and three tables show the same data

**Branch:** `k3d-manager-v1.14.0`
**Files:** `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`, `scripts/tests/plugins/argocd_metrics_servicemonitor.bats`

---

## Problem

Three defects in the Trivy section of the hub dashboard, all visible in one screenshot:

1. **The banner heading renders `### Trivy drilldown\n\nThe tables below…` as one literal line.** The `\n\n` shows up as text instead of a paragraph break.
2. **Two banner panels say the same thing.** Panel `10` ("Trivy Drilldown") and panel `15` ("Trivy Drilldown Banner") both open with `### Trivy drilldown`. Panel `10` still claims the drilldown is "at the bottom of the dashboard," which was true before panel `15` was added.
3. **Three drilldown tables carry two tables' worth of data.** Panel `18` is the set union of panels `16` and `17`. Every row in `16` and `17` also appears in `18`.

There is also a dead link: panels `13`, `14`, `16`, and `17` all deep-link to `?viewPanel=16`, which is the *namespaced Role* table — not the combined findings table. The combined table (`18`) has no link pointing at it.

**Root cause (defect 1):** the dashboard JSON is embedded in a YAML **literal block scalar** (`argocd-image-updater-hub.json: |`, line 10). A block scalar passes bytes through verbatim — it does not process escapes. So `\\n` reaches the JSON parser as an escaped backslash, decodes to the two characters `\` and `n`, and Grafana's markdown renderer prints them. The string must be written `\n`, exactly as the JSON layer expects.

**Root cause (defects 2 and 3):** panel `15` and panel `18` were added by `docs/bugs/2026-07-08-trivy-infra-panels-need-object-level-drilldown.md` without removing the panels they superseded.

---

## Reproduction

```bash
# Defect 1 — the escape is doubled in the source
grep -c 'Trivy drilldown\\\\n\\\\n' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml
# actual:   2
# expected: 0

# Defects 2/3 — duplicate banners and redundant tables
grep -c '### Trivy drilldown' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml
# actual:   2
# expected: 1
```

Open the dashboard in Grafana. The "Trivy Drilldown Banner" heading reads `### Trivy drilldown\n\nThe tables below now include…` on a single line. Below it, "Trivy Infra RBAC Drilldown", "Trivy ClusterRole Drilldown", and "Trivy Infra Findings Drilldown" show the same rows twice.

**Verified against the live PromQL.** Panel `18`'s expression is literally panel `16`'s expression `or` panel `17`'s expression, with a `source` label stamped on each branch. It is a strict superset.

---

## Fix

Keep panel `18` — it is the only one carrying the `source` column that distinguishes a namespaced Role from a ClusterRole. Delete panels `10`, `16`, and `17`. Retarget the deep-links to `?viewPanel=18`. Fix the escape and rewrite the banner text so it no longer overclaims.

> **On the banner text:** the current copy says the tables "include a description/reason column … so the dashboard explains why each row is present." They do not. The `reason` column is a hardcoded constant — `label_replace(…, "reason", "Trivy RBAC finding: review namespace-scoped permissions for this Role", …)` stamps the identical string onto every row. The real per-check reason (`AVD-KSV-0041 Manage secrets`) lives in the report's `.report.checks[].title` and never reaches Prometheus. The new copy states what the columns actually mean. Making `reason` real is out of scope here — see `docs/bugs/2026-07-09-trivy-finding-ownership-classification-and-fixed-state.md`.

### Change 1 — `grafana-dashboard-argocd.yaml`: replace the whole Trivy panel region

**Exact old block (lines 215–402):**

```json
        {
          "fieldConfig": { "defaults": {}, "overrides": [] },
          "gridPos": { "h": 4, "w": 24, "x": 0, "y": 36 },
          "id": 10,
          "options": {
            "content": "### Trivy drilldown\\n\\nThe panels below show the current security posture and include a focused findings drilldown at the bottom of the dashboard.",
            "mode": "markdown"
          },
          "title": "Trivy Drilldown",
          "type": "text"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": {}, "overrides": [] },
          "gridPos": { "h": 4, "w": 6, "x": 0, "y": 40 },
          "id": 11,
```

…through the close of panel `18` at line 402:

```json
          "title": "Trivy Infra Findings Drilldown",
          "type": "table"
        }
```

**Exact new block** (replaces lines 215–402 in full):

```json
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": {}, "overrides": [] },
          "gridPos": { "h": 4, "w": 6, "x": 0, "y": 36 },
          "id": 11,
          "options": {
            "colorMode": "value",
            "graphMode": "none",
            "justifyMode": "center",
            "orientation": "auto",
            "reduceOptions": {
              "calcs": ["lastNotNull"],
              "fields": "",
              "values": false
            },
            "textMode": "value"
          },
          "targets": [
            {
              "expr": "sum(increase(kube_job_status_failed{namespace=\"trivy-system\",job_name=~\"scan-.*\"}[30m]))",
              "refId": "A"
            }
          ],
          "title": "Trivy Scan Job Failures (30m)",
          "type": "stat"
        },
        {
          "datasource": { "type": "loki", "uid": "loki" },
          "fieldConfig": { "defaults": {}, "overrides": [] },
          "gridPos": { "h": 8, "w": 24, "x": 0, "y": 40 },
          "id": 12,
          "options": {
            "dedupStrategy": "none",
            "enableLogDetails": true,
            "showLabels": true,
            "showTime": true,
            "sortOrder": "Descending",
            "wrapLogMessage": false
          },
          "targets": [
            {
              "expr": "{namespace=\"trivy-system\",pod=~\"trivy-operator.*\"} | json | controller=\"job\" | msg=\"Reconciler error\"",
              "refId": "A"
            }
          ],
          "title": "Trivy Operator Job Reconcile Errors",
          "type": "logs"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": {}, "overrides": [] },
          "gridPos": { "h": 4, "w": 6, "x": 0, "y": 48 },
          "id": 13,
          "options": {
            "colorMode": "value",
            "graphMode": "none",
            "justifyMode": "center",
            "orientation": "auto",
            "reduceOptions": {
              "calcs": ["lastNotNull"],
              "fields": "",
              "values": false
            },
            "textMode": "value"
          },
          "targets": [
            {
              "expr": "sum(trivy_role_rbacassessments{severity=~\"High|Critical\"}) + sum(trivy_clusterrole_clusterrbacassessments{severity=~\"High|Critical\"})",
              "refId": "A"
            }
          ],
          "links": [
            {
              "title": "Open Trivy findings drilldown",
              "url": "?viewPanel=18",
              "targetBlank": false
            }
          ],
          "title": "Trivy Infra High/Critical Findings",
          "type": "stat"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": {}, "overrides": [] },
          "gridPos": { "h": 8, "w": 18, "x": 6, "y": 48 },
          "id": 14,
          "targets": [
            {
              "expr": "sort_desc(sum by (title,description,status) (trivy_cluster_compliance{status=\"Fail\"}) > 0)",
              "format": "table",
              "instant": true,
              "refId": "A"
            }
          ],
          "links": [
            {
              "title": "Open Trivy findings drilldown",
              "url": "?viewPanel=18",
              "targetBlank": false
            }
          ],
          "title": "Trivy Cluster Compliance Failures",
          "type": "table"
        },
        {
          "fieldConfig": { "defaults": {}, "overrides": [] },
          "gridPos": { "h": 4, "w": 24, "x": 0, "y": 56 },
          "id": 15,
          "options": {
            "content": "### Trivy drilldown\n\nOne row per High/Critical RBAC finding. The `source` column separates namespaced Roles (`rbac`) from cluster-scoped ClusterRoles (`clusterrole`). `Value` is the number of failing checks at that severity for that object, not the number of findings.",
            "mode": "markdown"
          },
          "title": "Trivy Drilldown Banner",
          "type": "text"
        },
        {
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "fieldConfig": { "defaults": {}, "overrides": [] },
          "gridPos": { "h": 8, "w": 24, "x": 0, "y": 60 },
          "id": 18,
          "targets": [
            {
              "expr": "sort_desc((label_replace(label_replace(sum by (namespace,resource_name,resource_kind,severity) (trivy_role_rbacassessments{severity=~\"High|Critical\"}) > 0, \"source\", \"rbac\", \"\", \"\"), \"reason\", \"Trivy RBAC finding: review namespace-scoped permissions for this Role\", \"resource_name\", \".*\") or label_replace(label_replace(label_replace(label_replace(sum by (name,resource_kind,severity) (trivy_clusterrole_clusterrbacassessments{severity=~\"High|Critical\"}) > 0, \"resource_name\", \"$1\", \"name\", \"(.*)\"), \"namespace\", \"cluster\", \"\", \"\"), \"source\", \"clusterrole\", \"\", \"\"), \"reason\", \"Trivy RBAC finding: review cluster-wide permissions for this ClusterRole\", \"resource_name\", \".*\")))",
              "format": "table",
              "instant": true,
              "refId": "A"
            }
          ],
          "title": "Trivy Infra Findings Drilldown",
          "type": "table"
        }
```

Net effect: panels `10`, `16`, `17` removed; `11`/`12`/`13`/`14`/`15`/`18` keep their ids; every `gridPos.y` below the deleted banner shifts up by 4; both `?viewPanel=16` links become `?viewPanel=18`; the banner `\\n\\n` becomes `\n\n`.

Panel `18`'s `expr` is **unchanged** — copy it byte-for-byte from the old file.

### Change 2 — `argocd_metrics_servicemonitor.bats`: retarget the panel assertions

**Exact old block (lines 151–193):**

```bash
@test "metrics: dashboard includes trivy infra security panels" {
  run grep -F -- 'Trivy Drilldown Banner' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'The tables below now include a description/reason column for each High or Critical finding, and they only show active non-zero findings once, so the dashboard explains why each row is present.' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra High/Critical Findings' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"title": "Open Trivy findings drilldown"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"url": "?viewPanel=16"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Cluster Compliance Failures' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc(sum by (title,description,status) (trivy_cluster_compliance{status=\"Fail\"}) > 0)' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'description' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra RBAC Drilldown' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy ClusterRole Drilldown' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra Findings Drilldown' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc(label_replace(sum by (namespace,resource_name,resource_kind,severity) (trivy_role_rbacassessments{severity=~\"High|Critical\"}) > 0, \"reason\", \"Trivy RBAC finding: review namespace-scoped permissions for this Role\", \"resource_name\", \".*\"))' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc(label_replace(label_replace(sum by (name,resource_kind,severity) (trivy_clusterrole_clusterrbacassessments{severity=~\"High|Critical\"}) > 0, \"resource_name\", \"$1\", \"name\", \"(.*)\"), \"reason\", \"Trivy RBAC finding: review cluster-wide permissions for this ClusterRole\", \"name\", \".*\"))' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc((label_replace(label_replace(sum by (namespace,resource_name,resource_kind,severity) (trivy_role_rbacassessments{severity=~\"High|Critical\"}) > 0, \"source\", \"rbac\", \"\", \"\"), \"reason\", \"Trivy RBAC finding: review namespace-scoped permissions for this Role\", \"resource_name\", \".*\") or label_replace(label_replace(label_replace(label_replace(sum by (name,resource_kind,severity) (trivy_clusterrole_clusterrbacassessments{severity=~\"High|Critical\"}) > 0, \"resource_name\", \"$1\", \"name\", \"(.*)\"), \"namespace\", \"cluster\", \"\", \"\"), \"source\", \"clusterrole\", \"\", \"\"), \"reason\", \"Trivy RBAC finding: review cluster-wide permissions for this ClusterRole\", \"resource_name\", \".*\")))' "${DASH}"
  [ "${status}" -eq 0 ]
}
```

**Exact new block:**

```bash
@test "metrics: dashboard includes trivy infra security panels" {
  run grep -F -- 'Trivy Drilldown Banner' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'One row per High/Critical RBAC finding.' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra High/Critical Findings' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"title": "Open Trivy findings drilldown"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- '"url": "?viewPanel=18"' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Cluster Compliance Failures' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc(sum by (title,description,status) (trivy_cluster_compliance{status=\"Fail\"}) > 0)' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'Trivy Infra Findings Drilldown' "${DASH}"
  [ "${status}" -eq 0 ]

  run grep -F -- 'sort_desc((label_replace(label_replace(sum by (namespace,resource_name,resource_kind,severity) (trivy_role_rbacassessments{severity=~\"High|Critical\"}) > 0, \"source\", \"rbac\", \"\", \"\"), \"reason\", \"Trivy RBAC finding: review namespace-scoped permissions for this Role\", \"resource_name\", \".*\") or label_replace(label_replace(label_replace(label_replace(sum by (name,resource_kind,severity) (trivy_clusterrole_clusterrbacassessments{severity=~\"High|Critical\"}) > 0, \"resource_name\", \"$1\", \"name\", \"(.*)\"), \"namespace\", \"cluster\", \"\", \"\"), \"source\", \"clusterrole\", \"\", \"\"), \"reason\", \"Trivy RBAC finding: review cluster-wide permissions for this ClusterRole\", \"resource_name\", \".*\")))' "${DASH}"
  [ "${status}" -eq 0 ]
}

@test "metrics: dashboard has exactly one trivy drilldown table and banner" {
  run grep -cF -- '### Trivy drilldown' "${DASH}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 1 ]

  run grep -F -- '"title": "Trivy Drilldown",' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy Infra RBAC Drilldown' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- 'Trivy ClusterRole Drilldown' "${DASH}"
  [ "${status}" -ne 0 ]

  run grep -F -- '"url": "?viewPanel=16"' "${DASH}"
  [ "${status}" -ne 0 ]
}

@test "metrics: dashboard banner uses real newlines not literal backslash-n" {
  run grep -F -- '\\n' "${DASH}"
  [ "${status}" -ne 0 ]
}
```

The dropped `run grep -F -- 'description' "${DASH}"` assertion was a tautology — `description` appears in panel `14`'s compliance query regardless. It is covered by the compliance-query assertion above it.

---

## Files Changed

| File | Change |
|------|--------|
| `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` | Delete panels 10/16/17, fix banner `\n` escaping, retarget links to `?viewPanel=18`, reflow `gridPos.y` |
| `scripts/tests/plugins/argocd_metrics_servicemonitor.bats` | Retarget panel assertions; add negative assertions guarding against reintroduction |

---

## Rules

- The dashboard JSON must stay valid after the edit. Verify:
  `yq -r '.data."argocd-image-updater-hub.json"' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml | jq -e . >/dev/null`
- Panel ids `11`, `12`, `13`, `14`, `15`, `18` keep their existing numbers. Do NOT renumber `18` to `16`.
- Panel `18`'s `expr` is copied verbatim from the current file. Do NOT retype it.
- No other files touched. Do NOT touch the alert rules or the ServiceMonitor.

---

## Definition of Done

- [ ] `grep -c '### Trivy drilldown' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` returns `1`
- [ ] `grep -F -- '\\n' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` returns non-zero (no matches)
- [ ] `grep -F -- '?viewPanel=16' scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` returns non-zero (no matches)
- [ ] The embedded JSON parses: `yq -r '.data."argocd-image-updater-hub.json"' … | jq -e . >/dev/null`
- [ ] `bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats` — all tests pass
- [ ] Committed and pushed to `k3d-manager-v1.14.0`
- [ ] memory-bank updated with commit SHA and task status

**Commit message (exact):**
```
fix(observability): dedupe trivy drilldown panels, fix banner newlines
```

---

## Deferred — do NOT do in this change

- **Cross-panel click-to-filter.** `"templating": { "list": [] }` — the dashboard has no variables, so no data link can filter a sibling panel. With the tables collapsed to one, there is no sibling left to correlate, which is why this is deferred rather than built. If per-`source` or per-`severity` filtering is wanted later, it needs a `templating.list` entry plus a data link of the form `?var-source=${__data.fields.source}`.
- **Unhashed ClusterRole names.** The `Value`/`resource_name` column shows `clusterrole-7c4d8f665` because `trivy_clusterrole_clusterrbacassessments` exports only the *report* name. The real object name lives in the `trivy-operator.resource.name` annotation, which is never scraped. Tracked in `docs/bugs/2026-07-09-trivy-finding-ownership-classification-and-fixed-state.md`.
- **A real per-row `reason`.** Same doc.

---

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify any file other than the two listed targets
- Do NOT commit to `main` — work on `k3d-manager-v1.14.0`
- Do NOT delete panel `18` and keep `16`/`17` instead — `18` is the only panel with the `source` column
- Do NOT add `templating` variables or alert rules in this change
