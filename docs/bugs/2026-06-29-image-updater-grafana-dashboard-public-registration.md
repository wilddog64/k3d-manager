# Bugfix: 2026-06-29 — public Grafana dashboard registration for Image Updater was not stable

## Summary

Even after the Image Updater metrics and logs were proven live through the hub Grafana
datasource APIs, the public dashboard page remained unreliable:

- `Dashboard not found`
- `Invalid dashboard UID in annotation request`

This was no longer a Prometheus/Loki data problem. It was a Grafana dashboard publication
problem.

## Actual behavior

The backend checks passed:

- Grafana datasource proxy returned live `argocd-image-updater` replica data
- Grafana datasource proxy returned live `argocd_app_info` rows
- Grafana datasource proxy returned recent Loki `Processing results:` lines

But the public dashboard page tied to the existing UID/path still failed for the user.

During verification, the live search endpoint also returned no matching dashboard rows for
the old Image Updater query even though the ConfigMap file existed, which made the old
record/path untrustworthy for operator use.

## Root cause

Two separate stale identities were in play:

- Grafana itself no longer served the old dashboard UID `argocd-image-updater`; live API
  verification returned `404 Not Found` for that UID while the newly provisioned
  `argocd-image-updater-hub` UID resolved correctly.
- On this Mac, the installed LaunchAgent
  `~/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist` was still pointing at
  `svc/acg-kube-prometheus-stack-grafana` on context `ubuntu-hostinger`, so
  `grafana.3ai-talk.org` was not actually serving the same hub Grafana instance proven by the
  in-cluster checks until that local port-forward was refreshed.

## Fix

Publish the dashboard as a fresh Grafana object:

1. Change the provisioned file key from:
   - `argocd-image-updater.json`
   to:
   - `argocd-image-updater-hub.json`
2. Change the dashboard title from:
   - `ArgoCD Apps & Image Updater`
   to:
   - `ArgoCD Apps & Image Updater Hub`
3. Change the dashboard UID from:
   - `argocd-image-updater`
   to:
   - `argocd-image-updater-hub`

This forces Grafana to register a fresh provisioned dashboard instead of relying on the old
public record/path.

Live operator follow-up on 2026-06-29:

- rewrite the installed `com.k3d-manager.grafana-port-forward` LaunchAgent so it targets
  `svc/kube-prometheus-stack-grafana` on `k3d-k3d-cluster`
- restart that LaunchAgent so `localhost:3001` and `grafana.3ai-talk.org` actually serve the
  hub Grafana instance

## Validation

- `bats scripts/tests/plugins/argocd_metrics_servicemonitor.bats`
- `/private/tmp/k3d-manager-pyyaml/bin/python3` dashboard YAML+JSON parse check
- live Grafana sidecar verification after reapply:
  - wrote `/tmp/dashboards/argocd-image-updater-hub.json`
  - removed `/tmp/dashboards/argocd-image-updater.json`
- live Grafana API verification:
  - hub pod `/api/dashboards/uid/argocd-image-updater-hub` -> 200 with URL
    `/d/argocd-image-updater-hub/argocd-apps-and-image-updater-hub`
  - hub pod `/api/dashboards/uid/argocd-image-updater` -> 404
  - public `https://grafana.3ai-talk.org/api/dashboards/uid/argocd-image-updater-hub` -> 200
    after the local LaunchAgent was rewritten and restarted
