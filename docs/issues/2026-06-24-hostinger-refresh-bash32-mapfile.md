# Issue: Hostinger `make refresh` aborted on macOS Bash 3.2 due to `mapfile`

**Date:** 2026-06-24  
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`  
**Area:** `scripts/lib/providers/k3s-hostinger.sh`

## What was tested

I ran the live Hostinger refresh path:

```bash
make refresh CLUSTER_PROVIDER=k3s-hostinger
```

I also reproduced the provider helper in a minimal shell on the same macOS environment.

## Actual output

The refresh aborted while clearing stale listeners:

```text
INFO: [k3s-hostinger] Refreshing ubuntu-hostinger kubeconfig + ArgoCD registration…
INFO: [k3s-hostinger] Removed stale ubuntu-hostinger context
INFO: [k3s-hostinger] ubuntu-hostinger merged into ~/.kube/config (current-context preserved: k3d-k3d-cluster)
INFO: [k3s-hostinger] Registering 'ubuntu-hostinger' (https://2.25.146.252:6443) with hub ArgoCD ns cicd...
secret/cluster-ubuntu-hostinger configured
INFO: [k3s-hostinger] Registered — verify: kubectl get secret cluster-ubuntu-hostinger -n cicd
INFO: [k3s-hostinger] Refreshing local access layer listeners...
INFO: [k3s-hostinger] Port 8080 is in use — killing stale ArgoCD port-forward listener(s)...
/Users/cliang/src/gitrepo/personal/k3d-manager/scripts/lib/providers/k3s-hostinger.sh: line 262: mapfile: command not found
make: *** [refresh] Error 1
```

## Root cause

`_hostinger_clear_port_listeners()` used `mapfile`, which is not available in the Bash 3.2 shell
that macOS still ships. That made the Hostinger refresh path exit nonzero before it could finish
restarting the access-layer services.

## Recommended follow-up

- Keep `_hostinger_clear_port_listeners()` portable across Bash 3.2 and Bash 5.x.
- Keep the browser wrapper regeneration on the canonical `_ACG_STATE_DIR/bin/...` paths so refresh
  can rebuild the launchd listeners consistently for provider switching.
- Re-run `make refresh CLUSTER_PROVIDER=k3s-hostinger` after any listener-related change.
