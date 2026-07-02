# Issue: Hostinger refresh restored ArgoCD and Keycloak, but left Alertmanager's local access layer unloaded

**Date:** 2026-07-02  
**Branch:** `k3d-manager-v1.12.0`  
**Area:** `scripts/plugins/observability.sh`, `scripts/lib/providers/k3s-hostinger.sh`, `scripts/tests/lib/observability.bats`

## Symptom

`make status CLUSTER_PROVIDER=k3s-hostinger` showed:

```text
❌ Alertmanager: HTTP 502 (https://alertmanager.3ai-talk.org/api/v2/status)
❌ ArgoCD: <urlopen error [Errno 61] Connection refused>
❌ Keycloak: HTTP Error 502: Bad Gateway
```

The cluster itself was healthy, but the Mac-side local listeners behind the public hostnames were not:

```text
curl: (7) Failed to connect to 127.0.0.1 port 9093
launchctl print gui/$(id -u)/com.k3d-manager.alertmanager-auth-proxy
Bad request. Could not find service ...
```

## Investigation

`make refresh CLUSTER_PROVIDER=k3s-hostinger` already restarted:

- `com.k3d-manager.argocd-port-forward`
- `com.k3d-manager.keycloak-port-forward`
- `com.k3d-manager.cloudflare-tunnel`
- `com.k3d-manager.vault-port-forward`
- `com.k3d-manager.grafana-port-forward`

but it did **not** reinstall the Alertmanager local access layer that backs
`https://alertmanager.3ai-talk.org`.

## Root Cause

`deploy_observability_acg()` handled the ACG Prometheus / Pushgateway / promtail setup, but it never called the Alertmanager local access-layer installers:

- `_observability_install_alertmanager_port_forward`
- `_observability_install_alertmanager_auth_proxy`

That left `localhost:19093` and `localhost:9093` unloaded after a reboot / logout / refresh cycle, which Cloudflare surfaced as a `502`.

## Fix

`deploy_observability_acg()` now also restores the Alertmanager login file and both launchd listeners, so Hostinger refresh brings the public Alertmanager route back automatically.

Validation:

```text
INFO: [observability] Alertmanager login credentials ready (...)
INFO: [observability] Alertmanager port-forward agent installed — raw backend stays open on port 19093
INFO: [observability] Alertmanager auth proxy installed — localhost:9093 now requires login
```

Final service health after refresh:

```text
✅ Alertmanager: HTTP 200
✅ ArgoCD: HTTP 200
✅ Keycloak: HTTP 200
```
