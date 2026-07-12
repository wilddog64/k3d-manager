# Issue: app-cluster Prometheus PVC/retention live verification deferred

**Date:** 2026-07-07
**Branch:** `k3d-manager-v1.14.0`
**Related fix commit:** `23e5d67f` (`fix(observability): give app-cluster Prometheus a PVC and 15d retention`)

## What was changed

Implemented the source fix from `docs/bugs/2026-07-07-app-cluster-prometheus-keeps-only-2h.md` in:

- `scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml`

The file now sets:

- `retention: 15d`
- `retentionSize: 8GB`
- `storageSpec.volumeClaimTemplate.spec.resources.requests.storage: 10Gi`

## Local validation output

```text
$ ruby -e "require 'yaml'; YAML.load_file('scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml'); puts 'YAML OK'"
YAML OK

$ rg -n "retention: 15d|retentionSize: 8GB|storageSpec:|storage: 10Gi" scripts/etc/helm/observability/kube-prometheus-stack-acg-values.yaml
62:    retention: 15d
63:    retentionSize: 8GB
64:    storageSpec:
70:              storage: 10Gi

$ ./scripts/k3d-manager _agent_audit
running under bash version 5.3.15(1)-release
```

## Pre-deploy live-state check

Before any redeploy in this session, the live app-cluster Prometheus still showed no storage:

```text
$ kubectl --context ubuntu-hostinger -n monitoring get prometheus -o jsonpath='{.items[*].spec.storage}'

```

That empty output matches the bug: no `spec.storage` on the live CR yet.

## What was skipped

No live redeploy was performed in this session, so these post-apply checks remain pending:

- `kubectl --context ubuntu-hostinger -n monitoring get prometheus -o jsonpath='{.items[*].spec.storage}'` should become non-empty
- `kubectl --context ubuntu-hostinger -n monitoring get pvc` should show a bound PVC in `monitoring`
- app-cluster Grafana should render a range older than 2h

## Recommended follow-up

1. Push/apply the branch so ArgoCD syncs `acg-kube-prometheus-stack`.
2. Verify the Prometheus CR now has `spec.storage`.
3. Verify a bound PVC exists in `monitoring`.
4. Confirm app-cluster Grafana renders >2h history.
