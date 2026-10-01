# Bug: Grafana Overview uses opaque raw series labels

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-10-01
**Status:** FIXED (`487b0a43`)
**Severity:** low — the dashboard is functional, but its legends and panel descriptions make the
HTTP status and latency series difficult to interpret.

## Evidence

The Overview dashboard displays raw status-code labels such as `-1`, `200`, `401`, `404`, and
`503`, and generic percentile labels such as `99th Percentile`, `50th Percentile`, and `Average`.
The screenshot also shows the underlying Grafana build-information labels directly (`job`,
`instance`, `edition`, and `version`) without explanatory text.

## Scope finding

The dashboard JSON is Grafana's built-in Overview dashboard. Its definition is not present in this
repository or the adjacent `shopping-cart-infra` checkout. The source-controlled dashboards under
`scripts/etc/grafana/dashboards/` and `scripts/etc/argocd/platform-ops/` are separate custom
dashboards and do not contain these panels.

## Required fix

Provide a source-controlled replacement or supported override for the Overview dashboard that:

- labels status series as `HTTP <code> — <meaning>`;
- explains `-1` as a non-HTTP or instrumented failure result;
- labels latency series as `p99`, `median (p50)`, and `average`, with a panel description;
- gives the Build Info table a human-readable description;
- preserves the existing queries and dashboard data source selection.

The replacement must be rendered and validated from source, and must not be created by editing the
Grafana UI.

## Resolution

Added `scripts/etc/grafana/dashboards/grafana-overview-readable-configmap.yaml`. It keeps the
existing PromQL, datasource variable, job/instance filters, and panel layout, while adding
explanatory panel descriptions and readable HTTP-status, percentile, median, and average legends.
It uses the unique title `Grafana Overview — Readable` and UID `k3dm-grafana-overview`, because the
Helm-owned Overview dashboard cannot be safely overridden by a second ConfigMap with the same UID.
The dashboard sidecar imports it from the existing ArgoCD-managed dashboards directory.

The same dashboard is also present in `scripts/etc/argocd/platform-ops/` for the hub ApplicationSet;
the app-cluster and hub dashboards must be synchronized separately.

Implementation commits: `62940976`, `487b0a43`.
