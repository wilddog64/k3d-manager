# Active Context — k3d-manager

## Current Status
- Current branch: `k3d-manager-v1.4.11` (created from merge SHA `f8bad52d`).
- **ESO sync saturation timeout fix committed and pushed** — commit `a4398fb4` on `k3d-manager-v1.4.11` (`fix(shopping_cart): annotate all ESOs before waiting to prevent sync saturation timeout`).
- **Keycloak group-ldap-mapper fix committed and pushed** — shopping-cart-infra branch `chore/add-group-ldap-mapper`, commit `a3a88ee`; k3d-manager commit `ba391a7f` on `k3d-manager-v1.4.11`.
- **shopping-cart-order actuator NPE fix committed and pushed** — branch `fix/order-actuator-security-npe`, commit `6b8888c` (`fix(security): add dedicated actuator filter chain to prevent ExceptionTranslationFilter NPE`).
- **Remove legacy ArgoCD app definitions committed and pushed** — shopping-cart-infra branch `fix/remove-legacy-argocd-apps`, commit `c852bca` (`fix(argocd): remove legacy app definitions superseded by services-git ApplicationSet`).
- **v1.4.11 DATA LAYER COMPLETE** — shopping-cart-infra PR #70 merged (`7840441`). ArgoCD `prune: false` for data layer.
- **v1.4.11 KEYCLOAK MFA COMPLETE** — shopping-cart-infra PR #71 merged (`0f13c0b`). Role-based TOTP for platform-admin/platform-developer.
- **v1.4.11 RECONCILE SUBFLOW FIX MERGED** — shopping-cart-infra PR #72 merged (`4c7c6ec`). Keycloak reconcile sub-flow endpoint now correctly targets update operation.
- **v1.4.11 ARGOCD RBAC COMPLETE** — shopping-cart-infra commit `8768955`. `catalog-admin` now references `shopping-cart-product-catalog`.
- **shopping-cart-infra PR #73 MERGED** (2026-05-29) — merge SHA `eccb4872`. Accumulated infra improvements (OIDC issuer URL, LDAP staging path, Keycloak secret templates). Retrospective: `docs/retro/2026-05-29-pr73-retrospective.md`. enforce_admins restored on shopping-cart-infra main. Next branch `docs/next-improvements` created.
- **shopping-cart-infra PR #74 MERGED** (2026-05-29) — merge SHA `fd234094`. Keycloak LDAP group-mapper reconciliation fix. Retrospective: `docs/retro/2026-05-29-pr74-retrospective.md`. enforce_admins restored on shopping-cart-infra main. docs/next-improvements branch synced.
- **v1.4.10 SHIPPED** — PR #81 merged (`f8bad52d`). ArgoCD stability, bootstrap reliability, /tmp cleanup.
- **enforce_admins:** restored on k3d-manager main after v1.4.10 merge; restored on shopping-cart-infra main after PR #73 merge.

## Carry-Forward Items
- **Data Layer GitOps consolidation** — complete; commit SHAs: k3d-manager `18be9e09`, shopping-cart-infra `0e7e2a6`.
- **Keycloak role-based MFA** — complete; commit SHA: shopping-cart-infra `d8603dd`.
- **ArgoCD RBAC fix** — complete; commit SHA: shopping-cart-infra `8768955`.
- **lib-acg Provider-Plugin architecture** — spec at `lib-acg/docs/plans/v1.2.0-provider-plugin-architecture.md`.

## Recent Changes
- **ESO sync saturation timeout fix completed** — split annotate and wait loops in `shopping_cart_sync_vault_backed_secrets`, captured existing ESOs before waiting, and increased `kubectl wait` timeout to 300s; commit `a4398fb4` pushed to origin.
- **Keycloak group-ldap-mapper fix completed** — added `group-ldap-mapper` reconciliation to `identity/keycloak/keycloak-reconcile-hook-job.yaml` in shopping-cart-infra and Step 10d.7 to `bin/acg-up` in k3d-manager; commits `a3a88ee` and `ba391a7f` pushed to origin.
- **shopping-cart-order actuator NPE fix** — added dedicated `@Order(0)` actuator filter chain in `SecurityConfig.java`, moved the main chain to `@Order(1)`, and bumped `OAuth2SecurityConfig` to `@Order(2)`; commit `6b8888c` pushed on `fix/order-actuator-security-npe`. `mvn compile` timed out in this environment after 180s (`exit 124`).
- **Remove legacy ArgoCD app definitions completed** — deleted `argocd/applications/basket-service.yaml`, `frontend.yaml`, `order-service.yaml`, `payment-service.yaml`, and `product-catalog.yaml` from `shopping-cart-infra`; commit `c852bca` pushed on `fix/remove-legacy-argocd-apps`.
- **shopping-cart-infra PR #72 merged** (`4c7c6ec`) — reconcile sub-flow endpoint fix complete; enforce_admins restored on main.
- **data-layer StatefulSet race fix** — `deploy_shopping_cart_data()` now polls for StatefulSet existence (300s timeout each) before `kubectl rollout status`; spec at `docs/bugs/v1.4.11-bugfix-data-layer-statefulset-not-found.md`.
- **bin/acg-down pre-auth removed** — dropped `_run_command --interactive-sudo --quiet -- true` block; caused `sudo: unable to allocate pty` on macOS Tahoe; NOPASSWD sudoers rules cover all actual privileged commands.
- **Keycloak role-based MFA completed** — conditional OTP browser flow in `keycloak-reconcile-hook-job.yaml`.
- **Data Layer GitOps consolidation completed** — removed imperative data-layer `kubectl apply`; set `prune: false` in `argocd/applications/data-layer.yaml`.
- **ArgoCD RBAC fix completed** — updated `catalog-admin` policies in `argocd/config/argocd-rbac-cm.yaml` to reference `shopping-cart/shopping-cart-product-catalog`.

## Assigned to Codex
- **acg-down password prompt fix** — spec: `docs/bugs/v1.4.11-bugfix-acg-down-interactive-sudo-password-prompt.md`; replace `--interactive-sudo` → `--prefer-sudo` on 5 calls in `bin/acg-down` mac block

## Next Steps
- Commit data-layer StatefulSet race fix + spec + acg-down pre-auth removal on `k3d-manager-v1.4.11`.
- Codex: Node.js 20→22 upgrade across all 5 shopping-cart repos (workflows).
- Add public domain to Keycloak realm config.
- **shopping-cart-order PR #32 MERGED** (`3e78feab`) — actuator NPE + Lombok processor + pre-push hook. enforce_admins restored. Next branch: `docs/next-improvements`.
- **pre-push main-guard hook** — `scripts/hooks/pre-push` committed to k3d-manager (`2c0589ac`); `.githooks/pre-push` committed to shopping-cart-order; Codex to add to remaining 6 shopping-cart repos on `chore/add-pre-push-hook` branches; spec at `docs/plans/v1.4.11-pre-push-main-guard-hook.md`.

## Cluster State Note (2026-05-29)
- Keycloak `otp-conditional-subflow` manually repaired via kcadm.sh — was DISABLED+empty due to reconcile bug.
- Duplicate ArgoCD apps identified: `basket-service`/`shopping-cart-basket`, `product-catalog`/`shopping-cart-product-catalog`, etc. — root cause: k3d-manager `services/` kustomize wrappers vs `shopping-cart-infra/argocd/applications/` direct apps.
- Keycloak LDAP group mapper added manually: `group-ldap-mapper` (ID `a54709dc`) on LDAP federation `ee968f21`; 10 groups imported. Permanent fix spec at `docs/bugs/v1.4.11-bugfix-keycloak-missing-ldap-group-mapper.md`.
- ArgoCD RBAC permission denied root cause: missing group mapper → empty groups JWT claim → falls through to `role:readonly`. Fixed by adding group mapper + triggering LDAP group sync.
- Proceed with Node.js 20→22 upgrade (all 5 shopping-cart repos).
