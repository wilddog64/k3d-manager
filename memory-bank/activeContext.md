# Active Context — k3d-manager

## Current Status
- Current branch: `k3d-manager-v1.4.11` (created from merge SHA `f8bad52d`).
- **v1.4.11 DATA LAYER COMPLETE** — shopping-cart-infra PR #70 merged (`7840441`). ArgoCD `prune: false` for data layer.
- **v1.4.11 KEYCLOAK MFA COMPLETE** — shopping-cart-infra PR #71 merged (`0f13c0b`). Role-based TOTP for platform-admin/platform-developer.
- **v1.4.11 RECONCILE SUBFLOW FIX MERGED** — shopping-cart-infra PR #72 merged (`4c7c6ec`). Keycloak reconcile sub-flow endpoint now correctly targets update operation.
- **v1.4.11 ARGOCD RBAC COMPLETE** — shopping-cart-infra commit `8768955`. `catalog-admin` now references `shopping-cart-product-catalog`.
- **v1.4.10 SHIPPED** — PR #81 merged (`f8bad52d`). ArgoCD stability, bootstrap reliability, /tmp cleanup.
- **enforce_admins:** restored on k3d-manager main after v1.4.10 merge; restored on shopping-cart-infra main after v1.4.11 reconcile subflow merge.

## Carry-Forward Items
- **Data Layer GitOps consolidation** — complete; commit SHAs: k3d-manager `18be9e09`, shopping-cart-infra `0e7e2a6`.
- **Keycloak role-based MFA** — complete; commit SHA: shopping-cart-infra `d8603dd`.
- **ArgoCD RBAC fix** — complete; commit SHA: shopping-cart-infra `8768955`.
- **lib-acg Provider-Plugin architecture** — spec at `lib-acg/docs/plans/v1.2.0-provider-plugin-architecture.md`.

## Recent Changes
- **shopping-cart-infra PR #72 merged** (`4c7c6ec`) — reconcile sub-flow endpoint fix complete; enforce_admins restored on main.
- **data-layer StatefulSet race fix** — `deploy_shopping_cart_data()` now polls for StatefulSet existence (300s timeout each) before `kubectl rollout status`; spec at `docs/bugs/v1.4.11-bugfix-data-layer-statefulset-not-found.md`.
- **bin/acg-down pre-auth removed** — dropped `_run_command --interactive-sudo --quiet -- true` block; caused `sudo: unable to allocate pty` on macOS Tahoe; NOPASSWD sudoers rules cover all actual privileged commands.
- **Keycloak role-based MFA completed** — conditional OTP browser flow in `keycloak-reconcile-hook-job.yaml`.
- **Data Layer GitOps consolidation completed** — removed imperative data-layer `kubectl apply`; set `prune: false` in `argocd/applications/data-layer.yaml`.
- **ArgoCD RBAC fix completed** — updated `catalog-admin` policies in `argocd/config/argocd-rbac-cm.yaml` to reference `shopping-cart/shopping-cart-product-catalog`.

## Next Steps
- Commit data-layer StatefulSet race fix + spec + acg-down pre-auth removal on `k3d-manager-v1.4.11`.
- Codex: Node.js 20→22 upgrade across all 5 shopping-cart repos (workflows).
- Add public domain to Keycloak realm config.
- Permanent fix: add group-ldap-mapper to `keycloak-reconcile-hook-job.yaml` (shopping-cart-infra) + `bin/acg-up` Step 10d.7; spec at `docs/bugs/v1.4.11-bugfix-keycloak-missing-ldap-group-mapper.md`.

## Cluster State Note (2026-05-29)
- Keycloak `otp-conditional-subflow` manually repaired via kcadm.sh — was DISABLED+empty due to reconcile bug.
- Duplicate ArgoCD apps identified: `basket-service`/`shopping-cart-basket`, `product-catalog`/`shopping-cart-product-catalog`, etc. — root cause: k3d-manager `services/` kustomize wrappers vs `shopping-cart-infra/argocd/applications/` direct apps.
- Keycloak LDAP group mapper added manually: `group-ldap-mapper` (ID `a54709dc`) on LDAP federation `ee968f21`; 10 groups imported. Permanent fix spec at `docs/bugs/v1.4.11-bugfix-keycloak-missing-ldap-group-mapper.md`.
- ArgoCD RBAC permission denied root cause: missing group mapper → empty groups JWT claim → falls through to `role:readonly`. Fixed by adding group mapper + triggering LDAP group sync.
- Proceed with Node.js 20→22 upgrade (all 5 shopping-cart repos).
