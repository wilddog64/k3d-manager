# Bug: make sync-apps fails with cryptic error when Hub cluster context missing

**Branch:** `k3d-manager-v1.2.0`
**File:** `bin/acg-sync-apps`

## Root Cause

`bin/acg-sync-apps` attempts to port-forward `argocd-server` against `INFRA_CONTEXT`
(`k3d-k3d-cluster` by default) without first checking whether that context exists.
When the Hub cluster is not running, kubectl reports a confusing mid-flow error:

```
INFO: [sync-apps] Starting argocd-server port-forward...
INFO: [sync-apps] ERROR: argocd-server port-forward exited early — see .../acg-sync-apps-argocd-pf.log
error: context "k3d-k3d-cluster" does not exist
```

## Fix

Add a pre-flight context check immediately after the variable declarations (before the
port-forward attempt at line 141).

**Add after line 24 (`ARGOCD_APP=...`):**
```bash
if ! kubectl config get-contexts "${INFRA_CONTEXT}" >/dev/null 2>&1; then
  _info "[sync-apps] ERROR: Hub cluster context '${INFRA_CONTEXT}' not found — run 'make up' first"
  exit 1
fi
```
