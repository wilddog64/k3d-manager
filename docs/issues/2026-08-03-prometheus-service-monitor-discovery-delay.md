# Prometheus delayed vulnerability-exporter target discovery

**Date:** 2026-08-03
**Status:** Resolved

## What happened

The deployed `vulnerability-inventory-exporter` pod was healthy and its
ServiceMonitor and Endpoints were valid, but an immediate Prometheus query
returned no `trivy_vulnerability_inventory` series.

## Evidence

The ServiceMonitor had:

```yaml
labels:
  release: kube-prometheus-stack
spec:
  namespaceSelector:
    any: true
  selector:
    matchLabels:
      app: vulnerability-inventory-exporter
```

The Endpoints object contained pod `10.42.4.60:8080` on port `metrics`.
Prometheus was configured with `serviceMonitorNamespaceSelector: {}` and
`serviceMonitorSelector.matchLabels.release: kube-prometheus-stack`.

Initial query:

```text
{"status":"success","data":{"resultType":"vector","result":[]}}
```

After Prometheus Operator reconciliation, the target appeared and the same
query returned inventory series including `fixed_version` and `package` labels.

## Root cause

Prometheus Operator target/config reload lag after the ServiceMonitor was
created or updated. No RBAC, selector, endpoint, or exporter failure was found.

## Resolution

The exporter ServiceMonitor now explicitly selects the kube-prometheus-stack
release and all namespaces. Verification showed the target in Prometheus and
`trivy_vulnerability_inventory` query results.

## Follow-up

Keep a post-deploy target/query check in the platform-ops verification runbook;
allow one reconciliation interval before treating an empty query as failure.
