# Bug: Pushgateway deployment metrics are intermittently missing

**Filed:** 2026-06-09

## Description

`bin/k3dm-webhook` pushes deployment metrics to Prometheus Pushgateway only once,
at job finish. When the Pushgateway port-forward or pod is still warming up, that
single best-effort push can fail and be logged as a non-fatal skip. The Grafana
dashboard then shows no fresh deployment data until a later run succeeds.

This matches the observed behavior where `k3dm_deployment_duration_seconds`,
`k3dm_deployment_success`, and `k3dm_deployment_last_timestamp_seconds` appear
intermittently: the data exists only when the one-shot push lands after
Pushgateway is reachable.

## Why this matters

- Grafana deployment panels look flaky even when the underlying deployment
  completed successfully.
- The last successful metric sample can be stale or missing if Pushgateway was
  briefly unavailable at job completion.
- The current best-effort push path has no retry window, so transient readiness
  gaps turn into lost metrics.

## Proposed follow-up

1. Add a bounded retry window around the Pushgateway metric push.
2. Prefer a healthy/reachable Pushgateway before sending the POST.
3. Keep the push non-fatal, but avoid dropping metrics on short-lived readiness
   gaps.
