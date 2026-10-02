# Bug: "Grafana Health & Firing Alerts" has no tags and no fixed uid

**Filed:** 2026-10-02
**Status:** FIXED `86f21788` (Codex, Claude-verified: 32/32 grafana_dashboard_appsets bats, hub-copy uid-removal mutation red, both copies uid+tags); LIVE 2026-10-02 (hub-grafana-dashboards auto-synced 86f21788, ConfigMap carries uid k3dm-grafana-health)
**Branch:** `k3d-manager-v1.41.0`
**Found by:** operator, 2026-10-02. After the retitle went live, the dashboard showed no tag chips in the Dashboards list; the other k3dm dashboards do have them.
**Related:** `docs/bugs/2026-10-02-grafana-overview-readable-title-collides-with-stock-dashboard.md`

## Symptom

The Dashboards list shows `Grafana Health & Firing Alerts` with no tags. It can't be found with a tag filter, and its URL changed on the rename because Grafana generates a uid when the JSON has none.

## Root cause

Both copies were derived from the chart's stock `grafana-overview.json`, which has no `tags` and no `uid`. Parsed JSON for both files: `{"tags": null, "uid": null}`. Every other k3dm dashboard sets both, for example `grafana-dashboard-alertmanager-delivery.yaml` → `uid: k3dm-alertmanager-delivery`, `tags: ["alertmanager","k3d-manager","notifications"]`.

The guide row added in `9ccfcccd` also says the hub copy is deployed by `make platform-ops`. That is wrong: the ArgoCD app `hub-grafana-dashboards` owns it (verified live 2026-10-02).

## Fix

### S1: `scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml`

Old:
```
      "time": {"from": "now-6h", "to": "now"},
      "timezone": "utc",
      "title": "Grafana Health & Firing Alerts",
      "version": 1
```
New:
```
      "tags": ["grafana", "alerts", "k3d-manager"],
      "time": {"from": "now-6h", "to": "now"},
      "timezone": "utc",
      "title": "Grafana Health & Firing Alerts",
      "uid": "k3dm-grafana-health",
      "version": 1
```

### S2: `scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml`

Old:
```
      "time": {"from": "now-6h", "to": "now"},
      "timezone": "utc",
      "title": "Grafana Health & Firing Alerts",
      "version": 2
```
New:
```
      "tags": ["grafana", "alerts", "k3d-manager"],
      "time": {"from": "now-6h", "to": "now"},
      "timezone": "utc",
      "title": "Grafana Health & Firing Alerts",
      "uid": "k3dm-grafana-health",
      "version": 2
```

### S3: `scripts/tests/plugins/grafana_dashboard_appsets.bats`

Add this test directly after `@test "readable Overview title does not collide with the stock Grafana Overview"`:
```bash
@test "Grafana Health dashboard has a fixed uid and k3dm tags" {
  local dashboard
  for dashboard in "${OVERVIEW}" "${HUB_OVERVIEW}"; do
    run bash -c "yq -r '.data[\"grafana-overview-readable.json\"]' '$dashboard' | jq -e '.uid == \"k3dm-grafana-health\" and (.tags | index(\"k3d-manager\")) != null'"
    [ "$status" -eq 0 ]
  done
}
```

### S4: `docs/guides/grafana-dashboards.md` (the `Grafana Health & Firing Alerts` row)

Old:
```
| Grafana Health & Firing Alerts | — (no fixed uid) | `platform-ops/grafana-dashboard-overview-readable.yaml` (hub); `etc/grafana/dashboards/grafana-overview-readable-configmap.yaml` (ACG) | `make platform-ops` (hub); `grafana-dashboards-acg` ApplicationSet (ACG) | hub + **ACG** |
```
New:
```
| Grafana Health & Firing Alerts | `k3dm-grafana-health` | `platform-ops/grafana-dashboard-overview-readable.yaml` (hub); `etc/grafana/dashboards/grafana-overview-readable-configmap.yaml` (ACG) | ArgoCD app `hub-grafana-dashboards` (hub; NOT `make platform-ops`); `grafana-dashboards-acg` ApplicationSet (ACG) | hub + **ACG** |
```

## Gate (paste output)

1. `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` reports 0 failures.
2. Mutation: delete the `"uid": "k3dm-grafana-health",` line from S2's file only. The new test must FAIL. Restore the line, and confirm with `git diff --stat` that only the 4 spec files changed.
3. `yq -r '.data["grafana-overview-readable.json"]' <file> | jq -c '{uid,tags}'` prints the uid and tags for both dashboard files.
4. `grep -rnE '^[[:space:]]*! ' scripts/tests --include='*.bats'` prints nothing.
5. `git grep -n '"uid": "k3dm-grafana-health"' -- scripts/etc` shows exactly 2 lines, and no other dashboard already uses that uid.

## Definition of Done

- [ ] S1–S4 applied exactly; only these 4 files changed
- [ ] Gates 1–5 output pasted
- [ ] Commit message: `fix(grafana): give the Grafana Health dashboard a fixed uid and k3dm tags`
- [ ] Pushed to `origin/k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`

## Rollout

The AppSets already track `k3d-manager-v1.41.0` (operator reapplied them 2026-10-02), so the change goes live on the next ArgoCD sync with no operator step. The URL changes one last time, to `/d/k3dm-grafana-health`, and stays fixed after that.

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than the 4 listed
- Do NOT commit to `main`
- Do NOT edit memory-bank
