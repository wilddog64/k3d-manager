# Progress — k3d-manager

## Status
- **v1.4.11 PARTIALLY COMPLETE** (2026-05-28) — Data Layer GitOps consolidation and Keycloak MFA complete; ArgoCD RBAC fix still pending.
- **v1.4.10 SHIPPED** — PR #81 merged (`f8bad52d`). ArgoCD stability, bootstrap reliability, /tmp cleanup.
- **v1.4.9 SHIPPED** — Credential extraction and OIDC issuer fixes.

## Milestone: v1.4.11 (Data Layer GitOps + RBAC)
- [x] Data Layer GitOps consolidation — spec: `docs/plans/v1.4.10-data-layer-gitops-consolidation.md` (shopping-cart-infra PR #70: `7840441`)
- [x] Keycloak role-based MFA — spec: `docs/plans/v1.4.11-keycloak-mfa.md` (shopping-cart-infra PR #71: `0f13c0b`)
- [ ] ArgoCD RBAC fix: `product-catalog` → `shopping-cart-product-catalog` in `argocd-rbac-cm`
- [ ] Node.js 20→22 upgrade (all 5 shopping-cart CI workflows)

## Milestone: v1.4.10 (ArgoCD Stability) — SHIPPED
- [x] OIDC Issuer protocol mismatch resolution.
- [x] Keycloak configuration conflict fix.
- [x] ArgoCD infinite sync loop fix for \`order-service-secrets\`.
- [x] ArgoCD sync drift fix for \`product-catalog-seed-script\`.
- [x] Product seed race condition fix.
- [x] Resilient DB password reconciliation.
- [x] ArgoCD permission denied mismatch investigation (RCA in \`shopping-cart-product-catalog/docs/bugs/\`).
- [x] seed job \`--wait=false\` fix (\`c27611a5\`).
- [x] PR #81 merged (\`f8bad52d\`). All Copilot findings addressed.

## Milestone: v0.4.0 (Observability) — PLANNED
- [ ] Prometheus ServiceMonitors for core services.
- [ ] Grafana Dashboards integration.
- [ ] Cross-cluster ESO validation.
