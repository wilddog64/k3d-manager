# Bug: PR Checks Check duration legend is clipped

**Filed:** 2026-10-19 (operator screenshots)
**Branch:** k3d-manager-v1.43.5
**Status:** LIVE-VERIFIED — 2026-10-20: operator screenshot after Argo CD sync shows the multi-series legend fully readable in the right-side list.
**Priority:** P3
**Fix commit:** `a5edc7ac`
**Live evidence:** 2026-10-20 · run operator-screenshot-pr-checks-duration-legend · env hub-grafana · scenario multi-series-check-duration-legend · commit 6385c3c6 · proves fix
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

The bottom legend exceeded the available panel height for the number of active series. The fix moves the list to the right of the plot. The operator's post-sync screenshot confirms the series names are readable and the chart remains visible.

## Expected behavior

Every plotted check-duration series remains identifiable. The legend must be fully readable or provide a deliberate compact/scrollable layout without obscuring the chart or changing the metric query.

## Acceptance

- [x] Panel 8 legend is fully readable with the current multi-series PR/check data.
- [ ] The chart remains usable with zero, one, and many duration series.
- [x] The `k3dm_pr_check_duration_seconds` query and `repo` filter remain unchanged.
- [x] The operator's post-sync live screenshot confirms no legend clipping with many series.

## Offline verification — 2026-10-20

- Dispatched as `pr-checks-legend-clipped`; dispatcher reported `exited successfully`, `scope: in-scope`, and landed commit `a5edc7ac` on `k3d-manager-v1.43.5`.
- `bats scripts/tests/plugins/grafana_dashboard_pr_checks.bats`: 5/5 passed, including the new assertion for a right-side legend and unchanged query/legend format.
- `shellcheck -x scripts/tests/plugins/grafana_dashboard_pr_checks.bats` and `git diff --check`: clean.
- The dashboard configuration places the legend at the right side of panel 8 as a list. Live screenshot evidence confirms the multi-series case; zero- and one-series layouts were not separately exercised.
