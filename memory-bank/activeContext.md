# Active Context — k3d-manager

## Current Status
- Current branch: \`k3d-manager-v1.4.10\` (created from merge SHA \`92ccaec1\`).
- **v1.4.10 IN PROGRESS** — Resolving ArgoCD sync drift and bootstrap race conditions.
- **SSO FIX COMPLETE:** Aligned OIDC protocols by enforcing \`KC_HOSTNAME_STRICT: true\` and \`KC_HOSTNAME_URL\`.
- **ARGOCD DRIFT FIX COMPLETE:** \`scripts/etc/argocd/applicationsets/services-git.yaml\` now ignores expected drift for \`Secret/order-service-secrets\` and \`ConfigMap/product-catalog-seed-script\`.
- **PRODUCT SEED RACE CONDITION:** Fixed in \`shopping-cart-product-catalog\` PR #32; pointer in \`docs/bugs/2026-05-27-product-catalog-seed-race-condition.md\`.
- **DB AUTH RECONCILIATION COMPLETE:** Implemented resilient SQL reconciliation in \`bin/acg-up\`. Spec: \`docs/plans/v1.4.10-resilient-db-password-reconciliation.md\`.
- **FRONTEND CHECKOUT BUG:** Identified a contractual mismatch preventing checkout (missing \`shippingAddress\`). RCA documented in \`docs/bugs/2026-05-27-frontend-checkout-contract-mismatch.md\`.
- **FRONTEND OIDC PUBLIC DOMAIN BUG:** Identified a domain whitelist mismatch preventing login via Cloudflare DNS. RCA documented in \`shopping-cart-frontend\` at \`docs/issues/2026-05-27-frontend-oidc-public-domain-mismatch.md\`.

## Recent Changes
- **docs(bugs):** added RCA for frontend OIDC public domain mismatch.
- **docs(bugs):** added RCA for frontend checkout contract mismatch.
- **fix(acg-up):** implemented resilient DB password reconciliation.
- **bug(seed):** fixed product seed race condition via initContainer in app repo.

## Next Steps
- Add public domain to Keycloak realm config to resolve frontend login mismatch.
- Implement frontend checkout form to resolve the contract mismatch.
- Proceed with v0.4.0 milestone (Observability).
