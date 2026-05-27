# Active Context — k3d-manager

## Current Status
- Current branch: \`k3d-manager-v1.4.10\` (created from merge SHA \`92ccaec1\`).
- **v1.4.10 IN PROGRESS** — Resolving ArgoCD sync drift for identity and app secrets.
- **SSO FIX COMPLETE:** Aligned OIDC protocols by enforcing \`KC_HOSTNAME_STRICT: true\` and \`KC_HOSTNAME_URL\`.
- **ARGOCD DRIFT FIX COMPLETE:** \`scripts/etc/argocd/applicationsets/services-git.yaml\` now ignores expected drift for \`Secret/order-service-secrets\` and \`ConfigMap/product-catalog-seed-script\` (including labels and ownerReferences), resolving the infinite reconciliation loop with ESO.
- **DB AUTH ALIGNMENT COMPLETE:** PostgreSQL internal passwords aligned with Vault-synced secrets.

## Recent Changes
- **fix(argocd):** expand ignoreDifferences for order and product-catalog to include labels (commit \`0cb8a464\`).
- **fix(keycloak):** resolve OIDC issuer mismatch (PR #45 merged).
- **fix(keycloak):** resolve hostname vs hostname-url conflict (PR #46 merged).

## Next Steps
- Monitor ArgoCD sync stability for \`shopping-cart-order\`.
- Proceed with v0.4.0 milestone (Observability).
