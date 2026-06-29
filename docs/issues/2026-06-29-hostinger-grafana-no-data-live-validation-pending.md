# Hostinger Grafana no-data live validation pending

**Found:** 2026-06-29  
**Branch:** `k3d-manager-v1.12.0`

## What was tested

Implemented the Hostinger observability drift fix locally and ran repository
validation only:

```text
$ bash -n scripts/lib/providers/k3s-hostinger.sh scripts/plugins/observability.sh bin/cluster-status
$ shellcheck -S warning scripts/lib/providers/k3s-hostinger.sh scripts/plugins/observability.sh bin/cluster-status
$ bats scripts/tests/lib/provider_contract.bats scripts/tests/lib/observability.bats scripts/tests/bin/cluster_status_image_updater.bats scripts/tests/bin/cluster_status_observability.bats
1..49
...
ok 49 cluster-status surfaces app-cluster Prometheus health and OOM evidence

$ ./scripts/k3d-manager _agent_audit
running under bash version 5.3.15(1)-release
```

## What was skipped

No live `make refresh CLUSTER_PROVIDER=k3s-hostinger` or live
`make status CLUSTER_PROVIDER=k3s-hostinger` run was performed in this task.

## Why

The code-path/root-cause was already confirmed from live cluster inspection, and
this task focused on shipping the repo fix plus status visibility. The live
refresh/status run remains the operator confirmation step.

## Recommended follow-up

1. Run `make refresh CLUSTER_PROVIDER=k3s-hostinger`.
2. Run `make status CLUSTER_PROVIDER=k3s-hostinger`.
3. Confirm the `=== App Observability ===` section no longer reports
   `OOMKilled`, and that Grafana panels populate again.
