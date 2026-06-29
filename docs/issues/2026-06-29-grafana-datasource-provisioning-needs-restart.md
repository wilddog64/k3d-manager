# Issue: hub Grafana did not hot-reload datasource provisioning after values changed

## What was attempted

After pushing the hub Loki datasource URL fix and hard-refreshing
`application/kube-prometheus-stack`, the live Grafana datasource API was checked.

## Actual behavior

The datasource provisioning file inside the Grafana pod had the corrected value:

```text
url: http://loki-gateway.monitoring.svc.cluster.local
```

But Grafana `/api/datasources` still returned the old live datasource:

```text
url: http://hub-loki-gateway.monitoring.svc.cluster.local
```

## Observed behavior

Dashboard provisioning updated from sidecar without a restart, but datasource provisioning
did not take effect in the running Grafana process until the deployment was restarted.

## Workaround used

```text
kubectl --context k3d-k3d-cluster -n monitoring rollout restart deployment/kube-prometheus-stack-grafana
kubectl --context k3d-k3d-cluster -n monitoring rollout status deployment/kube-prometheus-stack-grafana --timeout=180s
```

After restart:

- `/api/datasources` showed `http://loki-gateway.monitoring.svc.cluster.local`
- Grafana `/api/ds/query` for the Image Updater logs panel returned real log lines

## Root cause

Not fully diagnosed in this task. The most likely explanation is that the chart-managed
datasource provisioning file changed on disk, but Grafana 11.4.0 did not hot-reload that
datasource definition in-process.

## Recommended follow-up

Decide whether hub Grafana datasource changes should explicitly trigger a rollout restart in
the observability workflow, or whether the current manual/operator restart expectation is
acceptable.
