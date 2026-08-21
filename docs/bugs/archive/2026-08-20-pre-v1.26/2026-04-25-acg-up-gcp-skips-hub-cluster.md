# Bug: make up CLUSTER_PROVIDER=k3s-gcp exits before creating Hub cluster

**Branch:** `k3d-manager-v1.2.0`
**File:** `bin/acg-up`

## Root Cause

`bin/acg-up` has an early exit at line 92 for `k3s-gcp` immediately after Step 2
(remote GCP cluster provisioning). This skips Step 3.5 (local Hub k3d cluster creation)
and Step 3.6 (Vault + LDAP + ArgoCD bootstrap), which are provider-agnostic — the Hub
cluster is always local k3d regardless of whether the app cluster is on AWS or GCP.

Only Step 3 (SSH tunnel via `tunnel_start`) is AWS-specific. Steps 5–12 are also
AWS-specific (hardwired `ubuntu-k3s` context, `ssh ubuntu`).

## Fix

Replace the early exit block with:
1. Gate `tunnel_start` (Step 3) behind `[[ "${_cluster_provider}" != "k3s-gcp" ]]`
2. Let Steps 3.5, 3.6, and 4 run for all providers
3. Add a new GCP early exit after Step 4 with a note that Steps 5–12 are not yet ported

**Old (lines 92–97):**
```bash
if [[ "${_cluster_provider}" == "k3s-gcp" ]]; then
  _info "[acg-up] GCP cluster deployed. Steps 3–12 (SSH tunnel, Vault, ESO, ArgoCD) are AWS-only and not yet ported for GCP."
  _info "[acg-up] Run 'kubectl get nodes' to verify the cluster."
  kubectl get nodes
  exit 0
fi

_info "[acg-up] Step 3/12 — Starting SSH tunnel..."
tunnel_start
```

**New:**
```bash
if [[ "${_cluster_provider}" != "k3s-gcp" ]]; then
  _info "[acg-up] Step 3/12 — Starting SSH tunnel..."
  tunnel_start
fi
```

And after Step 4 (Vault port-forward block), add:
```bash
if [[ "${_cluster_provider}" == "k3s-gcp" ]]; then
  _info "[acg-up] Steps 5–12 (ESO, ArgoCD registration, Vault bridge) not yet ported for GCP."
  _info "[acg-up] Hub cluster is up. GCP app cluster nodes:"
  kubectl get nodes --context ubuntu-gcp 2>/dev/null || true
  exit 0
fi
```
