# Progress — k3d-manager

## Status
- **Keycloak group-ldap-mapper fix committed/pushed** (2026-05-29) — shopping-cart-infra commit `a3a88ee` on `chore/add-group-ldap-mapper`; k3d-manager commit `ba391a7f` on `k3d-manager-v1.4.11`.
- **shopping-cart-order actuator NPE fix committed/pushed** (2026-05-29) — branch `fix/order-actuator-security-npe`, commit `6b8888c`; compile verification timed out in this environment (`timeout 180s mvn compile`, exit `124`).
- **v1.4.11 PARTIALLY COMPLETE** (2026-05-29) — Keycloak sub-flow fix merged (`4c7c6ec`); ArgoCD RBAC fix merged (`8768955`); shopping-cart-infra PR #73 merged (`eccb487`); post-merge housekeeping complete; data-layer StatefulSet race fix pending commit; Node.js 20→22 upgrade pending.
- **v1.4.10 SHIPPED** — PR #81 merged (`f8bad52d`). ArgoCD stability, bootstrap reliability, /tmp cleanup.
- **v1.4.9 SHIPPED** — Credential extraction and OIDC issuer fixes.

## Milestone: v1.4.11 (Data Layer GitOps + RBAC)
- [x] Keycloak group-ldap-mapper permanent fix — shopping-cart-infra `a3a88ee`, k3d-manager `ba391a7f`; spec: `docs/bugs/v1.4.11-bugfix-keycloak-missing-ldap-group-mapper.md`
- [x] shopping-cart-order actuator NPE fix — branch `fix/order-actuator-security-npe`, commit `6b8888c`; compile check timed out in this environment.
- [x] Data Layer GitOps consolidation — spec: `docs/plans/v1.4.10-data-layer-gitops-consolidation.md` (shopping-cart-infra PR #70: `7840441`)
- [x] Keycloak role-based MFA — spec: `docs/plans/v1.4.11-keycloak-mfa.md` (shopping-cart-infra PR #71: `0f13c0b`)
- [x] Keycloak reconcile sub-flow endpoint fix — spec: `docs/plans/v1.4.11-bugfix-reconcile-subflow-update-endpoint.md` (shopping-cart-infra PR #72 merged: `4c7c6ec`)
- [ ] data-layer StatefulSet not-found race on fresh cluster — spec: `docs/bugs/v1.4.11-bugfix-data-layer-statefulset-not-found.md`; fix applied in `shopping_cart.sh` on `k3d-manager-v1.4.11`
- [x] ArgoCD RBAC fix: `product-catalog` → `shopping-cart-product-catalog` in `argocd-rbac-cm` (shopping-cart-infra: `8768955`)
- [x] order-service fix — PR #32 merged (`3e78feab`) — actuator NPE + Lombok processor + pre-push hook
- [ ] pre-push main-guard hook — k3d-manager (`2c0589ac`) + shopping-cart-order (`bd2a169`) done; Codex: 6 remaining shopping-cart repos on `chore/add-pre-push-hook`
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
