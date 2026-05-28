# Active Context — k3d-manager

## Current Status
- Current branch: \`k3d-manager-v1.4.10\` (created from merge SHA \`92ccaec1\`).
- **v1.4.10 IN PROGRESS** — Resolving ArgoCD sync drift and bootstrap race conditions.
- **SSO FIX COMPLETE:** Aligned OIDC protocols by enforcing \`KC_HOSTNAME_STRICT: true\` and \`KC_HOSTNAME_URL\`.
- **ARGOCD DRIFT FIX COMPLETE:** \`scripts/etc/argocd/applicationsets/services-git.yaml\` now ignores expected drift for \`Secret/order-service-secrets\` and \`ConfigMap/product-catalog-seed-script\`.
- **PRODUCT SEED RACE CONDITION:** Fixed in \`shopping-cart-product-catalog\` PR #32.
- **DB AUTH RECONCILIATION COMPLETE:** Implemented resilient SQL reconciliation in \`bin/acg-up\`. Spec: \`docs/plans/v1.4.10-resilient-db-password-reconciliation.md\`.
- **DATA LAYER GITOPS REFACTOR:** Identified visibility gap for MinIO/Databases in ArgoCD. Spec: \`docs/plans/v1.4.10-data-layer-gitops-consolidation.md\`.
- **LIB-ACG PROVIDER REFACTOR:** Drafting architecture to support AWS, GCP, and Azure independently using a Dispatcher-Plugin pattern. Spec in \`lib-acg\` at \`docs/plans/v1.2.0-provider-plugin-architecture.md\`.

## Recent Changes
- **docs(plans):** added spec for lib-acg Provider-Plugin architecture (in \`lib-acg\` repo).
- **docs(plans):** added spec for Data Layer GitOps consolidation.
- **docs(cleanup):** relocated RCAs from k3d-manager to target repositories.

## Next Steps
- Implement Data Layer GitOps consolidation.
- Execute lib-acg Phase 1 (AWS logic isolation).
- Proceed with v0.4.0 milestone (Observability).
