# Bug: GCP CLI identity mismatch blocks SSH access

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/plugins/gcp.sh`, `scripts/lib/providers/k3s-gcp.sh`

---

## Summary

After running `make up CLUSTER_PROVIDER=k3s-gcp`, the user is unable to use the `ssh ubuntu-gcp` alias. Investigation confirms the `gcloud` CLI is authenticated as the Service Account (SA), which lacks permissions to list or manage compute instances in the ACG sandbox.

---

## Reproduction Steps

1. Run `make up CLUSTER_PROVIDER=k3s-gcp`.
2. Wait for successful credential extraction and cluster deployment.
3. Run `ssh ubuntu-gcp`.
4. Observe failure: The SSH alias cannot resolve or the underlying `gcloud compute instances list` command fails with "active account not selected" or permission errors.

---

## Root Cause

The current implementation of `gcp_get_credentials` and `_gcp_load_credentials` focuses on activating the Service Account key:

```bash
gcloud auth activate-service-account --key-file="..."
```

While this works for `k3sup` and initial provisioning, ACG platform security restricts SAs from performing management tasks like listing instances or adding SSH keys. These tasks **must** be performed by the interactive `cloud_user_...` account. 

Because the CLI is left in the SA identity state, the user's local `~/.ssh/config` (which relies on `gcloud compute instances describe`) is broken.

---

## Proposed Fix

1.  **Identity Switch:** Update `gcp_login` to perform a full `gcloud auth login` using the `GCP_USERNAME` and `GCP_PASSWORD` extracted from the Pluralsight dashboard.
2.  **Surgical Latch-on:** Since Chrome is the default browser, this login will open the Google OAuth "Add Session" screen. We must use Playwright to latch onto this session via CDP and automate the "I understand", "Continue", and "Allow" buttons.
3.  **Final Active Identity:** Ensure the CLI is left authenticated as the `cloud_user` at the end of the `make up` process.

---

## Impact

This is a **High Priority** bug. It prevents the user from ever accessing the remote Kubernetes node, rendering the GCP provider unusable for debugging or interactive work despite the cluster being "up".
