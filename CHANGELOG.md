# Changelog

## [Unreleased]

## [1.11.0] - 2026-06-28

### Added
- Tier 3 P3 canonical-source Vault seeding — `vault_seed_hub_into_context` operator plus idempotent seeding of `redis/*` and `rabbitmq/default` from a canonical source (re-runnable without drift), with retargeted inner seed helpers (`scripts/plugins/vault.sh`, `scripts/plugins/shopping_cart.sh`)
- Tier 3 P4 assisted-failover watchdog — `vault_failover_hub_into_context` (probe the hub Vault → on sustained failure flip `HUB_VAULT_PROFILE` and persist it → re-seed the in-cluster Vault → reconcile the app-cluster ClusterSecretStore), the `vault_install_failover_watchdog` installer, a `com.k3d-manager.vault-failover` LaunchAgent (StartInterval 300s) with its plist template, and the `bin/k3dm-vault-failover` wrapper (`scripts/plugins/vault.sh`, `scripts/etc/launchd/com.k3d-manager.vault-failover.plist.tmpl`, `bin/k3dm-vault-failover`)

### Fixed
- Failover watchdog hardening — the wrapper prepends the Homebrew prefixes (`/opt/homebrew/bin:/usr/local/bin`) to PATH so it finds `kubectl`/`helm`/`jq` under launchd's minimal PATH, and the re-seed call runs in a subshell so an unreachable laptop source degrades to warn-and-continue instead of aborting the failover before the CSS reconcile (`bin/k3dm-vault-failover`, `scripts/plugins/vault.sh`)
- Failover watchdog now sources `vars.sh` before reading the active profile, so the persisted `HUB_VAULT_PROFILE` from the state file is honored in the watchdog dispatch path while explicit env still wins (`scripts/plugins/vault.sh`)
- App-cluster Vault auth targets the in-cluster Vault context under the `hostinger` profile instead of the laptop hub (`scripts/plugins/vault.sh`)
- Audience bound on the app-cluster `eso-app-cluster` kubernetes-auth role so ESO token review succeeds (`scripts/plugins/vault.sh`)
- `deploy_eso` skips the Helm install when ESO is externally managed (ArgoCD-owned), preventing an install conflict during the in-cluster cutover (`scripts/plugins/eso.sh`)
- `k3s-hostinger` `refresh` now runs `launchctl enable` before `bootstrap` so it heals previously disabled launchd agents (`scripts/lib/providers/k3s-hostinger.sh`)

### Changed
- `.gitguardian.yaml` migrated to the v2 schema and the ggshield cache is now ignored (`.gitguardian.yaml`, `.gitignore`)

## [1.10.0] - 2026-06-27

### Added
- Provider-agnostic app-cluster Vault auth keyed on kube-context (`configure_vault_app_auth_for_context`) — the Kubernetes auth wiring is now portable across providers (EKS/AKS/ACG/Azure/OCI/Hostinger) instead of being pinned to Hostinger (`scripts/plugins/vault.sh`)
- `HUB_VAULT_PROFILE` endpoint seam (`laptop` | `hostinger`) selecting the hub-Vault `server:` URL written into the app-cluster ClusterSecretStore and whether the reverse-tunnel/socat bridge is stood up; default `laptop` keeps today's behavior byte-for-byte (Tier 3 P1, `scripts/etc/vault/vars.sh`)
- In-cluster auto-unseal watchdog CronJob for a relocated hub Vault — replays the Shamir shard from the in-cluster `vault-unseal` Secret on a `vault status` exit-code trigger; pinned image, namespace-scoped, no RBAC; self-contained and behavior-preserving (nothing auto-calls it) (Tier 3 P2a, `scripts/plugins/vault.sh`)
- `vault_deploy_hub_into_context` wrapper to provision the hub Vault inside an app cluster (current-context save/restore idiom; `HUB_VAULT_INCLUSTER=1` guard bypasses the `CLUSTER_ROLE=app` early-return), plus a least-privilege `app-cluster-reader` Vault policy (7 `secret/{data,metadata}/*` prefixes, no wildcard) and a kubernetes-auth ClusterSecretStore variant selected by `HUB_VAULT_CSS_AUTH` (`laptop`→token, `hostinger`→kubernetes); default profile stays `laptop` so the cutover is P3-gated (Tier 3 P2b, `scripts/plugins/vault.sh`, `scripts/plugins/shopping_cart.sh`)

### Fixed
- Hostinger `refresh` now ensures the `vault-port-forward` LaunchAgent is present so the laptop→Hostinger Vault bridge survives a refresh (`scripts/lib/providers/k3s-hostinger.sh`)
- ArgoCD `data-layer` ApplicationSet ignores controller-injected `volumeClaimTemplates[]` fields (`.status`, `.apiVersion`, `.kind`) so StatefulSets stop showing a permanent cosmetic `OutOfSync` (`scripts/etc/argocd/applicationsets/data-git.yaml`)

## [1.8.0] - 2026-06-26

### Added
- ESO operator install on app clusters via an ArgoCD ApplicationSet cluster generator (`scripts/etc/argocd/applicationsets/eso.yaml`) — selects `k3d-manager/role: app-cluster`, installs the `external-secrets` chart `1.0.0` with CRDs into the `secrets` namespace using server-side apply; portable across host OS and CPU arch (install runs in-cluster, not from the local CLI)

### Changed
- lib-foundation subtree synced to v0.4.0 — absorbed lib-acg, added `_ensure_agy_cli` and the extensible cluster-provider hook (`scripts/lib/foundation/`)
- ACG module now sourced from lib-foundation: the `acg.sh`, `gcp.sh`, and `gemini.sh` stubs repoint to `scripts/lib/foundation/scripts/lib/acg/` (Phase 2 of the lib-acg absorption); `bin/cluster-up` / `bin/cluster-refresh` npm-prefix and `acg-credential-test` paths follow
- `gemini.sh` browser automation retargeted from the retired `@google/gemini-cli` to the Go-based Antigravity CLI (`agy --dangerously-skip-permissions`); `_ensure_gemini` now provisions `agy` instead of npm-installing gemini-cli; public `gemini_*` function names retained (backend-only swap)

### Fixed
- shopping-cart data-layer routing: the app-cluster ArgoCD cluster secret now carries the `k3d-manager/role: app-cluster` label so the `data-git` ApplicationSet generator matches it (`scripts/lib/providers/k3s-hostinger.sh`, `scripts/etc/argocd/cluster-secret.yaml.tmpl`)
- Slack webhook: `cluster-up`/`cluster-down`/`cluster-resume` are now accepted as top-level standalone commands (were thread-reply-only); provider allowlist on all three now includes `hostinger` and defaults to `hostinger` instead of `aws`, so a bare or unrecognized provider no longer silently starts an ACG AWS sandbox run (`bin/k3dm-webhook`)
- `k3s-hostinger` reconcile now provisions `ghcr-pull-secret` on the Hostinger context (best-effort with a warning), so shopping-cart pods stop sitting in `ImagePullBackOff` after a deploy/refresh
- `k3s-hostinger` app-cluster registration uses CA-verified TLS and ensures the `argocd-manager` ServiceAccount exists before registering with the hub ArgoCD
- `k3s-hostinger` provider-aware `refresh` restored — re-bootstraps ESO, restarts the keycloak public port-forward, restores the repo-managed cloudflared tunnel, and is now bash 3.2-safe with rebuilt browser wrappers
- `k3s-hostinger` ArgoCD access layer hardened on refresh — kills stale argocd wrappers, clears stale 8080 listeners, and restarts the argocd port-forward
- provider state precedence: a live Hostinger cluster now wins over a stale active-provider state file, and the active-provider state stays in sync across Hostinger switches (no more falling through to AWS defaults)
- `make status` / smoke probes are provider-aware for Hostinger — preflight apps are reported separately and the Hostinger access layer is restarted
- preflight vcluster is now deregistered from the hub ArgoCD on destroy; stale preflight stack retired and app-cluster role relabeled on the hub
- observability: ACG monitoring secrets are created against the resolved active app-cluster instead of a stale context

### Removed
- standalone `lib-acg` subtree (`scripts/lib/acg/`) and its git remote — fully absorbed into lib-foundation

## [1.7.0] - 2026-06-13

### Added
- `k3s-hostinger` cluster provider — single-node k3s app cluster on a permanent Hostinger KVM VPS via SSH/k3sup (no VM lifecycle); env-overridable `HOSTINGER_HOST` default via `scripts/etc/hostinger/vars.sh`
- `k3s-hostinger` app cluster registration with the hub ArgoCD via mTLS cluster secret (`cluster-ubuntu-hostinger` in `cicd`)
- `bin/hostinger-status` — read-only full status report (app nodes/pods, API health, hub ArgoCD registration, ArgoCD apps/applicationsets); wired into `make status CLUSTER_PROVIDER=k3s-hostinger`
- `APP_CLUSTER_NAME` envsubst parameter for ApplicationSet destination (default `ubuntu-hostinger`) — retargets shopping-cart + observability workloads off the retired ACG `ubuntu-k3s` cluster

### Fixed
- `k3s-hostinger` make `up` arm passes `--confirm` so the deploy gate accepts non-interactive provision
- `k3s-hostinger` provider sources `shopping_cart.sh` for `_ensure_k3sup`; resolves host to IP for k3sup load
- `k3s-hostinger` remote sudo written via a single `_run_command` line (de-obfuscate the bare-sudo guard)

## [1.6.5] - 2026-06-13

### Added
- `k3s-az` Azure provider — VM provision, k3sup install, and shopping-cart deploy; wired into `bin/acg-up` and `bin/acg-down`
- Optional `provider` argument for `/acg-up`, `/acg-down`, and `/acg-resume` Slack commands
- Provider-aware `make refresh` / `make status` / `acg-refresh` / `acg-status` — active provider is recorded at provision time (state file primary, kube-context probe fallback, explicit env override) so Azure/GCP clusters no longer fall through to AWS defaults

### Fixed
- Slack relay accepts `az` as the canonical provider token (with `azure` alias) for `/acg-up` and `/acg-resume`
- SSH: non-interactive host keys in shopping-cart deploy + known_hosts prune during `acg-up` preflight
- shopping-cart cross-cluster deploy: poll for data-layer StatefulSet presence instead of one-shot check; re-login ArgoCD before cluster add; purge stale default cluster/user before kubeconfig flatten; resolve SSH alias to IP; copy k3s kubeconfig to user home for sudo-free re-export; wait for product-catalog-seed job deletion before re-apply; default SSH user to `ubuntu`
- `acg-up` Azure path: gate `az group list` behind `_az_ok` (no spurious device-code auth); require non-empty resource group in the fast-path so stale creds don't skip extraction; guard `KV_NAME` in `azure-vars.sh`; extract Azure creds in Step 1 via `acg-credential-test`
- `acg-up` OrbStack/Docker preflight: recover a stopped OrbStack VM via `orbctl start`; dismiss OrbStack update dialogs; kill stale Vault port-forward via `lsof` before rebind
- `azure.sh` no longer sources `azure-vars.sh` at top level — `az ad app create` no longer runs on every plugin load
- Webhook skips `ask` sub-jobs in `_find_job_by_thread_ts` so Codex no longer repeats prior answers

### Changed
- lib-acg subtree synced to v0.1.7 (PR #44) — Azure SP/CLI-first credential validation, extend/restart hardening
- lib-foundation subtree synced — extensible cluster-provider hook (PR #30)

## [1.6.4] - 2026-06-10

### Added
- Slack Events API text commands — `acg-status`, `acg-refresh`, `ask`, `claude`, `gemini`, `codex` now work from thread replies and top-level channel messages via Events API; slash commands continue to work as before
- Slack thread context for text commands — orphan threads create anchor jobs so replies stay threaded
- Prometheus observability stack: Pushgateway deployment metrics, Grafana dashboard with k3d tag, non-interactive auth bootstrap in webhook startup
- `make show-service-passwords` target — display all basic-auth credentials including Prometheus admin user
- ACG screenshot archival — restart failure screenshots now captured and archived to `~/.local/share/k3d-manager/screenshots/`

### Fixed
- `/claude`, `/gemini`, and `/codex` agent prompts now keep raw probe commands and verbose kubectl output out of the Slack `ANSWER:` while preserving concise diagnostic conclusions
- Pushgateway deployment metrics now retry briefly before skipping so transient Pushgateway readiness gaps do not drop the last deployment sample
- Remove remaining fork-based subprocess calls from webhook job execution — all subprocess calls now use `posix_spawn` for NEF safety
- Webhook logs command falls back to output file for acg-up jobs when logs directory is unavailable

### Changed
- lib-acg subtree synced to v0.1.4 — Azure SP/CLI-first credential validation, screenshot archival support, sandbox retry hardening

## [1.6.3] - 2026-06-07

### Added
- `/acg-resume` Slack command — checkpoint-based pipeline re-entry for interrupted ACG provisioning workflows
- `/ask` Slack command — multi-agent troubleshooting with Claude, Gemini, and Codex from job thread replies
- `make fix-*` agent fix targets — named, discoverable cluster recovery operations for agent fix mode
- Webhook Slack thread context injection — fetch thread history and inject into agent prompts for better context
- Gemini side-observation bug filing — structured OBSERVATIONS block in sandbox for automatic issue creation
- Webhook read-only bash sandbox for `/ask` agents — deny destructive kubectl/helm/rm commands
- Webhook prompt injection guard and structural system/user separation for `/ask` agents
- Webhook semaphore and timeout protection for ask jobs (5 max turns, 300s timeout)
- Webhook job context prepend injection from parent job output tail (reduce wasted turns)
- Keycloak group-ldap-mapper reconciliation during reprovisioning

### Fixed
- NEF atfork SIGSEGV: replace all post-NEF subprocess.run calls with `os.posix_spawn` for job execution, `/ask claude`, `/ask codex`
- Replace subprocess kubeconfig parse with file-based parser (no fork) to avoid NEF child crashes
- Move k8s API context initialization to webhook startup to avoid macOS NEF atfork SIGSEGV
- Use `shlex.quote()` not `shutil.quote()` in webhook job execution
- Add data-layer StatefulSet readiness check to post-provision smoke test
- Always run post-provision smoke test unconditionally (remove ArgoCD early-return gate); add reconciliation note when hub is down but services are up
- Demote data-layer sync timeout to warning when StatefulSets are already Ready (skip wait on ubuntu-k3s refresh)
- Skip data-layer sync wait when StatefulSets already ready on ubuntu-k3s
- Remove ArgoCD port-forward unload from EXIT trap in acg-up
- Fix Gemini NEF fork bug and Keycloak port 18080 conflict
- Keycloak port-forward now kills existing listener before starting (fixes port conflict on resume)
- ArgoCD controller reconnection wait before data-layer sync (ensure ArgoCD is ready on ubuntu-k3s)
- Suppress Gemini CLI startup warnings at source
- Strip Gemini CLI Warning banners from failure analysis output
- Webhook diagnosis fallback to output file for acg-resume jobs
- Webhook ask-agent sanitize (sanitize user question before job context prepend to fix ask-agent rejection)
- `/tmp` file leaks from install-sudoers, k3s-oci-storage, and session teardown (add EXIT traps)
- Remove invalid cwd kwarg from posix_spawn Gemini call
- Add 5-attempt retry loop with 15s sleeps for Keycloak admin token fetch during ACG provision
- Auto-reinstall missing system daemon plists (argocd-browser-https, keycloak-browser-http, frontend-browser-http) on acg-refresh
- Auto-install ACG npm dependencies when node_modules missing in acg-up/acg-refresh
- Patch CoreDNS NodeHosts ConfigMap with host.k3d.internal before restart in acg-refresh
- Refresh ArgoCD cluster secret with host.k3d.internal on each sandbox rotation
- Restore ubuntu-k3s kubeconfig on resume with targeted Slack advice
- Auto force-sync data-layer on ArgoCD sync timeout before failing
- Retry kubeconfig fetch on SSH delay in acg-up
- ACG credentials: click "Extend Session" button (not Cancel) on session-extension dialog
- Keycloak group-ldap-mapper reconciliation persists across reprovisioning
- Install sudoers script — use `--interactive-sudo` + NOPASSWD rules for safe self-update
- k3s-aws idempotency — skip `deploy_app_cluster` when nodes already Ready

### Changed
- Webhook output — visual diagnosis via Gemini CLI with Playwright failure screenshots
- Webhook failure analysis — enrich with live pod and ArgoCD app state + node state distinction
- Observability: prune ~40 noisy kube-prometheus-stack default alert rules; enable Grafana on ACG cluster
- Prometheus 2Gi memory limit + narrow federation scope
- Keycloak port-forward now bypasses Istio sidecar for reliability
- Health check curl timeout increased from 35s to 90s (cover full smoke test duration)
- Make `/ask` max-turns adjustable via `K3DM_ASK_MAX_TURNS` env var and `turns=N` inline token

## [1.6.2] - 2026-06-05

### Added
- `/acg-refresh` Slack slash command — routes through `workers/slack-relay` → `bin/k3dm-webhook` → `bin/acg-refresh` for on-demand credential and SSH tunnel refresh from Slack

### Fixed
- `bin/acg-refresh` now removes pre-auth sudo block for headless webhook execution (no TTY in Cloudflare Worker)
- `bin/acg-refresh` makes summary `kubectl get nodes` non-fatal (webhook has no `ubuntu-k3s` kubeconfig context)
- `bin/acg-up` adds 5-attempt retry loop with 15s sleeps for Keycloak admin token fetch to handle slow startup during provision

## [1.6.1] - 2026-06-05

### Fixed
- `bin/acg-refresh` now auto-reinstalls missing system daemon plists (`argocd-browser-https`, `keycloak-browser-http`, `frontend-browser-http`) from their wrapper scripts when detected missing on refresh — prevents dark ports 80/443/8880 after partial `acg-up` failures
- `bin/acg-refresh` regenerates Keycloak port-forward LaunchAgent plist when missing on refresh
- `bin/acg-refresh` waits for SSH tunnel port to be ready before proceeding after launchctl restart
- `bin/acg-refresh` skips sudo pre-auth prompt when credentials already cached, improving UX on repeated runs
- `bin/acg-up` installs Vault port-forward LaunchAgent (`com.k3d-manager.vault-port-forward`) during provisioning and keeps port 18200 alive across cluster restarts
- `bin/acg-up` adds `RunAtLoad` and generator script to all LaunchAgent plists for reliability
- `/acg-status` now displays caveat labels for stale ArgoCD display when ACG cluster unreachable
- Prometheus `web.config.file` additionalArg conflict with prometheus-operator v0.79.2 fixed (removed arg)

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
