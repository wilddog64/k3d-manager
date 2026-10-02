# Bug: our Overview dashboard is named so close to the stock one that the operator opens the wrong one

**Filed:** 2026-10-02
**Status:** FIXED `9ccfcccd` (Codex, Claude-verified: 31/31 grafana_dashboard_appsets bats, old title gone from scripts, hub-copy revert mutation red (tests 14+15), both JSON titles valid); LIVE 2026-10-02: operator reapplied the ApplicationSets at `k3d-manager-v1.41.0`; `hub-grafana-dashboards` Synced at `a2b0f849`, and the Grafana sidecar wrote the retitled dashboard 21:15Z
**Branch:** `k3d-manager-v1.41.0`
**Found by:** operator, 2026-10-02. They opened Dashboards → "Grafana Overview" on the hub and reported that the "Firing Alerts by Category" table was missing.
**Related:** `docs/bugs/2026-10-01-grafana-overview-raw-series-labels.md` (created the Readable copy), `docs/bugs/2026-10-02-grafana-overview-firing-alerts-and-request-rate-no-data.md`

## Symptom

The hub Grafana has two dashboards with nearly identical names (live, namespace `monitoring`):

| ConfigMap | Title | Panels |
|---|---|---|
| `kube-prometheus-stack-grafana-overview` (chart default, uid `6be0s85Mk`) | `Grafana Overview` | Firing Alerts, Dashboards, Build Info, RPS, Request Latency |
| `grafana-dashboard-overview-readable` (ours) | `Grafana Overview — Readable` | Firing Alerts (Prometheus), Grafana Dashboards Loaded, Build Info, Request Rate by HTTP Status, Request Latency, Firing Alerts by Category |

All of the fixes from 2026-10-01/02 are live, but they are all in the Readable copy. The stock dashboard sorts first and matches the name people search for, so the operator opened that one and every fix looked missing.

## Root cause

Our title starts with the stock title. We can't turn off the stock dashboard alone: the chart's `grafana.defaultDashboardsEnabled` removes every default dashboard at once (Kubernetes, Alertmanager, node). So we rename ours instead.

## Fix

New title: **`Grafana Health & Firing Alerts`**. It names what the dashboard shows and does not start with "Grafana Overview".

### S1: `scripts/etc/argocd/platform-ops/grafana-dashboard-overview-readable.yaml` (line 28)

Old:
```
      "title": "Grafana Overview — Readable",
```
New:
```
      "title": "Grafana Health & Firing Alerts",
```

### S2: `scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml` (line 97)

Same old/new as S1.

### S3: `scripts/tests/plugins/grafana_dashboard_appsets.bats`

Lines 199 and 221. Old:
```bash
  [[ "$output" == *'"title": "Grafana Overview — Readable"'* ]]
```
New:
```bash
  [[ "$output" == *'"title": "Grafana Health & Firing Alerts"'* ]]
```
Add this test directly after the `@test "hub Grafana Overview uses the same readable dashboard contract"` block:
```bash
@test "readable Overview title does not collide with the stock Grafana Overview" {
  local dashboard
  for dashboard in "${OVERVIEW}" "${HUB_OVERVIEW}"; do
    run grep -F -- '"title": "Grafana Overview' "$dashboard"
    [ "$status" -ne 0 ]
  done
}
```

### S4: `docs/guides/grafana-dashboards.md`

In the `## The seven dashboards` table, add this row directly after the `Hermes Status` row:
```
| Grafana Health & Firing Alerts | — (no fixed uid) | `platform-ops/grafana-dashboard-overview-readable.yaml` (hub); `etc/grafana/dashboards/grafana-overview-readable-configmap.yaml` (ACG) | `make platform-ops` (hub); `grafana-dashboards-acg` ApplicationSet (ACG) | hub + **ACG** |
```
At the end of the `### Which Grafana am I looking at?` section, directly before `**Check the instance before debugging the query.**`, add this paragraph:
```
The chart also ships a stock **`Grafana Overview`** dashboard (Firing Alerts, Dashboards, RPS).
It is not ours and none of our fixes apply to it. Ours is **`Grafana Health & Firing Alerts`**,
which has the "Firing Alerts by Category" table. Before 2026-10-02 it was titled
"Grafana Overview — Readable", and the operator kept opening the stock one by mistake
(`docs/bugs/2026-10-02-grafana-overview-readable-title-collides-with-stock-dashboard.md`).
```

## Gate (paste output)

1. `bats scripts/tests/plugins/grafana_dashboard_appsets.bats` reports 0 failures.
2. `git grep -n 'Grafana Overview — Readable' -- scripts` prints nothing.
3. Mutation: in S2's file only, change the title back to `Grafana Overview — Readable`. Rerun gate 1; the new collision test AND the `readable request labels` test must FAIL. Restore the file, and confirm with `git diff --stat` that only the 4 spec files changed.
4. `yq -r '.data["grafana-overview-readable.json"]' <file> | jq empty` succeeds for both dashboard files.
5. `grep -rnE '^[[:space:]]*! ' scripts/tests --include='*.bats'` prints nothing.

## Definition of Done

- [ ] S1–S4 applied exactly; only these 4 files changed
- [ ] Gates 1–5 output pasted
- [ ] Commit message: `fix(grafana): retitle the readable Overview so it no longer collides with the stock dashboard`
- [ ] Pushed to `origin/k3d-manager-v1.41.0`; report `git rev-parse origin/k3d-manager-v1.41.0`

## Rollout (operator, after merge or sync)

- Hub: `make platform-ops` does NOT apply this ConfigMap. It is owned by the ArgoCD app `hub-grafana-dashboards`, which tracks `k3d-manager-v1.40.0` (confirmed 2026-10-02: live title still the old one after `make platform-ops`). It goes live when the ApplicationSets are reapplied at `k3d-manager-v1.41.0` (the release step), or sooner if the operator reapplies them early.
- ACG: the ApplicationSet syncs it.
- Then search Dashboards for "Grafana Health". The dashboard has no fixed uid, so its URL may change.

## What NOT to Do

- Do NOT create a PR
- Do NOT skip pre-commit hooks (`--no-verify`)
- Do NOT modify files other than the 4 listed (do not rename the ConfigMaps or data keys; the ApplicationSet `exclude` matches the file name)
- Do NOT set `grafana.defaultDashboardsEnabled: false`
- Do NOT commit to `main`
- Do NOT edit memory-bank
