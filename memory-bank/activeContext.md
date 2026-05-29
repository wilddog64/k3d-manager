# Active Context — k3d-manager

## Current Status
- Current branch: \`k3d-manager-v1.4.11\` (created from merge SHA \`f8bad52d\`).
- **v1.4.11 DATA LAYER COMPLETE** — Data Layer GitOps consolidation pushed in k3d-manager (\`18be9e09\`) and shopping-cart-infra (\`0e7e2a6\`).
- **v1.4.11 REMAINS OPEN** — ArgoCD RBAC fix still pending.
- **v1.4.10 SHIPPED** — PR #81 merged (\`f8bad52d\`). ArgoCD stability, bootstrap reliability, /tmp cleanup.
- **enforce_admins:** restored on k3d-manager main after v1.4.10 merge.

## Carry-Forward Items
- **Data Layer GitOps consolidation** — complete; commit SHAs: k3d-manager \`18be9e09\`, shopping-cart-infra \`0e7e2a6\`.
- **ArgoCD RBAC fix** — \`argocd-rbac-cm\` in shopping-cart-infra: \`product-catalog\` → \`shopping-cart-product-catalog\`. RCA at \`shopping-cart-product-catalog/docs/bugs/2026-05-28-argocd-permission-denied-catalog-admin.md\`.
- **lib-acg Provider-Plugin architecture** — spec at \`lib-acg/docs/plans/v1.2.0-provider-plugin-architecture.md\`.

## Recent Changes
- **Data Layer GitOps consolidation completed** — removed imperative data-layer `kubectl apply` from \`scripts/plugins/shopping_cart.sh\`; set \`prune: false\` in \`argocd/applications/data-layer.yaml\`.
- **Push complete** — k3d-manager \`18be9e09\` on \`k3d-manager-v1.4.11\`; shopping-cart-infra \`0e7e2a6\` on \`feat/v1.4.11-data-layer-gitops\`.
- **PR #81 merged** — v1.4.10 ArgoCD stability + bootstrap reliability.
- **Copilot findings addressed** — PAT hygiene (netrc), SA imagePullSecrets all namespaces, set -e guard, Helm pin v3.17.3, API doc update.
- **Retro written** — \`docs/retro/2026-05-28-v1.4.10-retrospective.md\`.

## Next Steps
- Codex: implement Data Layer GitOps consolidation (spec ready).
- Gemini: apply ArgoCD RBAC fix in shopping-cart-infra.
- Add public domain to Keycloak realm config.
- Proceed with Node.js 20→22 upgrade (all 5 shopping-cart repos).
