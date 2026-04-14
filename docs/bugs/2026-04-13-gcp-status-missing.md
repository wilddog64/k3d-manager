# Bug: k3s-gcp provider missing `status` implementation in Makefile dispatch

**Branch:** `k3d-manager-v1.1.0`
**Files:** `scripts/lib/providers/k3s-gcp.sh`

---

## Summary

`make status CLUSTER_PROVIDER=k3s-gcp` fails with:

```
Error: Function 'status' not found in plugins
make: *** [status] Error 1
```

The Makefile dispatch expects each provider to export `_provider_<name>_status`, but
`scripts/lib/providers/k3s-gcp.sh` only defines `deploy_cluster` and `destroy_cluster`.

---

## Reproduction

```bash
make status CLUSTER_PROVIDER=k3s-gcp
```

---

## Root Cause

`k3s-gcp.sh` lacks `_provider_k3s_gcp_status`. When the dispatcher calls
`provider_dispatch status`, the loader cannot find the function and errors out. No
fallback to `kubectl get pods` exists.

---

## Proposed Fix

### Change 1 — `scripts/lib/providers/k3s-gcp.sh`

Implement `_provider_k3s_gcp_status` mirroring the k3s-aws UX:

1. Ensure kubeconfig `~/.kube/k3s-gcp.yaml` exists; guide user to `make up` if missing.
2. Run `gcloud compute instances describe` to show instance state/IP (optional but
   consistent with other providers).
3. Execute `kubectl --context k3s-gcp get nodes` and `get pods --all-namespaces` to
   provide cluster health and microservice status.

### Change 2 — `scripts/k3d-manager`

Add a top-level `status()` function that calls `_cluster_provider_call status "$@"` so
`make status` dispatches through the provider modules instead of looking for a plugin
named `status`.

Update `docs/plans/v1.1.0-gcp-provision-full-stack.md` if status expectations change.

---

## Impact

Without a provider status action, users cannot rely on `make status` workflows for
k3s-gcp; they must remember raw kubectl/gcloud commands. This breaks parity with the
k3s-aws provider and the Makefile UX described in `docs/plans/v1.0.7-makefile-provider-dispatch.md`.

---

## Definition of Done

- `_provider_k3s_gcp_status` implemented
- `make status CLUSTER_PROVIDER=k3s-gcp` shows node + pod status
- `shellcheck scripts/lib/providers/k3s-gcp.sh` and relevant BATS suites pass
