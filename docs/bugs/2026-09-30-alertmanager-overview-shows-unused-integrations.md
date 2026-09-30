# Bug: the Alertmanager overview dashboard shows every integration, not the ones this stack uses

**Branch:** `k3d-manager-v1.40.0`
**Filed:** 2026-09-30 by Claude (cloud session), from the operator's screenshot
**Status:** FIXED 2026-09-30 by Claude — `k3dm Alertmanager Delivery` dashboard added (commit in
the changelog entry). The chart's dashboard remains; see "Why it stays".

## Evidence

The Grafana dashboard **Alertmanager / Overview** repeats a "Notifications Send Rate" and a
"Notification Duration" panel for discord, email, msteams, opsgenie, pagerduty, pushover, slack,
sns, telegram, victorops, webex, webhook and wechat. Only `email` had data. This stack routes
`severity=critical` to the SMS gateway and `warning` to Gmail (both email integrations) and ArgoCD /
Trivy alerts to webhook receivers (`alertmanager-config.yaml`). Nothing uses the others.

## Root cause

The dashboard is the kube-prometheus-stack chart's built-in `alertmanager-overview`, not a repo file.
Its `integration` variable is `label_values(alertmanager_notifications_total, integration)`, and
Alertmanager pre-registers that counter at 0 for every integration it supports, used or not. So the
repeat draws a panel per supported integration. The empty panels hide the two that matter.

## Why it stays

In chart `67.9.0` (the pinned hub version) that dashboard is gated only by
`grafana.defaultDashboardsEnabled`, which also turns off the other ~25 default dashboards. There is no
per-dashboard switch, and patching the chart's JSON at deploy time would break on every chart upgrade.
Revisit if a later chart version adds a per-dashboard toggle.

## Fix

`scripts/etc/argocd/platform-ops/grafana-dashboard-alertmanager-delivery.yaml`, uid
`k3dm-alertmanager-delivery`, applied by `argocd.sh` with the other platform-ops dashboards and synced by
`grafana-dashboards-hub`:

- the `integration` variable lists only integrations with at least one send in the last 30 days
  (`query_result(sum by (integration) (max_over_time(alertmanager_notifications_total[30d])) > 0)`);
- stats: notifications sent (24 h) and failed (24 h, red above 0) per integration in use;
- **firing alerts by severity**, with the routing spelled out: critical → SMS, warning → email. Many
  warnings and no critical alerts means email and no texts, by design. That answers the 2026-09-29
  question.
- a repeated row per integration in use: send/failed rate and p50/p99 delivery latency.

Hermes's own SMS pager sends from the M4 through Gmail SMTP and is not an Alertmanager integration; the
dashboard description says so.

Tests: `scripts/tests/plugins/alertmanager_delivery_dashboard.bats` (5). Listing every integration (no
`> 0`) and not deploying the file each went red.

**Live check (operator):** after the next platform-ops sync, Grafana → Dashboards →
"k3dm Alertmanager Delivery" shows `email` (and `webhook` once it has fired) and nothing else.
