# Bugfix: 2026-07-08 — public Grafana route must serve the hub dashboard instance

**Branch:** `k3d-manager-v1.14.0`  
**Files:** `scripts/lib/providers/k3s-hostinger.sh`, `scripts/tests/lib/provider_contract.bats`

## Problem

`grafana.3ai-talk.org` now loads Grafana again, but the ArgoCD/Image Updater dashboard path shows:

- `Dashboard not found`

This is not a Grafana availability failure. It is a dashboard-instance mismatch.

## Root Cause

The public Grafana route is still:

- `grafana.3ai-talk.org` → Cloudflare tunnel → `localhost:3001`

But the generated `com.k3d-manager.grafana-port-forward` plist currently points `:3001` at:

- `svc/acg-kube-prometheus-stack-grafana`
- context `ubuntu-hostinger`

The repo’s provisioned dashboard file is:

- `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`
- key `argocd-image-updater-hub.json`
- UID `argocd-image-updater-hub`

That dashboard belongs to the **hub Grafana** instance, not the Hostinger app-cluster Grafana. So
the current public route serves a healthy Grafana that does not have the requested dashboard object,
which produces the user-visible `Dashboard not found` page.

## Required Fix

Repoint the generated public Grafana port-forward back to the hub Grafana instance:

- service: `svc/kube-prometheus-stack-grafana`
- context: `k3d-k3d-cluster`

Do not touch the dashboard JSON, cloudflared config, or any Grafana datasource definitions. This is
strictly a public-route target correction.

## Exact Change

### Change 1 — `scripts/lib/providers/k3s-hostinger.sh`

Replace the Grafana port-forward target in `_hostinger_refresh_access_layer`:

**OLD**
```bash
  _hostinger_write_monitoring_port_forward_plist \
    "${_grafana_pf_plist}" \
    "${_grafana_pf_log}" \
    "svc/acg-kube-prometheus-stack-grafana" \
    "${_HOSTINGER_KUBE_CONTEXT}" \
    "3001" \
    "80"
```

**NEW**
```bash
  _hostinger_write_monitoring_port_forward_plist \
    "${_grafana_pf_plist}" \
    "${_grafana_pf_log}" \
    "svc/kube-prometheus-stack-grafana" \
    "k3d-k3d-cluster" \
    "3001" \
    "80"
```

### Change 2 — `scripts/tests/lib/provider_contract.bats`

Update the contract assertions for the generated plist:

**OLD**
```bash
  run grep -F -- 'svc/acg-kube-prometheus-stack-grafana' "${HOME}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist"
  [ "$status" -eq 0 ]
  run grep -F -- '<string>ubuntu-hostinger</string>' "${HOME}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist"
  [ "$status" -eq 0 ]
```

**NEW**
```bash
  run grep -F -- 'svc/kube-prometheus-stack-grafana' "${HOME}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist"
  [ "$status" -eq 0 ]
  run grep -F -- '<string>k3d-k3d-cluster</string>' "${HOME}/Library/LaunchAgents/com.k3d-manager.grafana-port-forward.plist"
  [ "$status" -eq 0 ]
```

## Gates

- `shellcheck -S warning scripts/lib/providers/k3s-hostinger.sh`
- `bats scripts/tests/lib/provider_contract.bats`
- `./scripts/k3d-manager _agent_audit`

## Out of Scope

- exposing a second public hostname for app-cluster Grafana
- changing dashboard JSON or UID
- changing cloudflared ingress entries
- live refresh / live rollout of the port-forward on the laptop
