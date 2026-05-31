# Changelog

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
