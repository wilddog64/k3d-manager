# Issue: Remote Vault Bridge Instability (socat)

**Date:** 2026-04-01
**Branch:** `k3d-manager-v1.0.2`

## Problem
The automated retrieval of secrets on the remote `ubuntu-k3s` cluster is failing because the `ClusterSecretStore` cannot establish a stable connection to the local Vault instance via the reverse SSH tunnel and `socat` bridge.

## Analysis
- **Authentication:** Successfully transitioned from Kubernetes auth to static **Vault Token** auth. The `vault-token` secret is present on the remote cluster.
- **Bridge Architecture:** 
    1. Local Mac `vault` pod → `port-forward` to Mac `localhost:8200`.
    2. Mac `localhost:8200` → SSH Reverse Tunnel (`-R 8200:localhost:8200`) → Remote EC2 `localhost:8200`.
    3. Remote EC2 `localhost:8200` → `socat` bridge → Remote EC2 `0.0.0.0:8201`.
    4. Remote `ubuntu-k3s` Service/Endpoint → Remote EC2 `10.0.1.204:8201`.
- **Failure Point:** The `socat` process on the remote server (Step 3) is unstable. It frequently terminates or fails to bind after the initial setup, leading to `connection refused` or `context deadline exceeded` errors in the External Secrets Operator (ESO) logs.
- **Missing Automation:** `socat` is not currently managed or installed by the `k3s.sh` or `acg.sh` plugins, requiring manual intervention during every sandbox lifecycle.

## Impact
Blocks the "All 5 Pods Running" milestone as services cannot retrieve database and message broker credentials from Vault.

## Recommended Follow-up
1. Incorporate `socat` installation into `deploy_app_cluster` (Linux path).
2. Formalize the Vault reverse bridge setup in the `tunnel.sh` plugin or as a dedicated `scripts/plugins/vault_bridge.sh`.
3. Use a more robust process manager (e.g., a simple systemd unit) for the remote `socat` bridge instead of `nohup` or `screen`.
