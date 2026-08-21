# Bug: k3s-gcp is not registered in core cluster dispatcher

**Branch:** `recovery-v1.1.0-aws-first`
**Files Implicated:** `scripts/lib/core.sh`, `scripts/lib/provider.sh`

---

## Summary

When running `CLUSTER_PROVIDER=k3s-gcp make up`, the script fails during Step 2 (Provisioning) with the error: `ERROR: Unsupported cluster provider: k3s-gcp`.

Investigation reveals that while the GCP extraction plugin is complete, the `k3s-gcp` provider has not been added to the allowlist in the core dispatcher (`scripts/lib/core.sh`), nor does a provider module exist in `scripts/lib/providers/`.

---

## Reproduction Steps

1. Run `CLUSTER_PROVIDER=k3s-gcp make up`.
2. Wait for credential extraction to succeed.
3. Observe failure at Step 2:
   ```text
   INFO: [acg-up] Step 2/12 — Provisioning 3-node cluster...
   INFO: Detected macOS environment.
   ERROR: Unsupported cluster provider: k3s-gcp
   ```

---

## Root Cause

`scripts/lib/core.sh` contains a hardcoded list of supported providers in the `_cluster_provider` and `deploy_cluster` functions. This list currently only includes `k3d`, `orbstack`, `k3s`, and `k3s-aws`.

Additionally, the dispatcher in `scripts/lib/provider.sh` expects a provider script to exist at `scripts/lib/providers/k3s-gcp.sh`.

---

## Proposed Fix

1.  Update `scripts/lib/core.sh` to include `k3s-gcp` in the provider allowlist.
2.  Create a skeleton `scripts/lib/providers/k3s-gcp.sh` that implements `_provider_k3s_gcp_deploy_cluster`.
3.  For the purpose of this recovery phase, the GCP deploy function should be a placeholder that confirms the identity switch worked, as full GCP provisioning is out of scope for v1.1.0 recovery.

---

## Impact

The `make up` interface is completely blocked for GCP users, even though the extraction and identity logic is verified and working.
