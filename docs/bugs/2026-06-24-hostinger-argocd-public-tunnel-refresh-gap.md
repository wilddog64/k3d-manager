# Bug: Hostinger refresh did not restart the ArgoCD port-forward behind `argocd.3ai-talk.org`

**Date:** 2026-06-24  
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`  
**Files:** `scripts/lib/providers/k3s-hostinger.sh`, `scripts/tests/lib/provider_contract.bats`

## Problem

`make refresh CLUSTER_PROVIDER=k3s-hostinger` refreshed the Cloudflare tunnel and the browser
listeners, but it did not explicitly revive the `com.k3d-manager.argocd-port-forward` LaunchAgent.

`argocd.3ai-talk.org` is routed by Cloudflare to `http://localhost:8080`, so if the ArgoCD
port-forward dies or is missing, the public hostname returns a 502 even though the rest of the
access layer appears healthy.

## Root Cause

The Hostinger-specific access-layer refresh covered:

- `cloudflared`
- `argocd-browser-https`
- `keycloak-browser-http`
- `frontend-browser-http`
- `grafana-port-forward`
- `pushgateway-port-forward`

but not the underlying ArgoCD port-forward on `localhost:8080`.

## Fix

- Restart or self-heal `com.k3d-manager.argocd-port-forward` during Hostinger refresh.
- Keep the existing tunnel/browser restarts in place.
- Add contract coverage so the Hostinger refresh path includes the ArgoCD port-forward.

## Expected Result

- `make refresh CLUSTER_PROVIDER=k3s-hostinger` restores the access layer needed by
  `https://argocd.3ai-talk.org`.
- A stale or dead ArgoCD port-forward no longer leaves the public ArgoCD hostname returning 502.
