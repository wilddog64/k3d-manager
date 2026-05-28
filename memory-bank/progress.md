# Progress — k3d-manager

## Status
- **v1.4.10 IN PROGRESS** (2026-05-27) — Finalizing OIDC and ArgoCD stability.
- **v1.4.9 SHIPPED** — Credential extraction and OIDC issuer fixes.

## Milestone: v1.4.10 (ArgoCD Stability)
- [x] OIDC Issuer protocol mismatch resolution.
- [x] Keycloak configuration conflict fix.
- [x] ArgoCD infinite sync loop fix for \`order-service-secrets\`.
- [x] ArgoCD sync drift fix for \`product-catalog-seed-script\`.
- [x] Product seed race condition fix.
- [x] Resilient DB password reconciliation.
- [ ] Data Layer GitOps consolidation (Spec drafted).
- [ ] lib-acg Provider-Plugin architecture (Spec drafted in \`lib-acg/docs/plans/v1.2.0-provider-plugin-architecture.md\`).

## Milestone: v0.4.0 (Observability) — PLANNED
- [ ] Prometheus ServiceMonitors for core services.
- [ ] Grafana Dashboards integration.
- [ ] Cross-cluster ESO validation.
