# Bug: Grafana overview dashboard has no data

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30
**Status:** FIXED (`bc301f83`)
**Severity:** medium — the Grafana overview loads, but its dashboards, build info, RPS and
request-latency panels are empty.

## Evidence

The dashboard queries `grafana_build_info`, `grafana_http_request_duration_seconds_*`, and
`grafana_stat_totals_dashboard` through the Grafana ServiceMonitor. The rendered
`kube-prometheus-stack` chart creates that ServiceMonitor without the `release` label, while the
parent Prometheus selects ServiceMonitors using `release: kube-prometheus-stack` (or
`release: acg-kube-prometheus-stack`). The target is therefore excluded from discovery.

## Fix

Add the matching release label to the Grafana ServiceMonitor values for both the hub and ACG
stacks. This keeps the dashboard source unchanged and makes Prometheus scrape Grafana's metrics.

## Acceptance

The rendered Grafana ServiceMonitor has the same release label as its Prometheus selector, and the
Grafana overview panels can receive `grafana_build_info` and request metrics after reconciliation.
