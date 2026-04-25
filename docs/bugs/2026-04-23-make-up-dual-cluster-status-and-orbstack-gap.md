# Bug: `make up` does not report dual-cluster readiness clearly and does not guide local runtime startup

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `Makefile`, `bin/acg-up`, `bin/acg-status`, `scripts/plugins/tunnel.sh`

---

## Summary

`make up` completes a mixed local/remote orchestration flow, but the operator-facing status remains ambiguous. The stack depends on both:

- the local Hub / infra cluster (`k3d-k3d-cluster`, OrbStack-backed), and
- the remote app cluster (`ubuntu-k3s`),

yet the current workflow does not end with a clear dual-cluster readiness summary.

This leads to confusing states where:

- the remote cluster is healthy while local Hub components are degraded,
- tunnel status appears down even when key forwarded endpoints are working,
- ArgoCD is healthy in-cluster but operators still cannot log in because local access setup is manual,
- OrbStack may not be running, but the workflow does not clearly distinguish that from downstream cluster/component failures.

---

## Reproduction Steps

1. Run `make up`.
2. Observe that follow-up troubleshooting still requires several manual checks across local Hub, tunnel, Vault, ArgoCD, and the remote app cluster.
3. Run `make status` and note that the tunnel line may not reflect the actual health of the forwarded Kubernetes API endpoint.
4. Attempt ArgoCD login locally and note that an additional manual port-forward is required even when ArgoCD is healthy in `cicd`.

---

## Root Cause

1. **Mixed topology without one summary:** The workflow spans two clusters but does not end with one authoritative readiness report.
2. **Misleading tunnel probe:** Local tunnel status is reduced to a simplistic localhost check rather than endpoint-aware health semantics.
3. **Access/setup gap:** In-cluster service health and local operator access are treated as separate concerns, but not surfaced together.
4. **Runtime assumption gap:** The local Hub depends on OrbStack, but the workflow does not clearly report or optionally remediate that prerequisite.

---

## Proposed Fix

1. Add a final dual-cluster status summary to `make up` / `bin/acg-up` covering:
   - OrbStack/runtime state
   - local Hub cluster reachability
   - Vault health/seal state
   - ArgoCD install/bootstrap/access hints
   - remote app cluster reachability
   - registration / ESO / ClusterSecretStore readiness
2. Improve tunnel reporting so it reflects actual endpoint behavior rather than a misleading single probe.
3. Optionally support OrbStack startup when the local runtime is not running, gated behind an explicit flag or environment variable.

---

## Impact

Medium. The stack can be healthy, partially healthy, or locally inaccessible while the current UX makes those states hard to distinguish quickly.
