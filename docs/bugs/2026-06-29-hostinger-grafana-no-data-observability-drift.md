# Bug: Hostinger Grafana shows no data because observability drifts to an old branch and undersized Prometheus

**Branch:** `k3d-manager-v1.12.0`
**Files:**
- `scripts/lib/providers/k3s-hostinger.sh` (edit)
- `scripts/plugins/observability.sh` (edit)
- `scripts/etc/argocd/applicationsets/observability-acg.yaml` (edit)
- `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml` (edit)
- `scripts/tests/lib/provider_contract.bats` (edit)
- `scripts/tests/lib/observability.bats` (edit)

---

## Problem

On `2026-06-29`, Grafana on `ubuntu-hostinger` loaded but showed no data.

Live inspection showed the failure was not the Grafana UI itself. The backing
Prometheus pod was unhealthy:

```text
$ kubectl --context ubuntu-hostinger -n monitoring describe pod prometheus-acg-kube-prometheus-stack-prometheus-0
...
Last State:  Terminated
  Reason:    OOMKilled
  Exit Code: 137
...
Limits:
  memory: 512Mi
```

At the same time, the hub-side `observability-acg` ApplicationSet and child app
were still pinned to an old branch (`feat/v1.8.0-acg-absorb-phase2-agy`), so
Hostinger kept reconciling stale observability values instead of the current
branch.

## Root Cause

Two issues compounded:

1. `make refresh CLUSTER_PROVIDER=k3s-hostinger` restored kubeconfig,
   registration, Vault, and local listeners, but it never re-applied the
   observability ApplicationSet. Once the live ApplicationSet drifted to an old
   `targetRevision`, refresh left that stale branch pin in place indefinitely.
2. The shared app-cluster observability values still capped Prometheus at
   `512Mi`, even though the repo already recorded `1Gi` as the safe baseline for
   this stack after previous OOMs.

## Fix

1. Re-apply `deploy_observability_acg "${_HOSTINGER_KUBE_CONTEXT}"` during the
   Hostinger refresh flow, immediately after cluster registration, so refresh
   self-heals the ApplicationSet back to the current branch.
2. Pass `APP_CLUSTER_NAME` through the observability ApplicationSet render and
   map it into the Helm parameter
   `prometheus.prometheusSpec.externalLabels.cluster`, so the live cluster label
   matches the real destination context.
3. Raise the shared app-cluster Prometheus memory limit from `512Mi` to `1Gi`.

## Definition of Done

- [ ] Hostinger refresh reapplies observability from the current branch
- [ ] Observability ApplicationSet renders `APP_CLUSTER_NAME`
- [ ] Prometheus memory limit is `1Gi`
- [ ] Tests updated and passing
- [ ] Commit pushed and memory-bank updated
