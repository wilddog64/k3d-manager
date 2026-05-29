# Active Context — k3d-manager

## Current Status
- Current branch: \`k3d-manager-v1.4.11\` (created from merge SHA \`f8bad52d\`).
- **v1.4.11 DATA LAYER COMPLETE** — shopping-cart-infra PR #70 merged (\`7840441\`). ArgoCD \`prune: false\` for data layer.
- **v1.4.11 KEYCLOAK MFA COMPLETE** — shopping-cart-infra PR #71 merged (\`0f13c0b\`). Role-based TOTP for platform-admin/platform-developer.
- **v1.4.11 REMAINS OPEN** — ArgoCD RBAC fix still pending.
- **v1.4.10 SHIPPED** — PR #81 merged (\`f8bad52d\`). ArgoCD stability, bootstrap reliability, /tmp cleanup.
- **enforce_admins:** restored on k3d-manager main after v1.4.10 merge; restored on shopping-cart-infra main after v1.4.11 partial merge.
- **shopping-cart-infra docs/next-improvements:** created and synced; retrospective added (\`295a83a\`).

## Carry-Forward Items
- **Data Layer GitOps consolidation** — complete; commit SHAs: k3d-manager \`18be9e09\`, shopping-cart-infra \`0e7e2a6\`.
- **Keycloak role-based MFA** — complete; commit SHA: shopping-cart-infra \`d8603dd\`.
- **ArgoCD RBAC fix** — \`argocd-rbac-cm\` in shopping-cart-infra: \`product-catalog\` → \`shopping-cart-product-catalog\`. RCA at \`shopping-cart-product-catalog/docs/bugs/2026-05-28-argocd-permission-denied-catalog-admin.md\`.
- **lib-acg Provider-Plugin architecture** — spec at \`lib-acg/docs/plans/v1.2.0-provider-plugin-architecture.md\`.

## Recent Changes
- **Keycloak role-based MFA completed** — added `platform-mfa`, made `platform-admin` and `platform-developer` composite, and installed the conditional OTP browser flow in `keycloak-reconcile-hook-job.yaml`.
- **Push complete** — shopping-cart-infra \`d8603dd\` on \`feat/v1.4.11-keycloak-mfa\`.
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
