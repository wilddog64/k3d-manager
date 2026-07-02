# Bugfix: add an alert for ArgoCD Image Updater flapping

## Problem

The dashboard already showed `Possible Flapping (30m syncs)` for the Image
Updater-managed apps, but there was no Prometheus alert for the same signal.
That meant a repeating sync churn could be visible in Grafana and `make status`
while still never generating an alert.

## Root Cause

The repo had Prometheus rules for `ArgoCDAppDegraded` and
`ArgoCDAppOutOfSync`, but nothing that looked at repeated sync activity on the
Image Updater-managed apps.

## Fix

- Add `ArgoCDImageUpdaterFlapping` to `scripts/etc/argocd/platform-ops/prometheusrule.yaml`
- Route it through the existing analyzer webhook in
  `scripts/etc/argocd/platform-ops/alertmanager-config.yaml`
- Document the alert in `docs/howto/argocd-alerts.md`
- Cover the new rule and route with `scripts/tests/plugins/argocd_metrics_servicemonitor.bats`

The alert reuses the same 30 minute sync-churn signal as the dashboard and
targets the Image Updater-managed shopping-cart apps:

- `shopping-cart-basket`
- `shopping-cart-order`
- `shopping-cart-product-catalog`

It fires when one of those apps has at least 5 syncs in 30 minutes for 10
minutes.

## Expected Outcome

- repeated image-adoption churn now pages through the existing analyzer path
- the dashboard and alert use the same underlying sync signal
- operators can spot flapping in Grafana and Alertmanager
