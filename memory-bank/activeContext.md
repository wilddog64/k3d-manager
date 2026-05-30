# Active Context — k3d-manager

## Current Status
- Current branch: `k3d-manager-v1.4.12` (created from merge SHA `57cd3bc3`).
- **shopping-cart-infra PR #78 MERGED** (2026-05-29, merge SHA `7881f35`) — ExternalSecret/product-catalog-secrets SharedResourceWarning fix. Deleted `data-layer/secrets/postgres-products-apps-externalsecret.yaml` — sole ownership of `product-catalog-secrets` now with `shopping-cart-product-catalog` Application. enforce_admins restored on shopping-cart-infra main. Next branch: `docs/next-improvements`. Retro: `docs/retro/2026-05-29-product-catalog-externalsecret-fix-retrospective.md`.
- **v1.4.11 SHIPPED** — PR #82 merged (57cd3bc3); enforce_admins restored; k3d-manager-v1.4.12 branch created.
- **shopping-cart-infra PR #76 post-merge housekeeping completed** (2026-05-29) — PR #76 merged SHA `1e7044b7`. Removed legacy ArgoCD app definitions (basket-service, frontend, order-service, payment-service, product-catalog YAMLs). Updated Makefile and docs/architecture.md for ApplicationSet model. enforce_admins restored on shopping-cart-infra main. docs/next-improvements branch synced. README and architecture.md docs audited — no stale references found (PR #76 updated architecture.md correctly).
- **Post-merge housekeeping completed** (2026-05-29) — shopping-cart-basket PR #12 (`a01e146`), shopping-cart-e2e-tests PR #4 (`2f048ba`), shopping-cart-frontend PR #26 (`9b9c2c2`), shopping-cart-infra PR #75 (`475d7c1`), shopping-cart-payment PR #22 (`3e25b8b`), shopping-cart-product-catalog PR #33 (`f425a9a`) all merged; enforce_admins restored on all 6 repos; docs/next-improvements branches created on all 6 repos.
- **ESO sync saturation timeout fix shipped** — commit `a4398fb4` on `k3d-manager-v1.4.11` (`fix(shopping_cart): annotate all ESOs before waiting to prevent sync saturation timeout`).
- **Keycloak group-ldap-mapper fix committed and pushed** — shopping-cart-infra branch `chore/add-group-ldap-mapper`, commit `a3a88ee`; k3d-manager commit `ba391a7f` on `k3d-manager-v1.4.11`.
- **shopping-cart-order actuator NPE fix committed and pushed** — branch `fix/order-actuator-security-npe`, commit `6b8888c` (`fix(security): add dedicated actuator filter chain to prevent ExceptionTranslationFilter NPE`).
- **Remove legacy ArgoCD app definitions committed and pushed** — shopping-cart-infra branch `fix/remove-legacy-argocd-apps`, commit `c852bca` (`fix(argocd): remove legacy app definitions superseded by services-git ApplicationSet`).
- **Infra ArgoCD stale refs fix committed and pushed** — shopping-cart-infra branch `fix/remove-legacy-argocd-apps`, commit `407e489` (`fix(docs): update Makefile argocd targets and architecture.md for ApplicationSet model`).
- **Networking directory.recurse fix committed and pushed** — shopping-cart-infra branch `docs/next-improvements`, commit `1eeed15` (`fix(argocd): remove redundant directory.recurse: false from networking.yaml — causes perpetual OutOfSync`).
- **ServiceAccount imagePullSecrets patch committed and pushed** — commit `a53c752b` on `k3d-manager-v1.4.12` (`fix(services): add imagePullSecrets patch to named ServiceAccounts — ghcr.io pull was 401 with non-default SA`).
- **acg-down password prompt fix committed and pushed** — commit `b1b5e599` on `k3d-manager-v1.4.11` (`fix(acg-down): replace --interactive-sudo with --prefer-sudo to eliminate password prompt on macOS Tahoe`).
- **Pre-push main-guard hook rollout completed** — shopping-cart-basket `c54c148`, shopping-cart-e2e-tests `0f398ab`, shopping-cart-frontend `4d0c8d3`, shopping-cart-infra `24e65f9`, shopping-cart-payment `c87f8b5`, shopping-cart-product-catalog `7b2fa2a`; all pushed on `chore/add-pre-push-hook`.
- **v1.4.11 DATA LAYER COMPLETE** — shopping-cart-infra PR #70 merged (`7840441`). ArgoCD `prune: false` for data layer.
- **v1.4.11 KEYCLOAK MFA COMPLETE** — shopping-cart-infra PR #71 merged (`0f13c0b`). Role-based TOTP for platform-admin/platform-developer.
- **v1.4.11 RECONCILE SUBFLOW FIX MERGED** — shopping-cart-infra PR #72 merged (`4c7c6ec`). Keycloak reconcile sub-flow endpoint now correctly targets update operation.
- **v1.4.11 ARGOCD RBAC COMPLETE** — shopping-cart-infra commit `8768955`. `catalog-admin` now references `shopping-cart-product-catalog`.
- **shopping-cart-infra PR #73 MERGED** (2026-05-29) — merge SHA `eccb4872`. Accumulated infra improvements (OIDC issuer URL, LDAP staging path, Keycloak secret templates). Retrospective: `docs/retro/2026-05-29-pr73-retrospective.md`. enforce_admins restored on shopping-cart-infra main. Next branch `docs/next-improvements` created.
- **shopping-cart-infra PR #74 MERGED** (2026-05-29) — merge SHA `fd234094`. Keycloak LDAP group-mapper reconciliation fix. Retrospective: `docs/retro/2026-05-29-pr74-retrospective.md`. enforce_admins restored on shopping-cart-infra main. docs/next-improvements branch synced.
- **v1.4.10 SHIPPED** — PR #81 merged (`f8bad52d`). ArgoCD stability, bootstrap reliability, /tmp cleanup.
- **enforce_admins:** restored on k3d-manager main after v1.4.10 merge; restored on shopping-cart-infra main after PR #73 merge.

## Carry-Forward Items
- **ExternalSecret/product-catalog-secrets SharedResourceWarning** — claimed by both cicd/product-catalog and data-layer ArgoCD apps; requires follow-on fix in v1.4.12
- **Data Layer GitOps consolidation** — complete; commit SHAs: k3d-manager `18be9e09`, shopping-cart-infra `0e7e2a6`.
- **Keycloak role-based MFA** — complete; commit SHA: shopping-cart-infra `d8603dd`.
- **ArgoCD RBAC fix** — complete; commit SHA: shopping-cart-infra `8768955`.
- **lib-acg Provider-Plugin architecture** — spec at `lib-acg/docs/plans/v1.2.0-provider-plugin-architecture.md`.

## Recent Changes
- **ESO sync saturation timeout fix completed** — split annotate and wait loops in `shopping_cart_sync_vault_backed_secrets`, captured existing ESOs before waiting, and increased `kubectl wait` timeout to 300s; commit `a4398fb4` pushed to origin.
- **Keycloak group-ldap-mapper fix completed** — added `group-ldap-mapper` reconciliation to `identity/keycloak/keycloak-reconcile-hook-job.yaml` in shopping-cart-infra and Step 10d.7 to `bin/acg-up` in k3d-manager; commits `a3a88ee` and `ba391a7f` pushed to origin.
- **shopping-cart-order actuator NPE fix** — added dedicated `@Order(0)` actuator filter chain in `SecurityConfig.java`, moved the main chain to `@Order(1)`, and bumped `OAuth2SecurityConfig` to `@Order(2)`; commit `6b8888c` pushed on `fix/order-actuator-security-npe`. `mvn compile` timed out in this environment after 180s (`exit 124`).
- **Remove legacy ArgoCD app definitions completed** — deleted `argocd/applications/basket-service.yaml`, `frontend.yaml`, `order-service.yaml`, `payment-service.yaml`, and `product-catalog.yaml` from `shopping-cart-infra`; commit `c852bca` pushed on `fix/remove-legacy-argocd-apps`.
- **Infra ArgoCD stale refs fix completed** — updated `Makefile` ArgoCD targets and `docs/architecture.md` to the ApplicationSet model; commit `407e489` pushed on `fix/remove-legacy-argocd-apps`.
- **Networking directory.recurse fix completed** — removed the redundant `directory.recurse: false` block from `argocd/applications/networking.yaml`; commit `1eeed15` pushed on `docs/next-improvements`. The spec-required PyYAML validation command failed in this environment because `PyYAML` is not installed; verified with `ruby -e \"require 'yaml'; YAML.load_file(...)\"` instead.
- **ServiceAccount imagePullSecrets patch completed** — appended `imagePullSecrets: [{name: ghcr-pull-secret}]` patches to the named ServiceAccounts in all four service kustomizations; commit `a53c752b` pushed on `k3d-manager-v1.4.12`. `kubectl kustomize` validated basket, order, payment, and product-catalog after fetching remote bases.
- **acg-down password prompt fix completed** — replaced `--interactive-sudo` with `--prefer-sudo` in the macOS launchd teardown block of `bin/acg-down`; commit `b1b5e599` pushed on `k3d-manager-v1.4.11`. `shellcheck -S warning bin/acg-down` passed with no output.
- **Pre-push main-guard hook rollout completed** — added `.githooks/pre-push` to shopping-cart-basket `c54c148`, shopping-cart-e2e-tests `0f398ab`, shopping-cart-frontend `4d0c8d3`, shopping-cart-infra `24e65f9`, shopping-cart-payment `c87f8b5`, and shopping-cart-product-catalog `7b2fa2a`; each branch `chore/add-pre-push-hook` pushed to origin.
- **shopping-cart-infra PR #72 merged** (`4c7c6ec`) — reconcile sub-flow endpoint fix complete; enforce_admins restored on main.
- **data-layer StatefulSet race fix** — `deploy_shopping_cart_data()` now polls for StatefulSet existence (300s timeout each) before `kubectl rollout status`; spec at `docs/bugs/v1.4.11-bugfix-data-layer-statefulset-not-found.md`.
- **bin/acg-down pre-auth removed** — dropped `_run_command --interactive-sudo --quiet -- true` block; caused `sudo: unable to allocate pty` on macOS Tahoe; NOPASSWD sudoers rules cover all actual privileged commands.
- **Keycloak role-based MFA completed** — conditional OTP browser flow in `keycloak-reconcile-hook-job.yaml`.
- **Data Layer GitOps consolidation completed** — removed imperative data-layer `kubectl apply`; set `prune: false` in `argocd/applications/data-layer.yaml`.
- **ArgoCD RBAC fix completed** — updated `catalog-admin` policies in `argocd/config/argocd-rbac-cm.yaml` to reference `shopping-cart/shopping-cart-product-catalog`.
- **shopping-cart-infra PR #76 merged** (2026-05-29) — removed legacy ArgoCD app definitions; switched to ApplicationSet model; updated Makefile and docs/architecture.md. Docs audit: README and architecture.md checked — no stale app-of-apps references remained (PR #76 updated architecture.md correctly to describe ApplicationSet deployment model).

## Assigned to Codex
- None.

## Next Steps
- Commit data-layer StatefulSet race fix + spec + acg-down pre-auth removal on `k3d-manager-v1.4.11`.
- Codex: Node.js 20→22 upgrade across all 5 shopping-cart repos (workflows).
- Add public domain to Keycloak realm config.
- **shopping-cart-order PR #32 MERGED** (`3e78feab`) — actuator NPE + Lombok processor + pre-push hook. enforce_admins restored. Next branch: `docs/next-improvements`.
- ExternalSecret/product-catalog-secrets SharedResourceWarning follow-up.

## Cluster State Note (2026-05-29)
- Keycloak `otp-conditional-subflow` manually repaired via kcadm.sh — was DISABLED+empty due to reconcile bug.
- Duplicate ArgoCD apps identified: `basket-service`/`shopping-cart-basket`, `product-catalog`/`shopping-cart-product-catalog`, etc. — root cause: k3d-manager `services/` kustomize wrappers vs `shopping-cart-infra/argocd/applications/` direct apps.
- Keycloak LDAP group mapper added manually: `group-ldap-mapper` (ID `a54709dc`) on LDAP federation `ee968f21`; 10 groups imported. Permanent fix spec at `docs/bugs/v1.4.11-bugfix-keycloak-missing-ldap-group-mapper.md`.
- ArgoCD RBAC permission denied root cause: missing group mapper → empty groups JWT claim → falls through to `role:readonly`. Fixed by adding group mapper + triggering LDAP group sync.
- Proceed with Node.js 20→22 upgrade (all 5 shopping-cart repos).
