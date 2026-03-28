# Issue: ArgoCD Sync Failure — ACG Sandbox Unreachable

**Date:** 2026-03-28
**Branch:** `k3d-manager-v0.9.19`

## Problem
Attempting to sync `order-service` and `product-catalog` in ArgoCD failed due to connection refused on the app cluster API server (`https://host.k3d.internal:6443`).

## Analysis
- ArgoCD CLI reported `rpc error: code = Unauthenticated desc = invalid session: token has invalid claims: token is expired`.
- Successfully logged in as admin to `127.0.0.1:8119` (ArgoCD server port-forward).
- Sync command failed to reach the cluster.
- Investigation shows the SSH tunnel is down:
  - `nc -zv 127.0.0.1 6443` returns `Connection refused`.
  - `ssh ubuntu` returns `Operation timed out`.
- `acg_status` reveals that AWS credentials have expired:
  ```text
  ERROR: [acg] AWS credentials invalid or expired. Update ~/.aws/credentials from the ACG console.
  ```

## Root Cause
The ACG sandbox session has expired, and the AWS credentials in `~/.aws/credentials` are no longer valid. The ubuntu-k3s VM is either stopped or unreachable via the current SSH configuration.

## Recommended Follow-up
1. Log into the Pluralsight (ACG) console and start a new cloud playground sandbox.
2. Update `~/.aws/credentials` with the new sandbox credentials.
3. Run `acg_provision` to restore the app cluster (or `acg_status` to check if it's still there).
4. Restart the tunnel and retry the ArgoCD sync.
