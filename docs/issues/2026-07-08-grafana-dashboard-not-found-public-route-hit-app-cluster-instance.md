# Issue: 2026-07-08 — public Grafana returned "Dashboard not found" because the route hit the app-cluster instance

## What was observed

User-reported live behavior at `grafana.3ai-talk.org`:

- Grafana shell loaded successfully
- dashboard page rendered:
  - `Dashboard not found`

The screenshot matched a healthy Grafana frontend returning a missing-dashboard route, not a 502 or
datasource failure.

## Root cause

Current repo state on `k3d-manager-v1.14.0` before the fix:

- `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml` provisions dashboard key
  `argocd-image-updater-hub.json`
- that dashboard is intended for the hub Grafana instance
- `scripts/lib/providers/k3s-hostinger.sh` was generating the public
  `com.k3d-manager.grafana-port-forward` plist against:
  - `svc/acg-kube-prometheus-stack-grafana`
  - context `ubuntu-hostinger`

So the public hostname served the Hostinger app-cluster Grafana, while the requested dashboard UID
only exists on the hub Grafana. Result: public route was healthy but the dashboard object was absent.

## Recommended fix

Repoint the generated public Grafana port-forward back to the hub Grafana instance:

- `svc/kube-prometheus-stack-grafana`
- `k3d-k3d-cluster`

Tracked and implemented via:

- `docs/bugs/2026-07-08-grafana-public-route-must-serve-hub-dashboard-instance.md`
