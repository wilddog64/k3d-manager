# Issue: Prometheus LaunchAgent stayed on the old `ubuntu-k3s` context after the repo fix

**Filed:** 2026-06-24
**Type:** investigation
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`

## What happened

The failure reported from `make up` looked like a live observability outage:

```text
INFO: [acg-up] Step 14/14 — Deploying ACG observability (Prometheus + Trivy)...
INFO: [observability] Deploying ACG observability stack...
applicationset.argoproj.io/observability-acg configured
INFO: [observability] ACG ApplicationSet applied — ArgoCD will sync monitoring/trivy-system on ubuntu-k3s
INFO: [observability] Reading Alertmanager credentials from Vault...
Error from server (NotFound): error when creating "STDIN": namespaces "monitoring" not found
WARN: [acg-up] failed (exit 1) — cleaning up local processes...
make: *** [up] Error 1
```

Investigation showed the repository already contains the app-cluster-aware fix:

- `scripts/plugins/observability.sh` resolves the active provider context before creating `monitoring` secrets.
- `scripts/etc/launchd/com.k3d-manager.prometheus-port-forward.plist.tmpl` already targets `k3d-k3d-cluster`.

The remaining failure on this machine was a stale local LaunchAgent install, not a missing code fix.

## Evidence

Live plist on disk still pointed at the old context:

```xml
<string>--context</string>
<string>ubuntu-k3s</string>
```

The LaunchAgent log kept repeating the same namespace error:

```text
Error from server (NotFound): namespaces "monitoring" not found
```

`launchctl list com.k3d-manager.prometheus-port-forward` returned nothing, so the agent was not actively managed at the time of inspection.

## Root Cause

The repo-side fix was already present, but the installed LaunchAgent was stale.
It had not been reinstalled after the plist template changed.

## Follow-up

- Reinstall the LaunchAgent with `make install-prometheus-port-forward`.
- Keep the LaunchAgents reference in sync with the plist template so the installed context matches the current repo.
- For ACG/Hostinger observability paths, prefer provider-resolved contexts instead of hardcoding `ubuntu-k3s` in new code.
