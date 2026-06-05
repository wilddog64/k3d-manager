# Changelog

## [Unreleased]

## [1.6.0] - 2026-06-04

### Added
- Webhook Slack threading — all job notifications grouped into a single thread with thread-aware replies
- Slack thread commands — `/kill`, `/diagnosis`, `/status`, `/logs` commands reply directly in job thread
- ArgoCD CVE scan CronJob (bi-weekly, Hub cluster) — direct kubectl invocation, no webhook dependency
- ArgoCD upgrade pipeline notifications via SendGrid + PagerDuty integration
- Cloudflare Worker deploy workflow — `bin/k3dm-worker-setup` and `make deploy-worker` for slash command relay deployment
- AI-powered failure analysis on webhook job failures — Gemini triage + visual diagnosis (Claude vision on Playwright screenshots)
- Post-provision health check — Claude Haiku AI triage of degraded apps after `acg-up`
- Webhook token auto-rotation every 6 hours via LaunchAgent — `bin/rotate-webhook-token` keeps token in sync with Cloudflare Worker
- Stall detection for long-running ACG jobs — AI analysis + automatic kill action with Slack notification
- Python 3.13 interpreter in webhook plist template — fixes SIGSEGV on macOS 26.5.1 Beta

### Fixed
- Slack slash command Request URLs now point to `https://k3dm-slack-relay.k3dm.workers.dev` (Cloudflare Worker relay with auth) instead of direct tunnel endpoint — fixes 401 errors and prevents auth bypass
- Webhook restart-orphan handling — notify Slack when a restart kills a running job
- Webhook e2e token verification on rotation — verify new token before committing to Keychain
- Webhook SSH tunnel check before remote kubectl in failure analysis — prevents hung diagnosis waits
- Webhook TimeoutExpired exception handling — catch separately to prevent prompt leak in Slack message
- k3s-aws idempotency — skip `deploy_app_cluster` when nodes already Ready
- Keycloak group-ldap-mapper reconciliation — LDAP group sync persists across reprovisioning
- Install sudoers script — use `--interactive-sudo` + `NOPASSWD` rules for safe self-update

### Changed
- Webhook output — visual diagnosis via Gemini CLI with Playwright failure screenshots
- Webhook failure analysis — enrich with live pod and ArgoCD app state + node state distinction (cluster vs app failure)

## [1.5.3] - 2026-06-01

### Added
- ACG Alertmanager: NodePort 30093, Vault-backed SMTP secret integration, email alert routing

### Changed
- Observability: prune ~40 noisy kube-prometheus-stack default alert rules not applicable to k3s (apiserver SLO burn-rates, alertmanager HA, config-reloaders); enable Grafana on ACG cluster (NodePort 30030)
- README: add Trivy Operator to architecture diagram
- Shopping Cart: increase MinIO rollout timeout 120s→300s for slow container registry pulls

### Fixed
- ACG credentials: click "Extend Session" button (not Cancel) on session-extension dialog, preserving the once-per-session session-extension opportunity

## [1.5.1] - 2026-05-31

### Added
- OCI object storage backup/restore: `oci_backup` and `oci_restore` commands for k3s-oci provider — auto-backup after deploy, Makefile `backup` and `restore` targets
- ACG credential automation: auto-launch Chrome CDP, handle session-expired redirects; open sign-in page for manual completion when CAPTCHA is required

### Fixed
- Fix Python one-liner quoting in `cloudflared-backup` and `alertmanager-secret` Makefile targets — replace double-quoted `-c` arg and positional `sys.argv` with single-quoted `-c` and env-var injection to prevent shell brace expansion
- BATS observability tests: fix `>>` stub in `test_deploy_observability` (append to log instead of overwrite)
- `bin/acg-up`: make System Keychain cert trust non-fatal (warn on permission error instead of aborting)
- ACG credential automation: handle session-expired login redirects, navigate to signin page on 404/off-site redirect
- ACG credential automation: click sign-in button and navigate to sign-in form; user completes CAPTCHA manually when required
- `k3s-oci-storage`: replace hex-encoded sudo with named `_OCI_SSH_SUDO` variable for clarity

### Changed
- `Makefile`: add `trivy-scan-report` alias for `vuln-scan` target

## [1.5.0] - 2026-05-31

### Added
- `CLUSTER_PROVIDER=k3s-oci`: new OCI Always Free provider — single-node ARM64 k3s cluster on Oracle Cloud (2OCPU/12GB); Cilium CNI; Cloudflare Tunnel ingress
- `CLUSTER_PROVIDER=k3s-oci` two-node cluster: server + agent (4OCPU/24GB total); automated agent wait loop in BATS coverage
- `scripts/plugins/observability.sh`: deploy Prometheus+Grafana+Trivy to Hub k3d via ArgoCD ApplicationSet; Alertmanager with email-to-SMS via Vault-backed config
- `scripts/etc/prometheus/rules/shopping-cart-apps.yaml`: PrometheusRule CRDs (ServiceDown, PodCrashLooping, HighErrorRate)
- `scripts/etc/prometheus/alertmanager.yaml.tmpl`: envsubst-rendered Alertmanager config template
- `scripts/etc/observability/istio.yaml`: Istio Gateway + VirtualServices for prometheus.3ai-talk.org and grafana.3ai-talk.org
- `Makefile`: `observability`, `observability-acg`, `observability-status`, `vuln-scan`, `show-service-passwords`, `alertmanager-secret`, `cloudflared-backup` targets
- `bin/acg-up`: check sandbox TTL before provisioning and extend if below threshold
- `bin/acg-up`: patch CoreDNS NodeHosts instead of injecting a duplicate hosts block into CoreDNS Corefile
- `bin/acg-up`: generate cloudflared config from template and add keycloak to the Cloudflare tunnel
- `docs/bugs/` entries for OIDC issuer mismatch in product-catalog and payment services
- `bin/acg-up`: add prometheus/grafana URLs to public URL summary after `make up`
- `feat/cloudflared`: persist tunnel config to repo + restore credentials from Keychain on Hub rebuild; auto-sync credentials Keychain→Vault

### Changed
- Pull lib-acg v0.3.0 subtree with `ACG_CLUSTER_TEMPLATE` env var support for CloudFormation template path
- `scripts/etc/observability/`: rename observability DNS from `shopping-cart.local` to `3ai-talk.org`
- `scripts/plugins/observability.sh`: replace Alertmanager heredoc + hardcoded PrometheusRule with template files under `scripts/etc/prometheus/`

### Fixed
- `scripts/plugins/observability.sh`: subshell guard on `_kubectl get application` check — `_err()` calls `exit 1` not `return 1`; wrapping in `( )` prevents script abort on missing app
- `scripts/plugins/observability.sh`: silence Python traceback when Vault alertmanager secret not yet configured
- `scripts/plugins/observability.sh`: raise ACG Prometheus memory limit 256Mi→512Mi (OOMKilled)
- `scripts/plugins/observability.sh`: raise trivy scan job memory limit to 512Mi (OOMKilled)
- `Makefile`: add missing observability + credentials targets to `make help` output
- `bin/acg-up`: replace broken 40-retry credential wait loop with delegation to `acg-credential-test`, which has proper ghost-state detection and STS validation with restart capability
- `scripts/lib/acg/bin/acg-credential-test`: fix stderr swallowing — Playwright INFO/WARN/ERROR messages now reach terminal instead of being silently redirected to tmpfile
- `scripts/lib/acg/playwright/acg_credentials.js`: add `page.evaluate` fallback in `_waitForCredentials` when React-managed inputs return empty from `inputValue()` after CDP reconnect
- `scripts/lib/acg/scripts/etc/acg-cluster.yaml`: restore CloudFormation template removed from lib-acg in v0.2.0 without updating reference — broke `make up` with `Invalid template path`
- `scripts/etc/agent/hardcoded-ip-allowlist`: add subtree copy of `acg-cluster.yaml` to bypass IP literal check for CloudFormation CIDR blocks
- ArgoCD OIDC issuer: update to `keycloak.3ai-talk.org` in Helm values template
- `bin/acg-refresh`: non-fatal launchd bootstrap + kill orphans before bootstrap
- `bin/acg-refresh`: manage all port-forward services (PID + launchd)

## [1.4.12] - 2026-05-29

### Fixed
- `scripts/plugins/services.sh`: add imagePullSecrets patch to all named ServiceAccounts during cluster bootstrap — resolves ghcr.io 401 errors when non-default SAs pull images

### Added
- `Makefile`: `sync-branch` and `sync-main` targets for pre-merge ArgoCD branch verification
- `make status`: new ArgoCD ApplicationSets section (ArgoCD v3.4.2 removed UI sidebar — CLI is now the primary status view)

### Changed
- `services/shopping-cart-payment/kustomization.yaml`: remove redundant `payment-db-credentials-eso` ExternalSecret to fix SharedResourceWarning; sole ownership assigned to cicd/product-catalog app in shopping-cart-infra

## [1.4.11] - 2026-05-29

### Fixed
- `scripts/plugins/shopping_cart.sh`: annotate all ExternalSecrets before waiting to prevent ESO controller saturation on fresh clusters
- `scripts/plugins/shopping_cart.sh`: poll for StatefulSet existence before `kubectl rollout status` to fix data-layer race on fresh clusters
- `scripts/plugins/shopping_cart.sh`: add explicit `|| return 1` on `kubectl wait` and `|| _warn` on `kubectl annotate` — silent continuation on timeout was a reliability bug
- `bin/acg-down`: replace `--interactive-sudo` with `--prefer-sudo` on all LaunchDaemon teardown calls — eliminates `Password:` prompt and PTY allocation error on macOS Tahoe
- `bin/acg-up`: add Keycloak group-ldap-mapper reconciliation step — LDAP group sync now persists across reprovisioning
- ArgoCD RBAC: correct `catalog-admin` policy to reference `shopping-cart/shopping-cart-product-catalog` (was `shopping-cart/product-catalog`)
- `bin/acg-down`: move sudo pre-warm to top of script — prompt before any output to improve UX
- `services/shopping-cart-payment/kustomization.yaml`: remove redundant `payment-db-credentials-eso` ExternalSecret — `postgres-payment-app` (shopping-cart-infra) already owns the secret; k3d-manager ESO caused `SecretSyncedError` due to ownership conflict
- `bin/acg-up`: replace broken 40-retry credential wait loop with delegation to `acg-credential-test`
- `scripts/lib/acg/bin/acg-credential-test`: fix stderr swallowing — Playwright messages silently redirected to tmpfile
- `scripts/lib/acg/playwright/acg_credentials.js`: add `page.evaluate` fallback in `_waitForCredentials` after CDP reconnect
- `scripts/lib/acg/scripts/etc/acg-cluster.yaml`: restore CloudFormation template removed from lib-acg in v0.2.0 — broke `make up` with `Invalid template path`
- `scripts/etc/agent/hardcoded-ip-allowlist`: add subtree copy of `acg-cluster.yaml` to bypass IP literal check
- ArgoCD OIDC issuer: update to `keycloak.3ai-talk.org` in Helm values template
- `scripts/etc/argocd/applicationsets/services-git.yaml`: assign shopping-cart apps to `shopping-cart` ArgoCD project
- `bin/acg-down`: remove stale `/tmp/argocd-*.sock`, `/tmp/k3d-config-tmp-*.yaml`, `/tmp/k3d-hostsfile-*` on teardown
- `scripts/plugins/shopping_cart.sh`: add `--wait=false` to seed job delete — ArgoCD hook finalizer blocked `kubectl delete` indefinitely
- `bin/acg-up`: resilient DB password reconciliation — re-aligns Vault KV and PostgreSQL auth on every run
- `bin/acg-up`: reconcile order-service postgres password after sandbox seed
- `bin/acg-up`: sync vault-backed data-layer ExternalSecrets and MinIO on every run
- `scripts/etc/argocd/applicationsets/services-git.yaml`: add `ignoreDifferences` for `order-service-secrets` and `product-catalog-seed-script` labels

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
