# Changelog

## [Unreleased]

## [1.4.11] - 2026-05-29

### Fixed
- `scripts/plugins/shopping_cart.sh`: annotate all ExternalSecrets before waiting to prevent ESO controller saturation on fresh clusters
- `scripts/plugins/shopping_cart.sh`: poll for StatefulSet existence before `kubectl rollout status` to fix data-layer race on fresh clusters
- `scripts/plugins/shopping_cart.sh`: add explicit `|| return 1` on `kubectl wait` and `|| _warn` on `kubectl annotate` — silent continuation on timeout was a reliability bug
- `bin/acg-down`: replace `--interactive-sudo` with `--prefer-sudo` on all LaunchDaemon teardown calls — eliminates `Password:` prompt and PTY allocation error on macOS Tahoe
- `bin/acg-up`: add Keycloak group-ldap-mapper reconciliation step — LDAP group sync now persists across reprovisioning
- ArgoCD RBAC: correct `catalog-admin` policy to reference `shopping-cart/shopping-cart-product-catalog` (was `shopping-cart/product-catalog`)
- `bin/acg-down`: move sudo pre-warm to top of script — prompt before any output to improve UX
- `services/shopping-cart-payment/kustomization.yaml`: remove redundant `payment-db-credentials-eso` ExternalSecret — `postgres-payment-app` (shopping-cart-infra) already owns the secret with all required keys; k3d-manager ESO caused `SecretSyncedError` due to ownership conflict
- `bin/acg-up`: replace broken 40-retry credential wait loop with delegation to `acg-credential-test`, which has proper ghost-state detection and STS validation with restart capability
- `scripts/lib/acg/bin/acg-credential-test`: fix stderr swallowing — Playwright INFO/WARN/ERROR messages now reach terminal instead of being silently redirected to tmpfile
- `scripts/lib/acg/playwright/acg_credentials.js`: add `page.evaluate` fallback in `_waitForCredentials` when React-managed inputs return empty from `inputValue()` after CDP reconnect
- `scripts/lib/acg/scripts/etc/acg-cluster.yaml`: restore CloudFormation template removed from lib-acg in v0.2.0 without updating the `_LIB_ACG_ROOT/scripts/etc/acg-cluster.yaml` reference — broke `make up` with `Invalid template path`
- `scripts/etc/agent/hardcoded-ip-allowlist`: add subtree copy of `acg-cluster.yaml` to bypass IP literal check for CloudFormation CIDR blocks
- ArgoCD OIDC issuer: update to `keycloak.3ai-talk.org` in Helm values template
- `scripts/etc/argocd/applicationsets/services-git.yaml`: assign shopping-cart apps to `shopping-cart` ArgoCD project — ApplicationSet reconciliation was reverting manual project patches immediately
- `bin/acg-down`: remove stale `/tmp/argocd-*.sock`, `/tmp/k3d-config-tmp-*.yaml`, `/tmp/k3d-hostsfile-*` on teardown
- `scripts/plugins/shopping_cart.sh`: add `--wait=false` to seed job delete — ArgoCD hook finalizer blocked `kubectl delete` indefinitely on fresh clusters
- `bin/acg-up`: resilient DB password reconciliation — re-aligns Vault KV and PostgreSQL auth on every run; removes one-shot legacy overrides
- `bin/acg-up`: reconcile order-service postgres password after sandbox seed
- `bin/acg-up`: sync vault-backed data-layer ExternalSecrets and MinIO on every run
- `scripts/etc/argocd/applicationsets/services-git.yaml`: add `ignoreDifferences` for `order-service-secrets` and `product-catalog-seed-script` labels — prevents infinite sync loop from ArgoCD owner label injection

### Changed
- Pull lib-acg v0.3.0 subtree with `ACG_CLUSTER_TEMPLATE` env var support for CloudFormation template path
- `services/shopping-cart-*/kustomization.yaml`: move imagePullSecrets from per-app patches to `default` ServiceAccount in `shopping-cart-apps`
- `bin/acg-up`: extract shopping-cart bootstrap logic into `scripts/plugins/shopping_cart.sh`

### Added
- `bin/acg-up`: check sandbox TTL before provisioning and extend if below threshold
- `bin/acg-up`: patch CoreDNS NodeHosts instead of injecting a duplicate hosts block into CoreDNS Corefile
- `bin/acg-up`: generate cloudflared config from template and add keycloak to the Cloudflare tunnel
- `docs/bugs/` entries for OIDC issuer mismatch in product-catalog and payment services

## [1.4.8] - 2026-05-19

### Fixed
- `scripts/plugins/vault.sh`: register cleanup traps immediately after mktemp to prevent temp file leaks on error paths
- `scripts/lib/acg/playwright/acg_extend.js`: disconnect CDP browser connection on exit to prevent WebSocket hang and node process leak
- `bin/acg-up`: set Keycloak frontendUrl to Cloudflare public domain after realm import (fixes redirect loops from non-public domain)
- `bin/acg-up`: replace trycloudflare quick tunnels with named Cloudflare tunnel for stable public URLs across cluster restarts
- `bin/acg-up`: correct realm JSON path from identity/config to identity/keycloak in import payload
- `bin/acg-refresh`: restart Cloudflare tunnel on refresh to clear stale tunnel routes

### Changed
- `bin/acg-refresh`: drop unused SCRIPT_DIR variable

### Added
- `bin/get-keycloak-password`: new script to query Keycloak SSO user passwords from Vault

## [1.4.5] - 2026-05-10

### Added
- ACG AWS sandbox provisioning (`acg_provision`, `acg_extend`, `acg_teardown`)
- LoadBalancer ingress for ArgoCD, Keycloak, Jenkins
- Plugin architecture with lazy loading

### Fixed
- Vault PKI bootstrap on cluster up

## [1.4.0] - 2026-05-01

### Added
- Initial release
