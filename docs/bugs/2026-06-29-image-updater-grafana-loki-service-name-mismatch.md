# Bugfix: 2026-06-29 — hub Loki service names drifted from promtail and Grafana expectations

## Summary

After moving the Image Updater dashboard to hub Grafana and provisioning a hub Loki
datasource, the logs panel still returned no rows even though `kubectl logs` showed
matching `Processing results:` lines from `argocd-image-updater`.

## Actual behavior

Grafana `/api/ds/query` for the logs panel initially returned zero lines for:

```logql
{namespace="cicd",pod=~"argocd-image-updater.*"} |= "Processing results:"
```

At the same time:

- hub `argocd-image-updater` logs clearly contained `Processing results:` lines
- Prometheus-backed panels already returned data

## Root cause

The hub ArgoCD Application name was changed to `hub-loki` to avoid colliding with the
app-cluster `loki` Application in `cicd`, but Helm defaulted the release name to the
Application name. That produced hub services such as:

- `hub-loki`
- `hub-loki-gateway`

while both the shared promtail manifest and the intended Grafana datasource path expected:

- `loki`
- `loki-gateway`

So hub promtail was writing to `loki.monitoring.svc.cluster.local`, which did not exist,
and the first hub Grafana Loki datasource attempt also targeted the wrong gateway host
until the service-name issue was corrected.

## Fix

1. Keep the ArgoCD Application name distinct as `hub-loki`.
2. Force the Helm release name back to `loki` in
   `scripts/etc/argocd/applicationsets/observability.yaml`:

```yaml
releaseName: '{{if eq .name "hub-loki"}}loki{{else}}{{.name}}{{end}}'
```

3. Point the hub Grafana Loki datasource at:

```text
http://loki-gateway.monitoring.svc.cluster.local
```

This keeps:

- unique ArgoCD Application naming in `cicd`
- shared service naming that matches the existing promtail manifest and Grafana datasource

## Live verification

After reapplying the hub `observability` ApplicationSet, refreshing `application/hub-loki`,
and restarting Grafana so it reloaded datasource provisioning:

- hub services changed to `loki`, `loki-gateway`, `loki-canary`, etc.
- Grafana `/api/datasources` reported Loki URL
  `http://loki-gateway.monitoring.svc.cluster.local`
- Grafana `/api/ds/query` for the logs panel returned 3 recent
  `Processing results:` entries from `argocd-image-updater`

## Validation

- `bats scripts/tests/plugins/argocd_loki.bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats`
- `/private/tmp/k3d-manager-pyyaml/bin/python3` ApplicationSet YAML parse check
- `./scripts/k3d-manager _agent_audit`
