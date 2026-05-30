# Progress — k3d-manager

## Status
- **v1.4.11 SHIPPED** — PR #82 merged (57cd3bc3). ESO sync, acg-down macOS Tahoe fix, data-layer StatefulSet race, Keycloak group-ldap-mapper, ArgoCD RBAC, legacy app removal.
- **shopping-cart-infra PR #76 MERGED** (2026-05-29) — merge SHA `1e7044b7`. Removes legacy ArgoCD app definitions; switches to ApplicationSet model; updates Makefile and architecture.md. enforce_admins restored; docs/next-improvements branches remain active.
- **pre-push main-guard hook rollout completed** (2026-05-29) — shopping-cart-basket PR #12 merged (`a01e146`), shopping-cart-e2e-tests PR #4 merged (`2f048ba`), shopping-cart-frontend PR #26 merged (`9b9c2c2`), shopping-cart-infra PR #75 merged (`475d7c1`), shopping-cart-payment PR #22 merged (`3e25b8b`), shopping-cart-product-catalog PR #33 merged (`f425a9a`); enforce_admins restored on all 6; docs/next-improvements branches created.
- **infra ArgoCD stale refs fix committed/pushed** (2026-05-29) — shopping-cart-infra PR #76 now merged with commit `407e489` (stale refs fix part of PR #76).
- **networking directory.recurse fix committed/pushed** (2026-05-29) — shopping-cart-infra commit `1eeed15` on `docs/next-improvements`; spec-required PyYAML validation command was unavailable in this environment, so YAML was verified with Ruby's built-in parser instead.
- **serviceaccount imagePullSecrets patch committed/pushed** (2026-05-29) — k3d-manager commit `a53c752b` on `k3d-manager-v1.4.12`.
- **shopping-cart-infra PR #78 MERGED** (2026-05-29) — merge SHA `7881f35`. ExternalSecret/product-catalog-secrets SharedResourceWarning fix: data-layer duplicate removed; sole ownership with cicd/product-catalog app.
- **v1.4.10 SHIPPED** — PR #81 merged (`f8bad52d`). ArgoCD stability, bootstrap reliability, /tmp cleanup.
- **v1.4.9 SHIPPED** — Credential extraction and OIDC issuer fixes.

## Milestone: v1.4.11 (Data Layer GitOps + RBAC) — SHIPPED
- [x] ESO sync saturation timeout fix — commit `a4398fb4`; spec: `docs/bugs/v1.4.11-bugfix-eso-sync-saturation-timeout.md`
- [x] Keycloak group-ldap-mapper permanent fix — shopping-cart-infra `a3a88ee`, k3d-manager `ba391a7f`; spec: `docs/bugs/v1.4.11-bugfix-keycloak-missing-ldap-group-mapper.md`
- [x] shopping-cart-order actuator NPE fix — branch `fix/order-actuator-security-npe`, commit `6b8888c`; compile check timed out in this environment.
- [x] Data Layer GitOps consolidation — spec: `docs/plans/v1.4.10-data-layer-gitops-consolidation.md` (shopping-cart-infra PR #70: `7840441`)
- [x] Keycloak role-based MFA — spec: `docs/plans/v1.4.11-keycloak-mfa.md` (shopping-cart-infra PR #71: `0f13c0b`)
- [x] Keycloak reconcile sub-flow endpoint fix — spec: `docs/plans/v1.4.11-bugfix-reconcile-subflow-update-endpoint.md` (shopping-cart-infra PR #72 merged: `4c7c6ec`)
- [x] data-layer StatefulSet not-found race on fresh cluster — spec: `docs/bugs/v1.4.11-bugfix-data-layer-statefulset-not-found.md`; fix applied in `shopping_cart.sh` on `k3d-manager-v1.4.11`
- [x] acg-down password prompt on macOS Tahoe — commit `b1b5e599`; spec: `docs/bugs/v1.4.11-bugfix-acg-down-interactive-sudo-password-prompt.md`
- [x] ArgoCD RBAC fix: `product-catalog` → `shopping-cart-product-catalog` in `argocd-rbac-cm` (shopping-cart-infra: `8768955`)
- [x] order-service fix — PR #32 merged (`3e78feab`) — actuator NPE + Lombok processor + pre-push hook
- [x] pre-push main-guard hook rollout — shopping-cart-basket `c54c148`, shopping-cart-e2e-tests `0f398ab`, shopping-cart-frontend `4d0c8d3`, shopping-cart-infra `24e65f9`, shopping-cart-payment `c87f8b5`, shopping-cart-product-catalog `7b2fa2a`; spec: `docs/plans/v1.4.11-pre-push-main-guard-hook.md`
- [x] Remove legacy ArgoCD app definitions (basket-service/frontend/order-service/payment-service/product-catalog yamls) — shopping-cart-infra `c852bca`; spec: `docs/bugs/v1.4.11-bugfix-remove-legacy-argocd-app-definitions.md`
- [x] infra ArgoCD stale refs fix — shopping-cart-infra `407e489`; spec: `docs/plans/v1.4.12-bugfix-infra-argocd-stale-refs.md`
- [x] networking directory.recurse fix — shopping-cart-infra `1eeed15`; spec: `docs/plans/v1.4.12-bugfix-networking-directory-recurse.md`
- [x] serviceaccount imagePullSecrets patch — k3d-manager `a53c752b`; spec: `docs/plans/v1.4.12-bugfix-service-imagepullsecrets.md`
- [ ] Node.js 20→22 upgrade (all 5 shopping-cart CI workflows)

## Milestone: v1.4.12 (Reliability Hardening)
- [x] ExternalSecret/product-catalog-secrets SharedResourceWarning resolution — shopping-cart-infra PR #78 merged (`7881f35`); data-layer duplicate deleted
- [ ] Node.js 20→22 upgrade (all 5 shopping-cart CI workflows)

## Milestone: v1.4.10 (ArgoCD Stability) — SHIPPED
- [x] OIDC Issuer protocol mismatch resolution.
- [x] Keycloak configuration conflict fix.
- [x] ArgoCD infinite sync loop fix for `order-service-secrets`.
- [x] ArgoCD sync drift fix for `product-catalog-seed-script`.
- [x] Product seed race condition fix.
- [x] Resilient DB password reconciliation.
- [x] ArgoCD permission denied mismatch investigation (RCA in `shopping-cart-product-catalog/docs/bugs/`).
- [x] seed job `--wait=false` fix (`c27611a5`).
- [x] PR #81 merged (`f8bad52d`). All Copilot findings addressed.

## Milestone: v0.4.0 (Observability) — PLANNED
- [ ] Prometheus ServiceMonitors for core services.
- [ ] Grafana Dashboards integration.
- [ ] Cross-cluster ESO validation.
