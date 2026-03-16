# Issue: Ubuntu k3s Rebuild Instability and Connectivity

**Date:** 2026-03-16
**Component:** `scripts/plugins/shopping_cart.sh`, `scripts/lib/providers/k3s.sh`

## Description

During the Gemini cluster rebuild smoke test (v0.9.3), several issues were identified with the Ubuntu app cluster lifecycle:

1.  **Incomplete Uninstall:** `k3s-uninstall.sh` (provided by k3s) only removes the service and binaries but leaves behind the SQLite database (`/var/lib/rancher/k3s/server/db`) and Kubernetes state. This causes "ghost" nodes and stale Helm releases to persist after a reinstall.
2.  **Pod Connectivity (OrbStack to Parallels):** Pods in the infra cluster (running via Docker/OrbStack) are unable to reach the Ubuntu VM API server (`10.211.55.14`) directly, even though the M2 Air host can. This breaks ArgoCD's ability to manage the cluster.
3.  **ArgoCD Registration Failure:** `argocd cluster add` fails due to the connectivity issue mentioned above and also because the `argocd-server` pod lacks `curl` or `nc` for debugging.

## Evidence

-   **Stale State:** After running `k3s-uninstall.sh` and reinstalling, `kubectl get nodes` still showed `k3s-automation` (NotReady) from a previous installation.
-   **Connection Refused:** `kubectl run test-curl --image=curlimages/curl ... -- curl -k https://10.211.55.14:6443/version` returned `Connection refused`.
-   **EOF in ArgoCD:** `argocd cluster add` returned `unexpected EOF` or `connection reset by peer` when attempting to reach the Ubuntu cluster.

## Fixes/Workarounds Applied

1.  **Hard Cleanup:** Manually ran `sudo rm -rf /etc/rancher /var/lib/rancher /var/lib/kubelet` on the Ubuntu VM before reinstalling k3s.
2.  **SSH Tunneling:** Established an SSH tunnel on the M2 Air host: `ssh -L 0.0.0.0:6443:localhost:6443 -N ubuntu`.
3.  **Manual ArgoCD Secret:** Manually created the ArgoCD cluster secret in the `cicd` namespace on the infra cluster, pointing to `https://host.k3d.internal:6443`.
4.  **Vault Token Auth:** Switched the `ClusterSecretStore` on the app cluster to use a static Vault token with the `eso-reader` policy, as the Kubernetes auth mount was failing due to CA cert validation issues over the tunnel.

## Recommendation

-   Update `destroy_k3s_cluster` to include a thorough cleanup of `/var/lib/rancher`.
-   Formalize the SSH tunneling requirement or implement a more robust bridge for OrbStack-to-Parallels connectivity.
-   Automate the cross-cluster Vault token exchange if Kubernetes auth remains unreliable in the local lab environment.
