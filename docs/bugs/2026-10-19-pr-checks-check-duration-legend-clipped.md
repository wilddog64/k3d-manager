# Bug: PR Checks Check duration legend is clipped

**Filed:** 2026-10-19 (operator screenshots)
**Branch:** k3d-manager-v1.43.5
**Status:** OPEN — presentation fix not authorized
**Priority:** P3
**Severity:** low — the chart remains visible, but some series names cannot be read
**Component:** `scripts/etc/argocd/platform-ops/grafana-dashboard-pr-checks.yaml` panel 8
**Related:** `docs/bugs/2026-10-19-pr-checks-grafana-tables-misaligned-populated-state.md`

## Symptom / evidence

The **k3dm PR Checks** dashboard's **Check duration** panel shows multiple duration series, but the legend at the bottom is cut off. In the operator screenshots, the first legend rows are visible while lower check names are clipped by the panel boundary, so the chart cannot identify every plotted series.

The current panel definition is:

```json
{"id":8,"type":"timeseries","title":"Check duration","gridPos":{"h":8,"w":18,"x":0,"y":22},"fieldConfig":{"defaults":{"unit":"s"},"overrides":[]},"targets":[{"expr":"k3dm_pr_check_duration_seconds{repo=~\"$repo\"}","legendFormat":"{{repo}}#{{pr}} {{check}}"}]}
```

It uses the default Grafana legend layout, has no explicit legend configuration, and places a potentially long multi-series legend inside an eight-row panel.

## Root cause / investigation status

The likely cause is insufficient panel height for the number of legend rows. The panel has many series and the legend is placed below the plot; the current JSON does not configure a compact or scrollable legend. Confirm the exact Grafana rendering behavior against the deployed panel before choosing the fix.

## Expected behavior

Every plotted check-duration series remains identifiable. The legend must be fully readable or provide a deliberate compact/scrollable layout without obscuring the chart or changing the metric query.

## Acceptance

- [ ] Panel 8 legend is fully readable with the current multi-series PR/check data.
- [ ] The chart remains usable with zero, one, and many duration series.
- [ ] The `k3dm_pr_check_duration_seconds` query and `repo` filter remain unchanged unless evidence requires otherwise.
- [ ] A live screenshot or rendered panel inspection confirms no legend clipping after sync.
