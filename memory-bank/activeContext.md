# Active Context — k3d-manager

## Current Status
- Current branch: \`k3d-manager-v1.4.10\` (created from merge SHA \`92ccaec1\`).
- **v1.4.10 IN PROGRESS** — Resolving ArgoCD sync drift and bootstrap race conditions.
- **SSO FIX COMPLETE:** Aligned OIDC protocols by enforcing \`KC_HOSTNAME_STRICT: true\` and \`KC_HOSTNAME_URL\`.
- **ARGOCD DRIFT FIX COMPLETE:** \`scripts/etc/argocd/applicationsets/services-git.yaml\` now ignores expected drift for \`Secret/order-service-secrets\` and \`ConfigMap/product-catalog-seed-script\`.
- **PRODUCT SEED RACE CONDITION:** Fixed in \`shopping-cart-product-catalog\` PR #32; pointer in \`docs/bugs/2026-05-27-product-catalog-seed-race-condition.md\`.
- **DB AUTH RECONCILIATION COMPLETE:** Implemented resilient SQL reconciliation in \`bin/acg-up\` and cleaned up legacy \`CHANGE_ME\` overrides in \`scripts/plugins/shopping_cart.sh\`. Spec: \`docs/plans/v1.4.10-resilient-db-password-reconciliation.md\`.

## Recent Changes
- **fix(acg-up):** moved DB password reconciliation to end of bootstrap and removed legacy overrides.
- **fix(argocd):** expand ignoreDifferences for order and product-catalog to include labels.
- **bug(seed):** fixed product seed race condition via initContainer in app repo.

## Next Steps
- Verify DB reconciliation during the next full \`make up\`.
- Proceed with v0.4.0 milestone (Observability).
