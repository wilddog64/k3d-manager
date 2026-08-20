# Bug: ArgoCD Infrastructure Orchestration Fragility

**Branch:** `k3d-manager-v1.1.0`
**Files Implicated:** `scripts/plugins/argocd.sh`, `bin/acg-up`

---

## Summary

The infrastructure deployment flow is fragmented. `deploy_argocd` and `deploy_argocd_bootstrap` are separate, but the larger issue is that `make up` / `bin/acg-up` does not explicitly drive the full local Hub sequence. It assumes ArgoCD infrastructure already exists, then jumps straight to app-cluster registration and later expects operators to know that local UI/CLI access still requires a manual port-forward.

This creates multiple confusing partial states:

- ArgoCD may be installed but not bootstrapped ("clean but empty").
- `make up` may attempt ArgoCD-dependent actions without ever installing ArgoCD in that run.
- ArgoCD may be healthy in-cluster, yet appear "down" to operators because no local `argocd-server` port-forward is established for login.

---

## Reproduction Steps

1. Delete and recreate the local Hub.
2. Run `make up` on a fresh local stack.
3. Observe that `bin/acg-up` proceeds to ArgoCD-dependent registration logic without explicitly installing ArgoCD in that flow.
4. If ArgoCD was installed separately but no local access path is active, attempt `argocd login localhost:8081 --username admin --insecure`.
5. Observe `connection refused` until a manual port-forward is started.
6. If ArgoCD is installed without bootstrap, downstream tooling such as `make sync-apps` can hit empty-cluster / missing-application behavior.

---

## Root Cause

1. **Fragmented orchestration:** `deploy_argocd`, `deploy_argocd_bootstrap`, and local ArgoCD access setup are separate concerns with no single explicit orchestration path.
2. **`acg-up` assumption gap:** `bin/acg-up` performs ArgoCD-dependent registration work but does not explicitly install ArgoCD in that same flow.
3. **Bootstrap gap:** `deploy_argocd` and `deploy_argocd_bootstrap` remain decoupled, so ArgoCD can exist without the expected AppProject/ApplicationSet objects.
4. **Access gap:** ArgoCD can be healthy in `cicd`, but operators still cannot log in locally until they manually create a `kubectl port-forward` for `argocd-server`.
5. **Misleading symptoms:** The ArgoCD CLI can return confusing errors (`PermissionDenied`, `connection refused`) that look like auth problems when the real issue is missing bootstrap or missing local access.

---

## Proposed Fix

1.  **Orchestrator Logic:** Implement a single local Hub bootstrap path that enforces the correct sequence: `Vault -> ESO -> LDAP -> ArgoCD install -> ArgoCD bootstrap -> app-cluster registration`.
2.  **Idempotency:** Ensure each step can be safely re-run without manual intervention or data loss.
3.  **Operator Access UX:** Either establish a standard local ArgoCD access helper (port-forward/login) or clearly print the required command sequence when the server is healthy but not exposed locally.

---

## Impact

Medium. Causes confusion and manual recovery steps after local cluster resets because install, bootstrap, registration, and access are not presented as one coherent flow.
