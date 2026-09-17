# k3dm deployment dashboard has no data

**Date:** 2026-09-17

## Finding

The `k3dm Deployment Metrics` dashboard is present, but its panels depend on
`k3dm_deployment_*` metrics that are not currently published.

## Live checks

```text
count(k3dm_deployment_duration_seconds) = 0
count(k3dm_deployment_success) = 0
service/prometheus-pushgateway = NotFound
```

The dashboard definition is installed by `_deploy_pushgateway_acg`, but that
function only attempts to install Pushgateway and apply the dashboard. No
deployment lifecycle code currently pushes `k3dm_deployment_duration_seconds`,
`k3dm_deployment_success`, or `k3dm_deployment_last_timestamp_seconds`.

## Panel meaning

- Last acg-up/down Duration: duration of the latest cluster lifecycle action.
- Last Deployment Success: whether the latest action completed successfully.
- Last Deployment Time: timestamp of the latest lifecycle action.
- Deployment Duration Over Time: historical lifecycle durations.

## Follow-up

Add a bounded, authenticated deployment-event publisher (or restore the
Pushgateway installation and push contract) before treating this dashboard as
operational. Until then, `No data` means telemetry is not wired, not that a
deployment has failed.
