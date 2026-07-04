# Bugfix: app-specific ArgoCD alerts and Grafana views should cover data-layer, payment, and infra services

**Branch:** `k3d-manager-v1.12.0`
**Files:**
- `scripts/etc/argocd/platform-ops/prometheusrule.yaml` (edit)
- `scripts/etc/argocd/platform-ops/alertmanager-config.yaml` (edit)
- `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` (edit)
- `scripts/tests/plugins/argocd_metrics_servicemonitor.bats` (edit)

## Problem

The current ArgoCD observability path only gives narrow coverage for the
shopping-cart workload set:

- the Prometheus rule only fires `ArgoCDAppDegraded` generically
- the Grafana dashboard sync charts only watch
  `shopping-cart-basket`, `shopping-cart-order`, and
  `shopping-cart-product-catalog`

That leaves out the other apps that have already caused operational drift or
need the same visibility:

- `shopping-cart-apps`
- `shopping-cart-frontend`
- `shopping-cart-identity`
- `shopping-cart-namespace`
- `shopping-cart-networking`
- `shopping-cart-payment`
- `shopping-cart-rules`
- `data-layer`
- `trivy-operator`
- `ubuntu-hostinger-eso`
- `ubuntu-hostinger-platform`

## Root Cause

The existing dashboard queries hard-code only the image-updater watched apps,
and the alert rule does not distinguish the broader app portfolio that should be
covered by the same degradation / out-of-sync signals.

## Fix

1. Expand the ArgoCD Prometheus alerts so they fire for the full watched app set
   above, not just the narrow image-updater trio.
2. Add an `ArgoCDAppOutOfSync` alert alongside `ArgoCDAppDegraded` so sync drift
   is alerted the same way health degradation is.
3. Route both alerts through the existing Alertmanager webhook path.
4. Update the Grafana dashboard sync queries to use the same app set so what we
   alert on matches what we visualize.
5. Extend the BATS coverage to assert the broader app regex and the new
   OutOfSync alert wiring.

## Definition of Done

- [ ] Grafana sync/health panels cover the full watched app set
- [ ] Prometheus rules include both Degraded and OutOfSync alerts for that set
- [ ] Alertmanager routes both alert names to the webhook analyzer
- [ ] Tests prove the exact app regex is present in dashboard and alert config

