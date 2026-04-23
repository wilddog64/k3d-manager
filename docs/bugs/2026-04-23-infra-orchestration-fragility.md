# Bug: ArgoCD Infrastructure Orchestration Fragility

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/plugins/argocd.sh`, `bin/acg-up`

---

## Summary

The infrastructure deployment flow is fragmented. `deploy_argocd` installs the ArgoCD server but does not automatically trigger the `deploy_argocd_bootstrap` sequence. This leaves the cluster in a "Clean but Empty" state where downstream tools (like `make up` or `acg-sync-apps`) fail with `PermissionDenied` because the expected Application objects do not exist.

---

## Reproduction Steps

1. Delete the local Hub: `k3d cluster delete k3d-cluster`.
2. Re-create Hub: `./scripts/k3d-manager deploy_cluster k3d`.
3. Install ArgoCD: `./scripts/k3d-manager deploy_argocd`.
4. Run `make sync-apps`.
5. Observe failure: `rpc error: code = PermissionDenied desc = permission denied`.

---

## Root Cause

1. **Decoupled Actions:** `deploy_argocd` and `deploy_argocd_bootstrap` are separate functions with no automatic chaining. 
2. **Security Quirk:** The ArgoCD CLI returns `PermissionDenied` when an application is not found, confusing users into thinking there is a credential issue.
3. **Missing Dependency:** `deploy_argocd` assumes Vault is already configured, but there is no "Infra Orchestrator" that enforces the [Vault -> ESO -> ArgoCD] dependency chain.

---

## Proposed Fix

1.  **Orchestrator Logic:** Implement a `deploy_infra` or `bootstrap_hub` function that enforces the correct sequence: `Vault -> ESO -> LDAP -> ArgoCD -> ArgoCD Bootstrap`.
2.  **Idempotency:** Ensure that each step in the chain can be safely re-run without manual intervention or data loss.

---

## Impact

Medium. Causes confusion and manual recovery steps for developers after a local cluster reset.
