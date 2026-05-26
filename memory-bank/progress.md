# Progress — k3d-manager

## Status (v1.4.10 — active)
- **COMPLETE — shopping-cart-frontend PR #23 POST-MERGE:** `fix/cart-response-unwrap` → `main` merged (SHA `0ca35f0` / 2026-05-25); enforce_admins restored ✓; `docs/next-improvements` branch already existed on shopping-cart-frontend, checked out locally ✓; no version bump (Unreleased CHANGELOG only); retrospective (`2026-05-25-fix-cart-response-unwrap-retrospective.md`) created + committed (`4ebecfc`) + pushed to origin ✓; k3d-manager memory-bank updated ✓
- **COMPLETE — shopping-cart-frontend PR #22 POST-MERGE:** `fix/product-detail-field-mapping` → `main` merged (SHA `bef902a1` / 2026-05-25); enforce_admins restored ✓; `docs/next-improvements` branch already existed, checked out locally ✓; no version bump (Unreleased CHANGELOG); retrospective (`2026-05-25-pr22-product-detail-fix-retrospective.md`) committed (`1581e93`) + pushed to origin ✓
- **COMPLETE — shopping-cart-payment PR #21 POST-MERGE:** `fix/payment-remove-placeholder-secret` → `main` merged (SHA `9f9701bb` / 2026-05-25); enforce_admins restored ✓; `docs/next-improvements` branch already existed, checked out locally ✓; no version bump (Unreleased CHANGELOG); retrospective (`2026-05-25-pr21-placeholder-secret-removal-retrospective.md`) committed (`a36179e`) + pushed to origin ✓
- **COMPLETE:** `shopping-cart-payment` branch `fix/payment-remove-placeholder-secret` now removes `k8s/base/secret.yaml` from `k8s/base/kustomization.yaml` and deletes the placeholder secret manifest so ESO owns `payment-db-credentials` and `payment-encryption-secret`; committed as `f3f3817` and pushed to `origin/fix/payment-remove-placeholder-secret`.
- **COMPLETE:** `shopping-cart-frontend` branch `fix/product-detail-field-mapping` now maps `quantity`→`stock` and `image_url`→`imageUrl` in `src/services/productService.ts:getProductById`, and adds the `/minio/` nginx proxy in `nginx.conf`; committed as `66b9007` and pushed to `origin/fix/product-detail-field-mapping`.
- **MERGED PR #80:** v1.4.9 release merged to main (`a294dfc2`); enforce_admins restored ✓; retrospective committed (`b285331a`) to k3d-manager-v1.4.10 ✓; next branch k3d-manager-v1.4.10 created ✓; memory-bank updated ✓

## Pending — Next Release Cycle
- **PENDING:** Node.js 20 → 22 upgrade across all shopping-cart CI workflows — GitHub Actions deprecated Node.js 20 runner; `node-version: '20'` must be bumped to `'22'` in all jobs in all shopping-cart repos (`frontend`, `basket`, `order`, `payment`, `product-catalog`); issue doc at `shopping-cart-frontend/docs/issues/2026-05-22-nodejs20-deprecation.md` (commit `e6cde03` on `docs/next-improvements`); also consider adding `NODE_VERSION` to workflow-level `env:` block and referencing everywhere.

## Open Follow-ups (carried forward from v1.4.4–v1.4.9)
- [ ] **`scripts/plugins/argocd.sh:_argocd_write_port_forward_wrapper` Agent Audit mismatch** — temporarily allowlisted; audit counter reports 11 `if` blocks but rendered function body only has one. Spec: `docs/issues/2026-05-11-argocd-port-forward-wrapper-if-count-mismatch.md`.
- [ ] **`deploy_keycloak` if-count refactor** — temporary allowlist entry added for `scripts/plugins/keycloak.sh:deploy_keycloak`; separate refactor needed. Spec: `docs/issues/2026-05-11-keycloak-deploy_keycloak-if-count.md`.
- [ ] **Argo CD rejects localhost return URLs during SSO login** — `/auth/login` rejects `return_url=http://localhost:8080/...` even though Keycloak client redirect URIs are present. Spec: `docs/issues/2026-05-11-argocd-localhost-return-url-rejected.md`.
- [ ] **Planned — `make up TRUST_CA=1` host CA trust bootstrap** — spec `docs/plans/v1.4.5-trust-ca-auto-import.md`.
- [ ] **Argo CD Safari stale localhost session follow-up** — issue doc: `docs/issues/2026-05-12-argocd-safari-stale-localhost-tab-keeps-reopening.md`.
- [ ] **Argo CD port-forward wrapper scalar context follow-up** — optional array under `set -u`; scalar fix needed. Issue doc: `docs/issues/2026-05-12-argocd-port-forward-wrapper-empty-array-unbound.md`.
- [ ] **Keycloak browser launchd plist path fix** — plist was staged under `~/Library/LaunchDaemons` (does not exist); needs move to `/Library/LaunchDaemons`. Issue doc: `docs/issues/2026-05-12-keycloak-browser-launchd-plist-installed-under-home-dir.md`.
- [ ] **Live LDAP bind credentials mismatch** — `bin/ldap-search` against live `openldap-admin` secret returns `ldap_bind: Invalid credentials (49)`. Issue doc: `docs/issues/2026-05-12-live-ldap-bind-secret-invalid-credentials.md`.
- [ ] **LDAP username attribute re-aligned to `uid`** — fix/keycloak-ldap-username-attribute-uid sets `LDAP_USERNAME_ATTRIBUTE` and `usernameLDAPAttribute` to `uid`. Issue doc: `docs/issues/2026-05-13-keycloak-ldap-username-attribute-uid.md`.
- [ ] **New finding — Keycloak LDAP null username with mail mapping** — live log shows `User returned from LDAP has null username!` when `usernameLDAPAttribute=mail`. Issue doc: `docs/issues/2026-05-12-keycloak-ldap-null-username-mail-mapping.md`.
- [ ] **Agent Audit if-count budget in `scripts/lib/test.sh`** — `test_jenkins` and `test_cert_rotation` still exceed threshold; temporary allowlist entries added. Issue doc: `docs/issues/2026-05-12-scripts-lib-test-if-count-allowlist.md`.
- [ ] **acg-up known_hosts sync** — managed AWS host IPs in `~/.ssh/config` tracked so stale entries can be pruned from `~/.ssh/known_hosts`. Issue doc: `docs/issues/2026-05-13-acg-up-maintain-known-hosts-for-managed-aws-ips.md`.
- [ ] **Refactor shopping_cart.sh → k3s_remote.sh** — spec: `docs/plans/v1.4.3-refactor-k3s-remote-plugin.md`; assign to Codex after SSO wiring verified.
- [ ] **Service mesh + LB for k3s-aws and k3s-gcp** — spec: `docs/plans/v1.4.3-service-mesh-lb-k3s-remote.md`; assign to Codex AFTER refactor is done.
- [ ] **chisel HTTPS tunnel** — spec: `docs/plans/v1.4.3-chisel-tunnel.md`; replaces autossh+socat with HTTPS WebSocket; `TUNNEL_PROVIDER=chisel` gate; depends on refactor spec.
- [ ] Restore `deploy_argocd_bootstrap "$@"` passthrough — lib-foundation flag-filtering approach; fix callers that depended on it (esp. `provision-tomcat`).
- [ ] lib-foundation upstream: remove `K3DM_ENABLE_AI=1` from `_copilot_review` usage snippet in `docs/api/functions.md`.

## Archived
Entries for v1.4.2–v1.4.8 archived to `memory-bank/archive/progress-v1.4.2-v1.4.8.md`
