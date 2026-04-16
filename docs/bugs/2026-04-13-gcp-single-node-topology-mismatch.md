# Bug: GCP provider provisions a single node instead of the standard 3-node cluster

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/lib/providers/k3s-gcp.sh`, `scripts/plugins/gcp.sh`, `Makefile`

---

## Summary

`k3s-gcp` currently provisions only one VM (`k3s-gcp-server`) and installs a single-node
k3s cluster. This differs from the AWS provider, which provisions a 3-node cluster and
exposes a uniform operational model (`ubuntu`, `ubuntu-1`, `ubuntu-2`).

Because ACG permits only one active sandbox at a time, provider choice should not change
cluster topology from the user's perspective. GCP should match the standard 3-node layout.

---

## Root Cause

The GCP provider was originally implemented as a lightweight skeleton / single-node full-stack
proof of concept. That scope was never lifted to match the AWS provider's 3-node contract,
so the provider now exposes command parity (`make up`, `make provision`) without topology parity.

---

## Expected Behavior

`make up CLUSTER_PROVIDER=k3s-gcp` should provision the same logical cluster shape as AWS:

- 1 server node
- 2 agent nodes
- agent join flow via `k3sup join`
- consistent SSH alias set and kubeconfig behavior

---

## Proposed Fix

1. Extend `scripts/lib/providers/k3s-gcp.sh` to create 3 VMs (server + 2 agents).
2. Update the provider to run `k3sup install` on the server and `k3sup join` for agents.
3. Reuse the standard SSH alias contract (`ubuntu-tunnel`, `ubuntu-1`, `ubuntu-2`).
4. Update tests and docs to reflect the multi-node GCP topology.

---

## Impact

Users experience different topology, SSH entry points, and operational expectations across
providers, which breaks the intended cloud-agnostic UX.
