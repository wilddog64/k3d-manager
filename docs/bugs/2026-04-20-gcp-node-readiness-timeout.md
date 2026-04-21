# Bug: GCP k3s node readiness timeout is too short

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/lib/providers/k3s-gcp.sh`

---

## Summary

`make up CLUSTER_PROVIDER=k3s-gcp` fails during the final verification step: "Waiting for node to be Ready...". Although the cluster bootstraps successfully in the background, the 150-second timeout in the provider script is insufficient for a fresh GCE instance.

---

## Root Cause

`scripts/lib/providers/k3s-gcp.sh` line 218 uses a 30-attempt loop with a 5s sleep.
Bootstrap times for k3s on GCE typically range from 180s to 300s. The loop exits with Error 1 before the API server is fully responsive.

---

## Proposed Fix

Increase the timeout to 300 seconds (60 attempts) to match the AWS provider's patient behavior.
