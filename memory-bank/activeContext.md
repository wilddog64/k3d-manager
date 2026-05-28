# Active Context — k3d-manager

## Current Status
- Current branch: \`k3d-manager-v1.4.11\` (created from merge SHA \`f8bad52d\`).
- **v1.4.11 IN PROGRESS** — Data Layer GitOps consolidation and ArgoCD RBAC fix.
- **v1.4.10 SHIPPED** — PR #81 merged (\`f8bad52d\`). ArgoCD stability, bootstrap reliability, /tmp cleanup.
- **enforce_admins:** restored on k3d-manager main after v1.4.10 merge.

## Carry-Forward Items
- **Data Layer GitOps consolidation** — spec at \`docs/plans/v1.4.10-data-layer-gitops-consolidation.md\`; needs Codex implementation.
- **ArgoCD RBAC fix** — \`argocd-rbac-cm\` in shopping-cart-infra: \`product-catalog\` → \`shopping-cart-product-catalog\`. RCA at \`shopping-cart-product-catalog/docs/bugs/2026-05-28-argocd-permission-denied-catalog-admin.md\`.
- **lib-acg Provider-Plugin architecture** — spec at \`lib-acg/docs/plans/v1.2.0-provider-plugin-architecture.md\`.

## Recent Changes
- **PR #81 merged** — v1.4.10 ArgoCD stability + bootstrap reliability.
- **Copilot findings addressed** — PAT hygiene (netrc), SA imagePullSecrets all namespaces, set -e guard, Helm pin v3.17.3, API doc update.
- **Retro written** — \`docs/retro/2026-05-28-v1.4.10-retrospective.md\`.

## Next Steps
- Codex: implement Data Layer GitOps consolidation (spec ready).
- Gemini: apply ArgoCD RBAC fix in shopping-cart-infra.
- Add public domain to Keycloak realm config.
- Proceed with Node.js 20→22 upgrade (all 5 shopping-cart repos).
