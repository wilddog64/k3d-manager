# Bug: make status uses APP_CONTEXT=ubuntu-k3s regardless of CLUSTER_PROVIDER

**Branch:** `k3d-manager-v1.2.0`
**File:** `Makefile` (status target)

## Root Cause

`bin/acg-status` defaults `APP_CONTEXT` to `ubuntu-k3s` (the AWS cluster context).
The `status` Makefile target passes no override, so `make status CLUSTER_PROVIDER=k3s-gcp`
shows nodes and pods for the unreachable AWS cluster instead of the GCP cluster:

```
=== Nodes (ubuntu-k3s) ===
(empty — ubuntu-k3s at 35.90.75.113:6443 is unreachable)
```

Secondary issue (deferred): `bin/acg-status` always runs `aws sts get-caller-identity`
at the end, which is irrelevant for GCP and shows a misleading credentials error.

## Fix

Update the `status` Makefile target to pass `APP_CONTEXT=ubuntu-gcp` when
`CLUSTER_PROVIDER=k3s-gcp`, using the same pattern as the `sync-apps` fix.

**Old:**
```makefile
## Show cluster nodes, pod status, tunnel health
status:
	bin/acg-status
```

**New:**
```makefile
## Show cluster nodes, pod status, tunnel health
status:
	APP_CONTEXT=$(if $(filter k3s-gcp,$(CLUSTER_PROVIDER)),ubuntu-gcp,ubuntu-k3s) bin/acg-status
```
