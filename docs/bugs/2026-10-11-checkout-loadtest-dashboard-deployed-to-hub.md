# Bug: the Checkout Load Test dashboard is deployed to the hub, where it can never show data

**Filed:** 2026-10-11
**Branch:** `k3d-manager-v1.43.2`
**Status:** VERIFIED — Claude offline: tests green, new tests red on the old code, mutations red. Awaiting live proof. Was: IMPLEMENTED — landed `89b45f56` (Codex, Claude verified: BATS 41/41, mutation red. Live proof after `make appsets-reapply`.)
**Approval:** explicit 2026-10-11 "yes" (to "file the bug … and schedule the baseline?")
**Priority:** P3 — a blank dashboard; the Hostinger copy is correct
**Severity:** low — misleading, nothing broken

## Symptom

Operator screenshot, 2026-10-11 ("how can we make data presented"): every panel of Checkout Load
Test reads No data, including "shopping-cart-apps CPU saturation", which uses ordinary Kubernetes
metrics and should never be empty where the shop runs.

Read-only checks the same day:

| | hub `k3d-k3d-cluster` | `ubuntu-hostinger` |
|---|---|---|
| ConfigMap `checkout-loadtest-dashboard` | yes, ArgoCD app `k3d-cluster-grafana-dashboards` | yes, `ubuntu-hostinger-grafana-dashboards` |
| `k6_*` series | 0 | 0 |
| `container_cpu_usage_seconds_total{namespace="shopping-cart-apps"}` | 0 | 12 |
| Prometheus remote-write receiver | off | on (retention 15d) |

## Root cause

1. `scripts/etc/argocd/applicationsets/grafana-dashboards-acg.yaml` syncs every file in
   `scripts/etc/grafana/dashboards/` to each cluster labelled `k3d-manager/role: app-cluster`. The
   hub carries that label (it is load-bearing for ESO, so it stays), and the in-cluster `exclude`
   only removes `grafana-overview-readable-configmap.yaml`. The hub has no shopping-cart workload,
   no remote-write receiver and no k6 run, so its copy of this dashboard is empty by construction.
2. The six k6 panels are empty on Hostinger too, because no load test has run in 15 days: the run is
   manual only. That part is not this bug; it is
   [`v1.48.0-scheduled-baseline-loadtest.md`](../plans/v1.48.0-scheduled-baseline-loadtest.md).
3. `docs/guides/grafana-dashboards.md` still says nothing applies this ConfigMap ("**nothing — see
   below**", "has no applier"). The ACG ApplicationSet has applied it since at least
   2026-09-04 (Hostinger ConfigMap age 37 days), so a reader is told to expect it to be missing.

Prior art: [`docs/issues/2026-09-17-checkout-loadtest-dashboard-no-data.md`](../issues/2026-09-17-checkout-loadtest-dashboard-no-data.md)
(no producer) — still true for the k6 panels; the hub copy and the stale guide are new.

## Fix

1. `grafana-dashboards-acg.yaml`: the in-cluster exclude gains the load-test file:
   `exclude: '{k3dm-tests-configmap.yaml,{{if eq .server "https://kubernetes.default.svc"}}grafana-overview-readable-configmap.yaml,checkout-loadtest-configmap.yaml{{end}}}'`.
   ArgoCD prunes the hub ConfigMap (`prune: true`); Hostinger is unchanged.
2. `docs/guides/grafana-dashboards.md`: the table row's applier becomes "`grafana-dashboards-acg`
   ApplicationSet (app clusters except the hub)", target "Hostinger/ACG"; replace the "has no
   applier" note and update the "Checkout Load Test" section: the dashboard is deployed to app
   clusters only; the CPU panel fills there at all times; the k6 panels fill only during and after
   a load test (Hostinger retains 15 days), and the scheduled baseline is the plan that keeps them
   filled.

## Files

| File | Change |
|---|---|
| `scripts/etc/argocd/applicationsets/grafana-dashboards-acg.yaml` | in-cluster exclude |
| `scripts/tests/plugins/grafana_dashboard_appsets.bats` | new test |
| `docs/guides/grafana-dashboards.md` | row + section |
| `CHANGELOG.md` | `[Unreleased]` entry |

## Tests

- New BATS in `grafana_dashboard_appsets.bats`: rendering the exclude template with
  `.server = "https://kubernetes.default.svc"` yields a pattern that matches
  `checkout-loadtest-configmap.yaml`; with any other server it does not (Hostinger keeps it).
  Reuse the existing helper that renders the exclude for the overview file.
- The existing hub-collision and k3dm-tests exclude tests stay green.
- Mutation: drop the new name from the in-cluster branch → the new test is red.

## Proof it works

After `make appsets-reapply` on the release branch: `kubectl --context k3d-k3d-cluster -n monitoring
get cm checkout-loadtest-dashboard` returns NotFound, the Hostinger ConfigMap is still present, and
its CPU panel shows a value.

## What NOT to Do

- Do NOT remove the hub's `k3d-manager/role: app-cluster` label (it drives the hub's ESO).
- Do NOT exclude `k3dm-deployments` or `trivy-security` here; whether their hub copies are useful
  is a separate check.
- Do NOT start a load test from a test or from this fix.
