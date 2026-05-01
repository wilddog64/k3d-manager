# Bug: make sync-apps uses APP_CONTEXT=ubuntu-k3s regardless of CLUSTER_PROVIDER

**Branch:** `k3d-manager-v1.2.0`
**File:** `Makefile` (sync-apps target)

## Root Cause

`bin/acg-sync-apps` defaults `APP_CONTEXT` to `ubuntu-k3s` (the AWS cluster context).
The `sync-apps` Makefile target passes no override, so `make sync-apps CLUSTER_PROVIDER=k3s-gcp`
still checks pod status against the AWS cluster, which is unreachable:

```
INFO: [sync-apps] Pod status (ubuntu-k3s):
Unable to connect to the server: dial tcp 35.90.75.113:6443: i/o timeout
```

The ArgoCD steps (port-forward, login, sync) all succeed — only the final
`kubectl get pods --context ubuntu-k3s` fails.

## Fix

Update the `sync-apps` Makefile target to pass `APP_CONTEXT=ubuntu-gcp` when
`CLUSTER_PROVIDER=k3s-gcp`, keeping `ubuntu-k3s` as the default for all other providers.

**Old:**
```makefile
## Sync ArgoCD data-layer and show remote pod status
sync-apps:
	bin/acg-sync-apps
```

**New:**
```makefile
## Sync ArgoCD data-layer and show remote pod status
sync-apps:
	APP_CONTEXT=$(if $(filter k3s-gcp,$(CLUSTER_PROVIDER)),ubuntu-gcp,ubuntu-k3s) bin/acg-sync-apps
```
