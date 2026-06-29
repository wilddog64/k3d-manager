# Hostinger Grafana no-data live validation record

**Found:** 2026-06-29  
**Branch:** `k3d-manager-v1.12.0`

## What was tested

Implemented the Hostinger observability drift fix locally, then completed the
live Hostinger refresh/status validation:

```text
$ bash -n scripts/lib/providers/k3s-hostinger.sh scripts/plugins/observability.sh bin/cluster-status
$ shellcheck -S warning scripts/lib/providers/k3s-hostinger.sh scripts/plugins/observability.sh bin/cluster-status
$ bats scripts/tests/lib/provider_contract.bats scripts/tests/lib/observability.bats scripts/tests/bin/cluster_status_image_updater.bats scripts/tests/bin/cluster_status_observability.bats
1..49
...
ok 49 cluster-status surfaces app-cluster Prometheus health and OOM evidence

$ ./scripts/k3d-manager _agent_audit
running under bash version 5.3.15(1)-release

$ make refresh CLUSTER_PROVIDER=k3s-hostinger
...
INFO: [k3s-hostinger] Refresh complete — ubuntu-hostinger reachable
__WEBHOOK_SUCCESS__

$ make status CLUSTER_PROVIDER=k3s-hostinger
...
=== App Observability (ubuntu-hostinger) ===
Prometheus: 1/1 available
...
=== ArgoCD Apps ===
...
cicd        data-layer                      Synced        Healthy
...
cicd        shopping-cart-product-catalog   Synced        Healthy
...
cicd        ubuntu-hostinger-platform       Synced        Healthy
...
  ✅ Grafana: HTTP 200
  ✅ Prometheus: HTTP 200
  ✅ Data layer: 4/4 ready
```

## Result

Live validation passed. The observability fix converged on Hostinger and the
same refresh also left the previously drifted Hostinger ArgoCD apps synced.

## Follow-up note

During the refresh, the Vault auth helper still logs a benign
`path is already in use at kubernetes-app/` message before completing the
existing auth configuration successfully. That noise did not block the refresh.
