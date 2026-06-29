# Bugfix: 2026-06-29 — Image Updater Grafana dashboard was deployed against the wrong cluster

## Summary

The new `ArgoCD Apps & Image Updater` dashboard rendered as all `No data` in the
`ubuntu-hostinger` Grafana instance even though the dashboard JSON itself loaded
correctly.

## Actual behavior

Grafana on the app cluster showed:

- `Image Updater Ready Replicas` → `No data`
- `Image Updater Desired Replicas` → `No data`
- `Watched App Health / Sync` → `No data`
- `Watched App Sync Activity (5m increase)` → `No data`
- `Possible Flapping (30m syncs)` → `No data`
- `Image Updater Processing Results` → `No data`

## Root cause

The dashboard queries hub-only data:

- `argocd-image-updater` runs on the hub cluster in namespace `cicd`
- `argocd_app_*` metrics are emitted by the hub ArgoCD installation
- Image Updater logs are written by hub pods

But the live validation path applied the dashboard to the app-cluster observability
stack on `ubuntu-hostinger`. That Grafana instance queries the app-cluster
Prometheus/Loki pair, which do not contain the hub `cicd` deployment metrics, hub
ArgoCD app metrics, or hub Image Updater logs.

## Fix

Make the hub observability stack own the Image Updater dashboard and its log backend:

1. Add `loki` to `scripts/etc/argocd/applicationsets/observability.yaml` so the hub
   monitoring stack has a Loki datasource for hub logs.
2. Update `scripts/plugins/observability.sh` so `deploy_observability` applies:
   - `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`
   - `scripts/etc/observability/promtail.yaml`
   both against hub context `k3d-k3d-cluster`.
3. Keep the app-cluster observability stack focused on app-cluster telemetry; do not
   treat it as the source of truth for hub ArgoCD/Image Updater metrics.

## Validation

- `bats scripts/tests/lib/observability.bats scripts/tests/plugins/argocd_loki.bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats`
- `shellcheck -S warning scripts/plugins/observability.sh`
- `./scripts/k3d-manager _agent_audit`
