# Issue: acg-refresh drops ArgoCD cluster labels during secret refresh

**Branch:** `k3d-manager-v1.6.4`
**Date:** 2026-06-07
**Commits:** N/A (Fixed via Auto-Edit in session)
**Files:** `bin/acg-refresh`

---

## Symptom

After running `bin/acg-refresh` to restore a cluster connection, all ArgoCD applications targeting the `ubuntu-k3s` cluster suddenly went into an `Unknown` state.

Investigating with `argocd cluster list` showed that the `ubuntu-k3s` cluster had disappeared from the managed clusters list, even though the `cluster-ubuntu-k3s` secret still existed in the `cicd` namespace on the Hub cluster.

## Root Cause

The `bin/acg-refresh` script contains a logic to refresh the ArgoCD cluster secret with a new ServiceAccount token from the remote cluster. 

In Step 2b, the script generates a patch for the `cluster-ubuntu-k3s` secret. However, the YAML template used for this patch was missing the mandatory ArgoCD labels:

```yaml
  labels:
    argocd.argoproj.io/secret-type: cluster
    argocd.argoproj.io/cluster-name: ubuntu-k3s
```

Without these labels, ArgoCD's application controller does not recognize the Secret as a cluster definition, causing it to drop the connection to the remote cluster and mark all associated applications as `Unknown`.

## Resolution

1.  **Manual Fix:** Manually re-labeled the secret on the Hub cluster:
    ```bash
    kubectl --context k3d-k3d-cluster label secret cluster-ubuntu-k3s -n cicd \
      argocd.argoproj.io/secret-type=cluster \
      argocd.argoproj.io/cluster-name=ubuntu-k3s --overwrite
    ```
2.  **Code Fix:** Modified `bin/acg-refresh` to include the `labels` block in the secret patch template.

## Verification Results

### Before Fix (ArgoCD Status)
```text
NAME                            SYNC STATUS   HEALTH STATUS
data-layer                      Unknown       Unknown
shopping-cart-apps              Unknown       Unknown
```

### After Fix (ArgoCD Status)
```text
NAME                            SYNC STATUS   HEALTH STATUS
data-layer                      Synced        Healthy
shopping-cart-apps              Synced        Healthy
```

`argocd cluster list` now correctly displays `ubuntu-k3s`.
