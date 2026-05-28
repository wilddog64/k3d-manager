# Progress — k3d-manager

## Status
- **v1.4.10 IN PROGRESS** (2026-05-28) — Finalizing OIDC and ArgoCD stability.
- **v1.4.9 SHIPPED** — Credential extraction and OIDC issuer fixes.

## Milestone: v1.4.10 (ArgoCD Stability)
- [x] OIDC Issuer protocol mismatch resolution.
- [x] Keycloak configuration conflict fix.
- [x] ArgoCD infinite sync loop fix for \`order-service-secrets\`.
- [x] ArgoCD sync drift fix for \`product-catalog-seed-script\`.
- [x] Product seed race condition fix.
- [x] Resilient DB password reconciliation.
- [x] ArgoCD permission denied mismatch investigation (see RCA in \`shopping-cart-product-catalog/docs/bugs/2026-05-28-argocd-permission-denied-catalog-admin.md\`).
- [ ] Data Layer GitOps consolidation (Spec drafted).
- [ ] lib-acg Provider-Plugin architecture (Spec drafted).

## Milestone: v0.4.0 (Observability) — PLANNED
- [ ] Prometheus ServiceMonitors for core services.
- [ ] Grafana Dashboards integration.
- [ ] Cross-cluster ESO validation.
