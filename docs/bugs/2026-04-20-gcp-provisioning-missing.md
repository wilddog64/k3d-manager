# Bug: GCP provider is a skeleton and lacks provisioning logic

**Branch:** `recovery-v1.1.0-aws-first`
**Files Implicated:** `scripts/lib/providers/k3s-gcp.sh`

---

## Summary

After successful credential extraction and identity switch, `make up CLUSTER_PROVIDER=k3s-gcp` terminates without provisioning a cluster. The `k3s-gcp` provider module is currently a skeleton with placeholder functions, meaning no GCE instances are created, no k3s is installed, and no SSH tunnels are established.

---

## Reproduction Steps

1. Run `CLUSTER_PROVIDER=k3s-gcp make up`.
2. Wait for credential extraction and Google Login to succeed.
3. Observe terminal output:
   ```text
   INFO: [k3s-gcp] GCP cluster provisioning is not yet implemented (v1.1.0 recovery scope: credential flow only).
   INFO: [k3s-gcp] acg-up will exit after this step — use 'kubectl get nodes' to verify once a cluster is available.
   ```
4. Run `ssh ubuntu-gcp` or `kubectl get nodes`.
5. Observe failure: No remote instance exists to connect to.

---

## Root Cause

The `scripts/lib/providers/k3s-gcp.sh` file was deliberately created as a skeleton during Phase C to focus on the identity/credential blockers. However, this prevents a "Functional E2E" test from passing because the "Provisioning" phase of the tool is empty.

---

## Proposed Fix

Implement the actual provisioning logic in `scripts/lib/providers/k3s-gcp.sh`:
1.  **Firewall:** Automate `gcloud compute firewall-rules create` for port 6443.
2.  **Instance:** Automate `gcloud compute instances create` with the correct image and metadata.
3.  **Bootstrap:** Automate `k3sup install` to the remote IP.
4.  **Connectivity:** Automate `tunnel_start` and SSH config updates.

---

## Impact

The GCP provider is "extracted" but "immobilized." It cannot be claimed as "Working" or "Ready" until the tool can actually build the remote cluster automatically.
