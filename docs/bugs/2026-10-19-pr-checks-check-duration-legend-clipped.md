# Bug: PR Checks Check duration legend is clipped

**Filed:** 2026-10-19 (operator screenshots)
**Branch:** k3d-manager-v1.43.5
**Status:** VERIFIED — 2026-10-20: the legend is configured as a right-side list; focused dashboard BATS tests pass. Live Grafana verification after sync remains pending.
**Priority:** P3
**Fix commit:** `a5edc7ac`
**Severity:** low — the chart remains visible, but some series names cannot be read
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml` panel 8
**Related:** `docs/bugs/2026-10-19-pr-checks-grafana-tables-misaligned-populated-state.md`

## Files

- `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml`
- `scripts/tests/plugins/grafana_dashboard_pr_checks.bats`

## Symptom / evidence

The **k3dm PR Checks** dashboard's **Check duration** panel shows multiple duration series, but the legend at the bottom is cut off. In the operator screenshots, the first legend rows are visible while lower check names are clipped by the panel boundary, so the chart cannot identify every plotted series.

The current panel definition is:

```json
{"id":8,"type":"timeseries","title":"Check duration","gridPos":{"h":8,"w":18,"x":0,"y":22},"fieldConfig":{"defaults":{"unit":"s"},"overrides":[]},"targets":[{"expr":"k3dm_pr_check_duration_seconds{repo=~\"$repo\"}","legendFormat":"{{repo}}#{{pr}} {{check}}"}]}
```

It uses the default Grafana legend layout, has no explicit legend configuration, and places a potentially long multi-series legend inside an eight-row panel.

The operator supplied another live screenshot on 2026-10-20 showing the final legend row clipped at the bottom edge of the Check duration panel in Safari private browsing. Chrome also shows the legend crowded at the panel boundary. Keep the query and Repo filter unchanged while investigating the layout.

## Root cause / investigation status

The likely cause is insufficient panel height for the number of legend rows. The panel has many series and the legend is placed below the plot; the current JSON does not configure a compact or scrollable legend. Confirm the exact Grafana rendering behavior against the deployed panel before choosing the fix.

## Expected behavior

Every plotted check-duration series remains identifiable. The legend must be fully readable or provide a deliberate compact/scrollable layout without obscuring the chart or changing the metric query.

## Acceptance

- [ ] Panel 8 legend is fully readable with the current multi-series PR/check data (operator live verification pending).
- [ ] The chart remains usable with zero, one, and many duration series.
- [x] The `k3dm_pr_check_duration_seconds` query and `repo` filter remain unchanged.
- [ ] A live screenshot or rendered panel inspection confirms no legend clipping after sync.

## Offline verification — 2026-10-20

- Dispatched as `pr-checks-legend-clipped`; dispatcher reported `exited successfully`, `scope: in-scope`, and landed commit `a5edc7ac` on `k3d-manager-v1.43.5`.
- `bats scripts/tests/plugins/grafana_dashboard_pr_checks.bats`: 5/5 passed, including the new assertion for a right-side legend and unchanged query/legend format.
- `shellcheck -x scripts/tests/plugins/grafana_dashboard_pr_checks.bats` and `git diff --check`: clean.
- The dashboard configuration now places the legend at the right side of panel 8 as a list. This is offline verification only; confirm the rendered panel in Grafana after deployment before closing the live acceptance items.
