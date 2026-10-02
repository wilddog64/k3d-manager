# Bug: the Overview "Dashboards" stat has a title that does not say what it counts

**Status:** OPEN
**Branch:** `k3d-manager-v1.40.0`
**Files:** `scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml`,
`scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml` (keep both copies of panel 8 identical)
**Tests:** `scripts/tests/plugins/grafana_dashboard_appsets.bats`

## Symptom

The operator reported (2026-10-02) that the Overview panel titled **Dashboards**, showing `34`,
does not say what it means. Next to it, "Firing Alerts (Prometheus)" reads as a health signal,
so a bare green `34` beside it looks like a count of something healthy or unhealthy. The metric is
`grafana_stat_totals_dashboard`: how many dashboards this Grafana instance has loaded.

## Fix (panel `"id": 8`, in both files)

- `"title": "Dashboards"` → `"title": "Grafana Dashboards Loaded"`
- `"legendFormat": "Dashboards"` → `"legendFormat": "Dashboards loaded"`
- `"description": "Total dashboards currently known to this Grafana instance."` →
  `"description": "How many dashboards this Grafana instance has loaded: the provisioned ConfigMaps plus any saved in the UI. Inventory only, not a health signal. A drop after a sync means a dashboard ConfigMap stopped loading."`

Change nothing else in the panel: no change to the query, gridPos or thresholds.

## Test (append to `scripts/tests/plugins/grafana_dashboard_appsets.bats`)

Assert that both files contain `"title": "Grafana Dashboards Loaded"`, and that neither contains
`"title": "Dashboards"` (use `run !` or `|| false`, never a bare `! grep`). Follow the file's
existing style for locating the two dashboard files.

**Mutation check (must report):** revert the title in one file only, and the test goes red.

## Definition of Done

- [ ] Both copies are updated identically; `diff <(grep -o '"id": 8.*' fileA) <(grep -o '"id": 8.*' fileB)`
      gives no output (or an equivalent check that panel 8 is identical; paste it)
- [ ] `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` all green (paste the summary)
- [ ] Status line set to `FIXED (<short sha>)`
- [ ] Commit message: `fix(grafana): name the Overview dashboard-count stat for what it counts`

## What NOT to Do

- Do NOT create a PR, skip hooks, commit to `main`, or touch files outside the three listed above
  (plus this doc)
