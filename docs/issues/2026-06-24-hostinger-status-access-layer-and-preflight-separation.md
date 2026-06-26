# Issue: Hostinger status mixed preflight apps with core apps, and refresh did not restore the local access layer

**Filed:** 2026-06-24  
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`

## What happened

`make status CLUSTER_PROVIDER=k3s-hostinger` showed a confusing mix of core Hostinger apps and
`green1-preflight-*` rows in the same ArgoCD table. The same status run also showed local access
layer failures such as:

```text
❌ Frontend: <urlopen error [Errno 61] Connection refused>
❌ Pushgateway: <urlopen error [Errno 61] Connection refused>
❌ Product images: <urlopen error [Errno 61] Connection refused>
```

Those failures made the Hostinger app cluster look broken even when the preflight rows were the
real source of the noise.

## Root cause

Two separate issues were involved:

1. `bin/cluster-status` printed the raw ArgoCD application table, so preflight apps appeared
   alongside the primary Hostinger app cluster apps.
2. The Hostinger refresh path only restored kubeconfig + ArgoCD registration. It did not refresh
   the local launchd access layer that backs `frontend`, `keycloak`, `grafana`, and
   `pushgateway`, so those endpoints could remain on `Connection refused`.

## Fix

- Split the ArgoCD application table in `bin/cluster-status` into core apps and preflight apps.
- Add a Hostinger refresh helper that restarts the local access-layer launchd services.

## Follow-up

- Re-run `make status CLUSTER_PROVIDER=k3s-hostinger` after a refresh and confirm the preflight
  apps are shown separately from the core Hostinger apps.
- Confirm `frontend`, `pushgateway`, and the other public endpoints come back without requiring a
  manual launchd restart.
