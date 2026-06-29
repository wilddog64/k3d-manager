# Bugfix: 2026-06-29 — Image Updater Grafana dashboard used unresolved datasource variables

## Summary

After the dashboard was moved to hub Grafana, the page still failed at runtime even though:

- the dashboard existed in Grafana
- the Prometheus queries returned live data directly
- the dashboard file was being provisioned

The remaining problem was Grafana datasource binding.

## Actual behavior

The dashboard produced runtime errors such as:

- `Dashboard not found`
- `Invalid dashboard UID in annotation request`

And the panels rendered `No data` even though the underlying Prometheus queries worked.

## Root cause

The provisioned dashboard JSON used datasource variables:

- Prometheus panels: `"uid": "${datasource}"`
- Loki panel: `"uid": "${logsource}"`

with:

```json
"templating": {
  "list": [
    { "name": "datasource", "query": "prometheus", "type": "datasource" },
    { "name": "logsource", "query": "loki", "type": "datasource" }
  ]
}
```

But the live hub Grafana provisioned this dashboard with empty variable state, so the
dashboard API showed unresolved datasource UIDs and the panels did not bind cleanly.

Separately, hub Grafana had no Loki datasource at all, so even a resolved log panel would
still fail.

## Fix

1. Pin the dashboard to concrete datasource UIDs:
   - Prometheus → `prometheus`
   - Loki → `loki`
2. Remove the unused dashboard templating datasource variables.
3. Provision a hub Loki datasource through
   `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`:
   - name: `Loki`
   - uid: `loki`
   - url: `http://hub-loki-gateway.monitoring.svc.cluster.local`

## Live verification

After pushing the fix and hard-refreshing the hub `kube-prometheus-stack` ArgoCD app:

- Grafana `/api/datasources` returned:
  - `Prometheus` uid `prometheus`
  - `Loki` uid `loki`
- Grafana `/api/dashboards/uid/argocd-image-updater` returned dashboard version `3`
  with explicit datasource bindings:
  - Prometheus panels → uid `prometheus`
  - logs panel → uid `loki`

## Validation

- `bats scripts/tests/lib/observability.bats scripts/tests/plugins/argocd_loki.bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats`
- `shellcheck -S warning scripts/plugins/observability.sh`
- `/private/tmp/k3d-manager-pyyaml/bin/python3` dashboard YAML+JSON parse check
- `./scripts/k3d-manager _agent_audit`
