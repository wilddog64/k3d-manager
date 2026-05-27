# Active Context — k3d-manager

## Current Status
- Current branch: \`k3d-manager-v1.4.10\` (created from merge SHA \`92ccaec1\`).
- **v1.4.10 IN PROGRESS** — Resolving ArgoCD sync drift and bootstrap race conditions.
- **SSO FIX COMPLETE:** Aligned OIDC protocols by enforcing \`KC_HOSTNAME_STRICT: true\` and \`KC_HOSTNAME_URL\`.
- **ARGOCD DRIFT FIX COMPLETE:** \`scripts/etc/argocd/applicationsets/services-git.yaml\` now ignores expected drift for \`Secret/order-service-secrets\` and \`ConfigMap/product-catalog-seed-script\`.
- **PRODUCT SEED RACE CONDITION:** Identified and fixed a race condition where the seed job failed before tables were created. The RCA is documented in \`docs/bugs/2026-05-27-product-catalog-seed-race-condition.md\`. Fix applied in \`shopping-cart-product-catalog\` PR #32.

## Recent Changes
- **fix(argocd):** expand ignoreDifferences for order and product-catalog to include labels (commit \`0cb8a464\`).
- **bug(seed):** documented product seed race condition and opened PR #32 in app repo.
- **fix(keycloak):** resolve OIDC issuer mismatch (PR #45 merged).

## Next Steps
- Merge \`shopping-cart-product-catalog\` PR #32 to finalize the seed job fix.
- Proceed with v0.4.0 milestone (Observability).
