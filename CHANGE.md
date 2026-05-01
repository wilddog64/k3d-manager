# Changes - k3d-manager

## [Unreleased] — `_ai_agent_review` generic AI dispatch abstraction

### Changed
- `scripts/plugins/copilot.sh`: both `copilot_triage_pod` and `copilot_draft_spec` now route through `_ai_agent_review` instead of `_copilot_review` directly — backend selected by `AI_REVIEW_FUNC` (default: `copilot`), model by `AI_REVIEW_MODEL` (default: `gpt-5.4-mini`) (`c8ac9b2f`)
- `scripts/hooks/pre-commit`: `AGENT_LINT_AI_FUNC` updated from `_copilot_review` to `_ai_agent_review` (`c8ac9b2f`)
- `scripts/tests/lib/k3d_manager_copilot.bats`: `run` calls updated to invoke `_ai_agent_review`; source path updated to subtree location (`c8ac9b2f`)
- `docs/howto/copilot.md`: all user-facing `_copilot_review` references replaced with `_ai_agent_review`; `AI_REVIEW_FUNC` + `AI_REVIEW_MODEL` env vars documented with usage table (`c8ac9b2f`)
- `docs/api/functions.md`: copilot plugin table rows updated to reference `_ai_agent_review` and `AI_REVIEW_FUNC` (`c8ac9b2f`)
- `scripts/lib/foundation/scripts/lib/system.sh` (lib-foundation subtree): `_ai_agent_review` dispatch wrapper added — routes to `_copilot_review` via `AI_REVIEW_FUNC`; `ai_agent_review.bats` 3-test suite added (`448560a`, `80bf01cd`)

### Fixed
- `scripts/lib/foundation/scripts/lib/system.sh` (lib-foundation subtree): removed `K3DM_ENABLE_AI` gate from `_copilot_review` — a lib-foundation backend must not check a consumer-specific env var; gate belongs in callers (`copilot_triage_pod`, `copilot_draft_spec`) which already have it (`657fd91`, `f6362f79`)

---

## [v1.4.0] — 2026-05-01 — Copilot CLI plugin + _copilot_review rename + sandbox rebuild hardening

### Added
- `scripts/plugins/copilot.sh`: new plugin — `copilot_triage_pod <ns> <pod>` collects `kubectl describe` + last 100 log lines and asks Copilot to diagnose the failure; `copilot_draft_spec '<desc>'` collects git context and scaffolds a `docs/bugs/` spec with Root Cause / What to Change / DoD sections; requires `K3DM_ENABLE_AI=1` (`a7ad7fac`)
- `scripts/hooks/pre-commit`: wired `AGENT_LINT_AI_FUNC="_copilot_review"` + `K3DM_ENABLE_AI="${K3DM_ENABLE_AI:-0}"` before `_agent_lint` — AI architectural lint at commit time is now opt-in (`a7ad7fac`)
- `docs/howto/copilot.md`: how-to guide — setup, `copilot_triage_pod` / `copilot_draft_spec` examples, low-level `_copilot_review` API, pre-commit hook wiring, cross-project adoption via lib-foundation subtree (`d64ddecf`)

### Changed
- `scripts/etc/argocd/applicationsets/services-git.yaml`: `targetRevision` reverted to hardcoded `main`; `${K3D_MANAGER_BRANCH}` envsubst variable removed — was only needed during v1.2.0 development (`23475ac0`)
- `bin/acg-up`: removed `export K3D_MANAGER_BRANCH` — no longer required now that ApplicationSet tracks `main` (`23475ac0`)
- `scripts/lib/acg/` subtree: pulled lib-acg `main` — extend timing fix (`9b39df02`); `_sanitizePhaseLabel` helper, dynamic `remainingMs` from live TTL API, screenshot on extend failure (`dec36c9f`)
- `Makefile`: `GHCR_PAT ?=` (was `$(shell gh auth token 2>/dev/null)`) — OAuth token lacked `read:packages`; every `make up` was overwriting `ghcr-pull-secret` with an unusable token (`7bbac0d3`)

### Fixed
- `scripts/lib/acg/cdp.sh`: `../foundation` → `foundation` — path was broken when `cdp.sh` is loaded from inside the k3d-manager subtree context (`3c70c3a8`)
- `services/shopping-cart-order/kustomization.yaml`: removed `SPRING_JPA_HIBERNATE_DDL_AUTO=update` workaround — no longer needed after upstream `shopping-cart-infra` UUID init SQL fix (`9aaa0cea`)
- `services/shopping-cart-payment/`: added `postgres-payment-apps-externalsecret.yaml` (ESO, `creationPolicy: Merge`) — Vault-managed postgres password synced to `payment-db-credentials` instead of `CHANGE_ME` placeholder (`dfb65c73`)
- `services-git.yaml`: added `ignoreDifferences` for `payment-db-credentials` Secret `/data` field — prevents ArgoCD `selfHeal` from reverting ESO-managed password on every reconcile (`dfb65c73`)
- `bin/acg-up` Step 5: Vault PAT validated against `api.github.com/user` before applying to `ghcr-pull-secret`; prompts and saves replacement PAT to Vault if expired (`3a0901cc`)
- `bin/rotate-ghcr-pat`: Vault PAT validated before use; falls through to interactive prompt if expired — prevents silently applying an unusable token to cluster (`3a0901cc`)
- `bin/acg-up` Step 5: env-supplied `GHCR_PAT` validated against `api.github.com/user` before use; falls back to Vault if invalid — closes the bypass introduced by the now-removed Makefile OAuth fallback (`7bbac0d3`)
- `scripts/lib/system.sh` (lib-foundation subtree): `_k3d_manager_copilot` → `_copilot_review` — renamed to match the `_copilot_*` helper family; no behavior change (`d8181e3f`)
- `scripts/tests/lib/k3d_manager_copilot.bats`: updated `run` calls to use `_copilot_review` after rename (`3865cd82`)

## [v1.2.0] — 2026-04-30 — lib-acg extraction + shopping-cart bootstrap + GHCR hardening

### Added
- `scripts/lib/acg/` subtree from `wilddog64/lib-acg` — ACG/GCP Playwright automation extracted from k3d-manager into a standalone library; k3d-manager stubs in `scripts/plugins/acg.sh` and `scripts/plugins/gcp.sh` delegate to subtree (`99b2e143`, `c54de858`, `84da5d5e`, `a0b44c87`, `e300db31`)
- `bin/acg-up` Step 4b: ArgoCD port-forward installed as a launchd KeepAlive agent (`localhost:8080`, auto-restarts); stops in `bin/acg-down` (`3c671667`)
- `bin/acg-up` Step 10b: `deploy_shopping_cart_data()` auto-deploys PostgreSQL (orders/payment/products), Redis cart, RabbitMQ; aligns all passwords to `CHANGE_ME`; creates `rabbitmq-credentials` + `redis-cart-secret` (`d5cf80ed`)
- `bin/rotate-ghcr-pat`: new helper to rotate `ghcr-pull-secret` from a real PAT; persists PAT to Vault `secret/data/github/pat` for both interactive and piped input (`5d139afb`, `f4a9d78b`)
- `services/shopping-cart-namespace/`: dedicated ArgoCD Application owns `Namespace/shopping-cart-apps` with `istio-injection: enabled` — partial fix for SharedResourceWarning (`5d139afb`)
- `services/shopping-cart-order/kustomization.yaml`: TCP socket probes (readiness+startup), `SPRING_JPA_HIBERNATE_DDL_AUTO=update`, `SPRING_RABBITMQ_*` env vars — workarounds for order-service init SQL and RabbitMQHealthIndicator NPE (`9db9589c`, `013cfd08`, `20b0408e`, `4ad6bbae`)
- `bin/acg-sync-apps`: persistent frontend port-forward on `localhost:8081` after sync; stops in `bin/acg-down` (`6eee7afc`)

### Changed
- `scripts/plugins/gemini.sh` (was `antigravity.sh`): all `antigravity_*` functions renamed to `gemini_*`; `gemini.sh` sources CDP helpers from `scripts/lib/acg/` subtree (`20df717c`)
- `scripts/etc/argocd/applicationsets/services-git.yaml`: `targetRevision` and `revision` now use `${K3D_MANAGER_BRANCH}` envsubst variable (set from `git rev-parse --abbrev-ref HEAD` in `bin/acg-up`) so the ApplicationSet tracks the current branch during development; reverts to `main` after merge (`522aceb7`)
- `scripts/etc/argocd/projects/platform.yaml.tmpl`: `orphanedResources.warn: false` — suppresses OrphanedResourceWarning for imperative bootstrap secrets not tracked by ArgoCD (`625b82c2`)
- `bin/acg-up`: GHCR pull secret sourced from Vault `secret/data/github/pat` first; fails closed if neither `GHCR_PAT` nor Vault PAT is set — prevents `gh auth token` OAuth fallback which lacks `read:packages` (`9b2d3cb5`)
- `bin/acg-up`: Vault sealed-state recovery — preserves health JSON from non-2xx `/v1/sys/health`, auto-runs `deploy_vault --re-unseal`, rechecks before continuing (`786c5e6c`)
- `scripts/lib/providers/tunnel.sh`: reverse tunnel port mapping changed from `-R 8200:localhost:8200` to `-R 8200:localhost:18200` to prevent same-port reset; local Vault port-forward uses `18200:8200`
- `bin/acg-down`: `--keep-hub` flag added; continues Hub teardown even when CloudFormation teardown fails due to recycled sandbox credentials (`68eba803`, `727cde2f`)
- `Makefile` `sync-apps`/`status`: `APP_CONTEXT` passed as `ubuntu-gcp` when `CLUSTER_PROVIDER=k3s-gcp` (`7585d63c`, `f2f74b98`)

### Fixed
- `scripts/plugins/argocd.sh`: `envsubst` call updated to include `$K3D_MANAGER_BRANCH` alongside `$ARGOCD_NAMESPACE` (`522aceb7`)
- `bin/acg-down` (k3s-gcp): calls `_provider_k3s_gcp_destroy_cluster` directly — removed broken `destroy_cluster` → `_cluster_provider_call` routing (`b8b72a67`)
- `bin/acg-down` (k3s-gcp): `GCP_PROJECT` auto-detected from `~/.local/share/k3d-manager/gcp-service-account.json` when not set in environment (`ca18e581`)
- `bin/acg-sync-apps`: `argocd app list` replaced with `kubectl get applications.argoproj.io -A` (CRD query — no active port-forward required) (`237d0b2c`)
- `bin/acg-sync-apps`: Hub cluster context pre-flight check before kubectl commands (`7fc1a6f4`)
- `scripts/lib/providers/k3s-gcp.sh`: `_gcp_create_instance` now idempotent — skips create if instance already exists (`7582e290`)
- `bin/acg-up` (k3s-gcp): Hub cluster + Vault + ArgoCD now created for GCP provider (previously skipped after Step 2) (`f8f9d93b`)
- `bin/acg-status`: `aws sts get-caller-identity` gated behind `CLUSTER_PROVIDER != k3s-gcp` (`20e4bd44`)
- `scripts/lib/acg/playwright/gcp_login.js`: Chrome account-sync sign-in dialog dismissed via `context.on('page', ...)` handler (`lib-acg 5c0e8e2d`)
- `scripts/lib/acg/playwright/acg.js`: "Session Extended" modal dismissed via Escape + X-button fallback + `waitFor(hidden)` guard (`lib-acg 5c0e8e2d`)
- `scripts/lib/acg/playwright/acg_credentials.js`: CDP context miss when sandbox card is visible but wrong frame used — fixed with scoped frame selection (`lib-acg 7cb7f64a`)

## [v1.1.0] — 2026-04-24 — Unified ACG automation AWS + GCP

### Added
- GCP provider (`k3s-gcp`): GCP identity bridge, Playwright CDP OAuth automation, GCP cluster provisioning — firewall, GCE instance, k3sup install, kubeconfig merge (`9686e5c3`, `916d71fc`, `927cb452`)
- `bin/acg-sync-apps`: ArgoCD port-forward reuse with state persistence, managed PF metadata, foreign listener replacement, failure log retention in `scratch/logs/` (`f18c8ec7`, `890ba2a6`, `2e766a43`)

### Changed
- `bin/acg-down`: tears down local Hub cluster by default; `--keep-hub` to opt out (`3fd6f4d6`)
- `bin/acg-up` Step 3.5: auto-creates Hub cluster when missing instead of aborting (`73382eb2`)
- `bin/acg-up` Step 3.6: bootstraps Vault + LDAP + ArgoCD on fresh Hub create with `--confirm` safety gate (`c59f2c3a`, `8b43122f`, `c650f032`)

### Fixed
- `bin/acg-sync-apps`: `ARGOCD_APP` default changed from `data-layer` to `rollout-demo-default` — only app always present after bootstrap (`b83d5596`)
- `bin/acg-sync-apps`: readiness checks use `http://healthz` matching ArgoCD `server.insecure=true` mode (`0896d9ec`)
- `bin/acg-sync-apps`: non-interactive ArgoCD login (`--plaintext --skip-test-tls --grpc-web </dev/null`) (`c3a2f146`)
- `bin/acg-down`: provider-aware teardown dispatch — GCP calls `destroy_cluster --confirm`; expired AWS credentials path is silent (`706e0ba2`, `ae2fca66`, `07ca18a6`)
- `bin/acg-up`: Vault preflight checks Hub reachability and Vault seal state after OrbStack restart (`e577579e`)
- `scripts/plugins/argocd.sh`: LDAP vars sourced before dependency checks; `LDAP_NAMESPACE` var replaces hardcoded `ldap`; `_kubectl --no-exit` for soft namespace probes; non-interactive CLI login (`1c3ead28`, `032bfadb`, `fdbef8c4`)
- `scripts/plugins/eso.sh`: wait for webhook endpoint + all three deployments before returning — prevents race with ESO-dependent resources (`e7b06b2b`)
- `scripts/playwright/acg_credentials.js`: polite tab selection; disabled Start Sandbox `isEnabled()` guard (`131dca33`, `13d398ab`)
- `scripts/lib/cluster_provider.sh` (k3d): RETURN trap self-clears to prevent re-fire in parent scope; `configure_istio` EXIT trap scoped to RETURN (`e6a9ec91`, `258de0d1`)
- `scripts/playwright/gcp_login.js`: capture OAuth URL on Linux headless; clean-slate login pattern (`927cb452`, `6ae2a6c3`)
- `bin/acg-sync-apps`: pre-built port-forward rejects pre-existing port 8080 listener before starting (`3a1e2554`)

## [v1.0.6] — 2026-04-11 — AWS SSM support for k3s-aws provider

### Added
- `scripts/plugins/ssm.sh`: new `ssm_wait`, `ssm_exec`, `ssm_tunnel` helpers — opt-in EC2 SSM access via `K3S_AWS_SSM_ENABLED=true`; `_provider_k3s_aws_deploy_cluster` uses SSM paths when enabled (`8d35e2cb`)
- `acg-cluster.yaml` CloudFormation: IAM role + instance profile granting `AmazonSSMManagedInstanceCore` — EC2 instances auto-register with SSM on launch (`8d35e2cb`)
- `Makefile`: `ssm` target (ensures `session-manager-plugin` is installed) and `provision` target (full provision shortcut); `provision` depends on `ssm` (`b977709a`)

### Fixed
- `acg.sh` `_acg_deploy_cluster`: added `--capabilities CAPABILITY_NAMED_IAM` to `aws cloudformation deploy` — required because CloudFormation stack now contains a named IAM role and instance profile (`290edd1f`)

## [v1.0.5] — 2026-04-10 — antigravity decoupling + LDAP Vault KV seeding

### Changed
- `acg.sh` / `antigravity.sh`: exported `antigravity_acg_extend` in `antigravity.sh` was renamed/moved to `acg_extend_playwright` (public) / `_acg_extend_playwright` (impl) in `acg.sh` — `acg_watch` calls `_acg_extend_playwright` (impl) directly in-process; the launchd wrapper generated by `_acg_watch_write_wrapper` calls the public `acg_extend_playwright` via the dispatcher; `antigravity.sh` no longer exports the helper; removes false coupling between ACG watch loop and Antigravity IDE (`291a60dc`)

### Fixed
- `bin/acg-up`: LDAP admin and readonly passwords now generated and seeded to `secret/data/ldap/admin` in Vault KV at provision time — ESO ExternalSecret in `shopping-cart-infra` syncs them to the `identity` namespace (`e5b77474`)

## [v1.0.4] — 2026-04-10 — ACG extend hardening: button-first search, random passwords, sandbox expired guidance

### Fixed
- `acg_extend.js`: button-first approach — checks for extend button immediately before TTL logic; sanitizes selectors to remove `h4` false-positive; handles "trapped UI" by forcing Start/Resume click when extend button is missing (`64313224`, `715bfaa1`, `1d2f70ce`)
- `acg_extend.js`: midnight date-wrap bug fixed — `if (shutdownTime < now)` without narrow hour guard; robust TTL parsing with CDP + fallback (`c21f33d9`, `d0dcdf22`)
- `acg.sh` / `acg_credentials.js`: standardize all Pluralsight URLs to `/hands-on/playground/` — prevents Cloudflare block on `/cloud-labs/` path (`89b8572f`)
- `_acg_check_credentials`: expanded error message explains both remediation paths when sandbox is expired (start new sandbox + `acg_get_credentials` + `make up`) vs still running (`bf569a80`)
- `bin/acg-up`: replace 6 hardcoded redis/postgres/rabbitmq passwords with per-run `openssl rand -base64 24 | tr -d '=+/'` — AES/payment placeholders unchanged (`f709cb3c`)

## [v1.0.3] — 2026-04-05 — ACG full stack fixes: ESO 1.0.0, ArgoCD registration, GHCR_PAT masking, Chrome CDP

### Added
- `make sync-apps`: port-forwards argocd-server, logs in, syncs `cicd/data-layer`, shows remote pod status (`a47a4f5`)
- `make argocd-registration`: re-registers ubuntu-k3s with ArgoCD (grabs token, reads server URL, switches context, restarts controller) — safe to run after sandbox recreation (`7dfa093`)
- `acg_chrome_cdp_install`/`acg_chrome_cdp_uninstall`: launchd plist agent for persistent Chrome CDP session on macOS; `make chrome-cdp`/`chrome-cdp-stop` Makefile wrappers (`fe0f313`, `513009f`, `4ce2b51`)

### Fixed
- ESO default version bumped to 1.0.0 — `v0.14.0` only serves `v1beta1`; `external-secrets.io/v1` GA requires 1.0.0+ (`4dd1854`)
- `ClusterSecretStore` manifest in `bin/acg-up` bumped from `external-secrets.io/v1beta1` to `external-secrets.io/v1` — ESO 1.0.0 dropped v1beta1 serving (`b8bcb89`)
- `bin/acg-up` step 10: reads ubuntu-k3s server URL from kubeconfig; switches context to `k3d-k3d-cluster` before `register_app_cluster` — fixes ArgoCD registering EC2 cluster at wrong endpoint (`dec667f`, `5cbc3cf`)
- `make up` no longer echoes `GHCR_PAT="ghp_xxx..."` to console — `@` prefix suppresses Make command echo (`613bb1e`)
- `bin/acg-refresh`: skips credential extraction when existing AWS creds are still valid — prevents Chrome CDP lock conflict (`6dcb913`)
- `bin/acg-up`: skips credential extraction when existing AWS creds are valid (`dc2c82d`)
- `bin/acg-up`: waits for ESO webhook endpoints before applying ClusterSecretStore; poll window extended to 180s (`96629e0`, `e8b296b`)
- `acg-extend` selectors updated for current Pluralsight UI — Modal with "Extend Session" button only visible at ≤1hr remaining (`e39efa4`)
- `acg_credentials.js`: CDP probe removed — always uses `launchPersistentContext`; `acg_get_credentials` no longer probes CDP or launches Chrome manually (`ac260d0`)
- Platform detection: `_is_mac` → `[[ "$(uname)" == "Darwin" ]]` in `acg.sh` and `antigravity.sh` — `_is_mac` not available outside dispatcher context (`513009f`, `4ce2b51`)
- `bin/acg-up`: replaces `vault kv put` CLI calls with `curl` against Vault HTTP API — `vault` binary not installed on EC2 nodes (`07e89f9`)
- `bin/acg-up`: seeds `secret/data/rabbitmq/default` in Vault KV — credentials for RabbitMQ StatefulSet and app-namespace ExternalSecrets on remote cluster (`77e69e2`)

## [v1.0.2] — 2026-04-03 — full stack automation: make up, ESO, ArgoCD, vault-bridge, Playwright fixes

### Added
- `make up` one-command full stack: `bin/acg-up` now runs 12 automated steps — AWS credentials → 3-node k3s cluster → SSH tunnel → Vault port-forward → ghcr-pull-secret → vault-bridge Service → argocd-manager SA bootstrap → helm + ESO install → vault-token + ClusterSecretStore → ArgoCD cluster registration + controller restart → ClusterSecretStore verify → sandbox TTL watcher (`e4b7527`)
- `Makefile` at repo root: `make up/down/refresh/status/creds/help` with `GHCR_PAT` auto-populated from `gh auth token` (`e4b7527`, `82a0376`)
- Vault port-forward step in `bin/acg-up`: persistent `kubectl port-forward svc/vault` with PID tracking and `disown` so it survives shell exit (`e4b7527`)
- vault-bridge headless Service in `secrets` namespace on remote cluster — enables `vault-bridge.secrets.svc.cluster.local:8201` DNS (`e4b7527`)
- `argocd-manager` SA + ClusterRole + static token Secret bootstrap on remote cluster via SSH (`e4b7527`)
- `helm` + ESO v0.9.20 install on remote cluster with idempotency check (`e4b7527`)
- `vault-token` Secret + `ClusterSecretStore` apply on remote cluster from local `vault-root` secret (`e4b7527`)
- ArgoCD cluster registration with static SA token + `argocd-application-controller` restart (`e4b7527`)
- ClusterSecretStore Ready poll (12×10s) before watcher step (`e4b7527`)
- `bin/acg-down`: Vault port-forward PID cleanup on teardown (`e4b7527`)

### Fixed
- `bin/` SCRIPT_DIR contamination: all entry points now compute `REPO_ROOT` first then `SCRIPT_DIR="${REPO_ROOT}/scripts"` — fixes plugin sourcing (`29a8535`)
- `antigravity_acg_extend`: replaced `_err` with `_info + return 1` so pre-flight extend failure is non-fatal (`ed3a548`)
- `acg_credentials.js`: CDP `browser.close()` replaces missing `disconnect()` in both the no-session path and `finally` block (`82a0376`)
- `bin/acg-up` Step 9: reads `root_token` key (not `token`) from `vault-root` secret (`82a0376`)
- `acg.sh`: `_antigravity_launch` → `_browser_launch` call site updated; launchd wrapper now invokes `k3d-manager` entry point instead of sourcing plugin directly (`50734a7`)
- `vcluster.sh`: bare `linux` removed from `debian|redhat|wsl` install arm — falls through to unsupported error per convention (`50734a7`)
- `shopping_cart.sh`: SSH heredoc wrapped in `_run_command` for consistent logging (`50734a7`)

## [v1.0.1] — 2026-03-31 — multi-node k3s-aws + CloudFormation + Playwright hardening

### Added
- `k3s-aws` multi-node cluster: `_acg_provision_agents`, `_k3sup_join_agent`, node labeling — 3-node cluster verified end-to-end (`0c89f4e`)
- CloudFormation parallel provisioning: replaces sequential `aws ec2 run-instances` loop; single `wait stack-create-complete` covers all 3 nodes (`abe149f`)
- Playwright auto sign-in via Google Password Manager in `acg_credentials.js`: detects sign-in link, fills email, submits, waits for redirect back to `app.pluralsight.com` (`52cf05e`)
- vCluster how-to doc (`docs/howto/vcluster.md`) and API reference entry (`d4b8691`)

### Fixed
- `acg_get_credentials`: removed redundant `_ensure_antigravity`, `_antigravity_launch`, `_antigravity_ensure_acg_session` pre-calls that disrupted Chrome CDP page state; replaced with CDP health check — Chrome launched on demand only when port 9222 is not responding (`f574e05`)
- `scripts/playwright/acg_credentials.js`: 30s overall timeout increased to 120s; `browser.disconnect()` reverted to `browser.close()` — CDP connections use `close()` not `disconnect()` (`2814396`, `a145075`)
- `scripts/playwright/acg_credentials.js`: `isVisible()` calls without timeout replaced with 5–15s timeouts; `credentialsAlreadyVisible` guard skips Start/Open flow when panel already open (`7a7ec82`)
- `_agent_audit` IP allowlist: replaced per-file inner loop with pre-loaded `grep -Fqx` approach; added `-f` guard to reject directory paths; synced with lib-foundation v0.3.15 (`314bab8`)
- Pre-commit hook: exports `AGENT_IP_ALLOWLIST` env var pointing to `scripts/etc/agent/hardcoded-ip-allowlist` — CloudFormation CIDR literals exempted from IP audit (`c9419f2`)

### Removed
- `bin/setup-jenkins-cli-ssl`, `bin/setup-argocd-cli-ssl`, `bin/create-k8s-agent-test-jobs` — redundant scripts superseded by plugin functions (`980ca8d`)

---

## [v1.0.0] — 2026-03-29 — k3s-aws provider foundation

### Added
- `CLUSTER_PROVIDER=k3s-aws` provider: `_provider_k3s_aws_deploy_cluster` (pre-flight extend → `acg_provision` → `deploy_app_cluster` → `tunnel_start` → `acg_watch`) and `_provider_k3s_aws_destroy_cluster` in `scripts/lib/providers/k3s-aws.sh` (`4aba999`)
- `aws_import_credentials` in new `scripts/plugins/aws.sh`: supports CSV (IAM Download), quoted/unquoted export, labeled (Pluralsight), credentials file formats; replaces `acg_import_credentials` under generic namespace (`be7e997`)
- `acg_provision --recreate` flag: tears down existing instance before provisioning fresh — handles unknown sandbox state (`51bdf3a`)
- `acg_watch [interval_seconds]`: background TTL watcher; calls `antigravity_acg_extend` every 3.5h while EC2 instance alive; stops automatically when instance is gone (`51bdf3a`)
- Pre-flight sandbox extend in `_provider_k3s_aws_deploy_cluster`: ensures fresh 4h TTL before long deploy; non-fatal on Antigravity unavailability (`51bdf3a`)

### Fixed
- `acg_get_credentials`: `acg.sh` now sources `antigravity.sh` — `_ensure_antigravity`/`_antigravity_launch` always defined at load time (`4357f90`)
- `deploy_app_cluster`: resolves external IP from `~/.ssh/config` HostName before falling back to SSH alias — kubeconfig server address now correct (e.g. `https://1.2.3.4:6443` not `https://ubuntu:6443`) (`51983d3`)
- `_acg_provision_stack`: keypair import uses `_run_command --soft` — silent on duplicate key, idempotent on re-run; removes noisy error that caused agent misdiagnosis (`4a57f44`)
- `antigravity_acg_extend`: Playwright prompt now calls `page.goto()` unconditionally with `waitUntil: 'networkidle'` — no longer aborts on stale/404 browser state (`4a57f44`)

### Changed
- `acg_import_credentials` → deprecated alias for `aws_import_credentials` (generic AWS namespace) (`be7e997`)
- `_cluster_provider_call` in `scripts/lib/provider.sh`: normalizes hyphens to underscores in provider slug for function lookup — enables `CLUSTER_PROVIDER=k3s-aws` routing

---

## [v0.9.21] — 2026-03-29 — `_ensure_k3sup` auto-install helper

### Added
- `_ensure_k3sup` private helper in `scripts/plugins/shopping_cart.sh`: auto-installs k3sup via `brew install k3sup` (macOS/Linuxbrew) or `curl | sudo sh` (Debian/Ubuntu); emits `_err` with manual install guidance if neither installer is available (`11a3ac1`)

### Changed
- `deploy_app_cluster`: replaces raw `command -v k3sup` hard-error with `_ensure_k3sup` — consistent with `_ensure_node` / `_ensure_copilot_cli` auto-install pattern (`11a3ac1`)

### Tests
- 2 new BATS tests in `scripts/tests/plugins/shopping_cart.bats`: `_ensure_k3sup` returns 0 when k3sup present; errors when no installer available (`11a3ac1`)

---

## [v0.9.20] — 2026-03-29 — ACG Chrome launch + SPA navigation fix

### Fixed
- `_antigravity_launch` in `scripts/plugins/antigravity.sh`: now launches Google Chrome (not Antigravity IDE) with `--remote-debugging-port=9222 --password-store=basic --user-data-dir=~/.config/acg-chrome-profile`; fixes macOS Keychain `errSecInteractionNotAllowed` blocking CDP port bind on cold start (`8dd9cbb`, `653896e`)
- `scripts/playwright/acg_credentials.js`: no longer calls `page.goto()` when already on `app.pluralsight.com` — hard navigation was destroying SPA auth state causing permanent skeleton-loading; now finds Pluralsight page by URL, SPA-navigates via nav link click when needed, waits for `aria-busy` to clear; credential selector timeout 30s → 60s (`8dd9cbb`)

---

## [v0.9.19] — 2026-03-28 — ACG automated credential extraction

### Added
- `acg_get_credentials [sandbox-url]`: Playwright-based AWS credential extraction from Pluralsight sandbox "Cloud Access" panel via Antigravity CDP; optional URL defaults to `_ACG_SANDBOX_LIST_URL` (listing page auto-start flow); writes to `~/.aws/credentials` with masked key preview (`3970623`, `a7aea9c`, `67a445c`)
- `acg_import_credentials`: stdin fallback — parses both Pluralsight label format (`AWS Access Key ID: ...`) and shell export format (`export AWS_ACCESS_KEY_ID=...`); writes `[default]` profile with 600 permissions (`3970623`)
- `_acg_write_credentials`: private helper — writes `[default]` profile to `~/.aws/credentials`; handles optional session token (AKIA permanent IAM keys supported) (`3970623`, `67a445c`)
- `_ACG_SANDBOX_LIST_URL`: configurable listing page URL constant — `https://app.pluralsight.com/hands-on/playground/cloud-sandboxes` (`a7aea9c`)
- `scripts/playwright/acg_credentials.js`: static Node.js Playwright script — CDP connect, dual-path logic (listing page auto-start vs direct sandbox URL), two-pass selector strategy with regex fallback; live-verified against Pluralsight sandbox (`a7aea9c`, `67a445c`)
- 8 BATS tests in `scripts/tests/lib/acg.bats` (`3970623`)

### Fixed
- `acg_get_credentials`: removed hardcoded `NODE_PATH=/opt/homebrew/lib/node_modules` — not portable to Linux (`d3ea4b6`, `a90ae5d`)
- `acg_get_credentials`: removed inline `source antigravity.sh` — dispatcher handles plugin loading (`a90ae5d`)

---

## [v0.9.18] — 2026-03-28 — Pluralsight URL migration (ACG → app.pluralsight.com)

### Fixed
- `_ACG_SANDBOX_URL` in `scripts/plugins/acg.sh`: updated from retired `learn.acloud.guru/cloud-playground/cloud-sandboxes` to `app.pluralsight.com/cloud-playground/cloud-sandboxes` (`8f857ea`)
- `_antigravity_ensure_acg_session` in `scripts/plugins/antigravity.sh`: updated navigation URL, login URL (`/id/signin`), and DOM selector hints for Pluralsight; removed "ACG domain migration pending" language from bypass guard (`8f857ea`)

### Docs
- `docs/api/functions.md`: `_antigravity_ensure_acg_session` — updated domain reference, added `K3DM_ACG_SKIP_SESSION_CHECK` env var table, removed stale redirect note
- `docs/howto/acg.md`: updated sandbox URL and first-run login note to Pluralsight
- `docs/howto/antigravity.md`: updated example URL and bypass comment

---

## [v0.9.17] — 2026-03-27 — Antigravity model fallback + ACG session check + nested agent fix

### Added
- `_antigravity_ensure_acg_session`: CDP login check for ACG (`learn.acloud.guru`) — waits for login if not authenticated, 300s timeout (`bec1552`)
- `_antigravity_gemini_prompt`: model fallback helper — tries `gemini-2.5-flash → gemini-2.0-flash → gemini-1.5-flash`; detects 429/RESOURCE_EXHAUSTED/ModelNotFoundError and degrades automatically (`d004bb3`)
- `_ANTIGRAVITY_GEMINI_MODELS` array: ordered `gemini-2.5-flash` first — fastest, most capable; older models as fallback only (`3288fe2`)
- `docs/gists/install.md`: 3-line install gist for k3d-manager clone + run (`fa91648`)

### Fixed
- `_antigravity_gemini_prompt`: `--approval-mode yolo` added — disables nested agent confirmation prompts; temp dir changed to `${HOME}/.gemini/tmp/k3d-manager/` — resolves Plan Mode + path restriction in inner `gemini` subprocess (`978b215`)
- `_antigravity_gemini_prompt`: `sleep 2` before each model attempt — prevents rate-limit swarming (`1ac653d`)
- `_antigravity_gemini_prompt`: removed overbroad `*"404"*` match — only match specific API errors (`ModelNotFoundError`) to avoid false positives from Playwright page 404s (`fe4915c`)
- All Playwright temp scripts moved from `/tmp/ag_*.js` to `${HOME}/.gemini/tmp/k3d-manager/ag_*.js` (`978b215`)
- Reverted unauthorized `JENKINS_HOME_PATH` default change in `cluster_var.sh` — scope creep by Gemini (`4e5c16d`)

### Docs
- `docs/plans/roadmap-v1.md`: shopping-cart rigor gap section + v1.2.0 distribution packages (Debian/RedHat/Homebrew) (`fa91648`)
- `AGENTS.md` + `GEMINI.md`: `--approval-mode yolo` safety rule — only permitted for tightly scoped prompts writing to workspace temp dir (`2343d1e`)
- `GEMINI.md`: Known Failure Mode added — unsolicited code changes outside task scope (`37d8d6d`)
- `docs/issues/2026-03-27-acg-session-e2e-fail.md`: E2E failure — nested agent Plan Mode restriction
- `docs/issues/2026-03-28-acg-domain-redirection.md`: ACG platform URL retired; `learn.acloud.guru` → Pluralsight redirect

---

## [v0.9.16] — 2026-03-26 — Antigravity IDE + CDP browser automation

### Added
- `scripts/plugins/antigravity.sh`: rewritten plugin — gemini CLI + Playwright browser automation engine (`b2ba187`); public functions: `antigravity_install`, `antigravity_trigger_copilot_review`, `antigravity_poll_task`, `antigravity_acg_extend`
- `_antigravity_launch`: auto-starts Antigravity IDE with `--remote-debugging-port=9222`; polls port 9222 via `_antigravity_browser_ready` (`e83d89d`)
- `_antigravity_ensure_github_session`: CDP login check + wait loop for GitHub auth (`e83d89d`)
- `_ensure_antigravity_ide`, `_ensure_antigravity_mcp_playwright`, `_antigravity_browser_ready`: Antigravity install + MCP config + port readiness helpers via lib-foundation v0.3.12 (`45168cf`)

### Fixed
- `_antigravity_launch`: replaced `_curl` boolean probe with `_run_command --soft -- curl` — prevents silent `exit 1` on first poll iteration (`6b98902`)
- lib-foundation v0.3.13 subtree pull: `_antigravity_browser_ready` probe fix upstream (`dfcb590`)

---

## [v0.9.15] — 2026-03-25 — Antigravity × Copilot validation + ldap stdin hardening

### Added
- `docs/issues/2026-03-24-antigravity-copilot-agent-validation.md`: validation verdict — automation blocked by auth isolation; Playwright CLI cannot inherit browser session cookies

### Security
- `scripts/etc/ldap/ldap-password-rotator.sh`: `vault kv put` now reads credentials from stdin (`@-`) — prevents password exposure in `ps aux` (`e91a662`)

---

## [Unreleased] v0.9.14 — if-count elimination: system.sh

### Changed
- **`scripts/lib/system.sh`**: Extracted `_run_command_handle_failure` from `_run_command` — drops if-count from 9 to 7; failure logging + soft/hard exit now in dedicated helper (via lib-foundation `feat/v0.3.7` `b9fcbf6`)
- **`scripts/lib/system.sh`**: Extracted `_node_install_via_redhat` from `_ensure_node` — drops if-count from 9 to 7; dnf/yum/microdnf dispatch now in dedicated helper (via lib-foundation `feat/v0.3.7` `b9fcbf6`)
- **`scripts/etc/agent/if-count-allowlist`**: Both `system.sh:_run_command` and `system.sh:_ensure_node` entries removed — allowlist is now fully empty

### Security
- `scripts/etc/ldap/ldap-password-rotator.sh`: `vault kv put` now reads credentials from stdin (`@-`) instead of CLI args — prevents password exposure in Vault pod `ps aux`

---

## [v0.9.13] — 2026-03-23 — v0.9.12 retro + process: mergeable_state check

### Added
- v0.9.12 retrospective (`docs/retro/2026-03-23-v0.9.12-retrospective.md`) — documents merge conflict / CI silence root cause, `copilot auth status` vs env var auth decision, `K3DM_COPILOT_LIVE_TESTS` opt-in guard rationale

### Changed
- `/create-pr` skill — Step 0 added to Post-creation Steps: check `mergeable_state` immediately after PR creation; if `"dirty"`, resolve conflicts before waiting for CI. Added "Dirty PR silently kills CI" to Known Failure Modes.

---

## [v0.9.12] — 2026-03-23 — Copilot CLI auth CI integration + lib-foundation v0.3.6

### Added
- **`.github/workflows/ci.yml`**: "Install Copilot CLI" step (conditional on `COPILOT_GITHUB_TOKEN`) — installs from `https://gh.io/copilot-install`, adds `$HOME/.local/bin` to `GITHUB_PATH`; "Run lib unit BATS" step now passes `COPILOT_GITHUB_TOKEN`, `K3DM_ENABLE_AI=1`, and `K3DM_COPILOT_LIVE_TESTS=1`
- **`scripts/tests/lib/ensure_copilot_cli.bats`**: Live binary test (`copilot version`) gated behind `K3DM_COPILOT_LIVE_TESTS=1` + `COPILOT_GITHUB_TOKEN`; install-path tests stubbed for `_copilot_auth_check` to prevent `K3DM_ENABLE_AI` cascade
- lib-foundation v0.3.6 subtree pull (`9a030bc`) — `doc_hygiene.sh` + hooks now in `scripts/lib/foundation/`

### Fixed
- `K3DM_ENABLE_AI=1` env cascade — install-path BATS tests now stub `_copilot_auth_check` so live auth check does not fire when copilot binary is present but unstubbed (`fbb9ba4`)
- `copilot auth status` vs env var auth — live test changed to `copilot version` (which succeeds with `COPILOT_GITHUB_TOKEN` set); `copilot auth status` checks credential store only (`fbb9ba4`)

---

## [v0.9.11] — 2026-03-22 — dynamic plugin CI

### Added
- **`.github/workflows/ci.yml`**: New `detect` job (ubuntu-latest) runs after `lint` — computes changed files via `git diff --name-only origin/main...HEAD`, emits `skip_cluster=true` for docs-only PRs, and emits per-plugin flags (`run_jenkins`, `run_vault`, `run_eso`, `run_keycloak`, `run_cert_manager`) when the corresponding plugin file is modified (`e2241d6`).

### Changed
- **`.github/workflows/ci.yml`**: `stage2` job now depends on `detect`; skips entirely when `skip_cluster=true`; always runs `test_istio` as structural baseline; conditionally runs `test_jenkins`, `test_vault`, `test_eso`, `test_keycloak`, or `test_cert_rotation` only when the matched plugin changed (`e2241d6`).

---

## [v0.9.10] — 2026-03-22 — if-count allowlist elimination (jenkins)

### Changed
- **`scripts/plugins/jenkins.sh`**: Extracted helpers (`_jenkins_deploy_infra_prereqs`, `_jenkins_select_template`, `_jenkins_load_ldap_secret`, `_jenkins_apply_istio_resources`, `_jenkins_deploy_cert_rotator_if_enabled`, `_jenkins_deploy_agent_resources`, `_jenkins_run_helm_install`, `_jenkins_deploy_with_retry`, etc.) so all 4 allowlisted functions drop to ≤ 8 ifs (`733123a`).
- **`scripts/etc/agent/if-count-allowlist`**: Removed all jenkins (4) entries — allowlist now contains only `system.sh:_run_command` and `system.sh:_ensure_node` (blocked on lib-foundation upstream).

---

## [v0.9.9] — 2026-03-22 — if-count allowlist elimination (ldap + vault)

### Changed
- **`scripts/plugins/ldap.sh`**: Extracted 11 private helpers (`_ldap_generate_or_load_admin_creds`, `_ldap_build_ldif_content`, `_ldap_resolve_chart_ref`, `_ldap_ensure_helm_chart_available`, `_ldap_fetch_import_prereqs`, `_ldap_read_sync_creds`, `_ldap_parse_deploy_opts`, `_ldap_deploy_prerequisites`, `_ldap_ensure_vault_ready`, `_ldap_run_post_deploy`, `_ldap_run_ad_smoke_test`) so all 7 allowlisted functions drop to ≤ 8 ifs (`ba6f3a9`).
- **`scripts/plugins/vault.sh`**: Extracted 6 private helpers (`_vault_parse_deploy_opts`, `_vault_source_optional_vars`, `_vault_reinit_from_reset`, `_vault_build_policy_hcl`, `_vault_build_parent_metadata_policy`, `_vault_load_cached_shards`, `_vault_clear_cached_shards`) so all 5 allowlisted functions drop to ≤ 8 ifs (`365846c`).
- **`scripts/etc/agent/if-count-allowlist`**: Removed all ldap (7) and vault (5) entries — allowlist now contains only `system.sh:_run_command` and `system.sh:_ensure_node` (blocked on lib-foundation upstream).

---

## [Unreleased] v0.9.8

### Fixed
- **`scripts/plugins/jenkins.sh`**: Extracted `_jenkins_format_pull_failure_details()` helper from `_jenkins_warn_on_cert_rotator_pull_failure` — reduces if-count from 9 to 5; removes function from if-count allowlist (`9a4f795`).
- **`scripts/etc/agent/if-count-allowlist`**: Removed `indent` (awk function inside here-doc — scanner false positive) and `_jenkins_warn_on_cert_rotator_pull_failure` (refactored above) (`9a4f795`).

### Added
- **`scripts/tests/lib/dry_run.bats`**: 5 BATS tests covering `--dry-run` / `K3DM_DEPLOY_DRY_RUN` — plain, `--prefer-sudo`, `--require-sudo`, and normal-mode cases (`f1b4ca7`).
- **`docs/issues/2026-03-22-if-count-allowlist-deferred.md`**: Tracks 18 remaining allowlisted functions (jenkins x4, ldap x7, vault x5, system x2) deferred to v0.9.9+ with per-function if-counts and decomposition notes (`9a4f795`).
- Copilot CLI auth integration test — real `_copilot_auth_check` BATS test guarded by `COPILOT_GITHUB_TOKEN`; CI installs Copilot CLI from `https://gh.io/copilot-install` and sets `K3DM_ENABLE_AI=1` for the BATS run.

### Changed
- **`README.md`**: Safety Gates section — added note that `--dry-run` / `-n` sets `K3DM_DEPLOY_DRY_RUN=1`; can be set in environment to dry-run full sessions (`f1b4ca7`).

---

## [v0.9.7] — 2026-03-22 — lib sync + code quality + tooling polish

### Fixed
- **`scripts/lib/core.sh`**: `deploy_cluster` now prints help and returns 1 when called with no args, preventing accidental cluster creation (`51a40b0`).

### Changed
- **`scripts/lib/system.sh`**: Synced from lib-foundation `b60ddc6` — adds `_run_command_resolve_sudo()`, `resolver_rc` unified error handling, `--interactive-sudo` flag throughout, `helm_global_arr` word-split fix (`56aec2f`).
- **`scripts/lib/agent_rigor.sh`**: Synced from lib-foundation `15f041a` — adds allowlist file support, `kubectl exec` credential leak check, bare-sudo expanded diff.
- **`scripts/lib/foundation/`**: Subtree pulled to lib-foundation `b60ddc6` (TTY fix + allowlist feature).
- **`bin/smoke-test-cluster-health.sh`**: Sources `scripts/lib/system.sh` via `REPO_ROOT` and uses `_kubectl` wrapper for all kubectl calls (`b0b76b3`).
- **`README.md`**: Plugins section — full table of all 14 plugins with key functions and descriptions.
- **`README.md`**: How-To section — grouped by component (Jenkins / LDAP).
- **`README.md`**: Issue Logs promoted to top-level section with 5 most recent entries.
- **`README.md`**: Releases table — top 3 in main table; older in `<details>` collapsible block.
- **`docs/releases.md`**: Backfilled v0.9.2–v0.9.6 entries (were missing).
- **`CLAUDE.md`**: Added agent commit + memory-bank discipline rules.

### Added
- **`scripts/tests/lib/system.bats`**: Restored from lib-foundation — 8 BATS tests for `_run_command_resolve_sudo` + `_run_command` (`cc49b66`).
- **`scripts/etc/agent/bare-sudo-allowlist`**: Allowlist file for `_agent_audit` — permits `system.sh` to use sudo internally (`c216d45`).
- **`docs/issues/2026-03-22-missing-system-bats.md`**: Tracks missing `system.bats` (now restored).
- **`docs/issues/2026-03-21-frontend-readonly-filesystem-failure.md`**: Frontend nginx CrashLoopBackOff — read-only root filesystem prevents config write.
- **`docs/retro/2026-03-22-v0.9.6-retrospective.md`**: v0.9.6 retrospective + post-merge v0.9.7 session start.

---

## [Unreleased] v0.9.6 — ACG plugin + kops-for-k3s reframe

### Added
- **`acg_provision`** (`scripts/plugins/acg.sh`): Provisions ACG AWS sandbox EC2 instance — VPC, subnet, IGW, SG, key pair, t3.medium launch, SSH config update. Requires `--confirm`. Replaces `bin/acg-sandbox.sh`.
- **`acg_status`** (`scripts/plugins/acg.sh`): Reports instance state, public IP, and k3s health. Check-only, no side effects.
- **`acg_extend`** (`scripts/plugins/acg.sh`): Opens ACG sandbox URL to extend TTL (+4h). macOS: opens browser. Linux: prints URL.
- **`acg_teardown`** (`scripts/plugins/acg.sh`): Terminates EC2 instance and removes `ubuntu-k3s` kubeconfig context. Requires `--confirm`.
- **`scripts/tests/plugins/acg.bats`**: 12-case BATS suite covering all four functions with AWS/kubectl/ssh stubs.

### Removed
- **`bin/acg-sandbox.sh`**: Retired — all functionality migrated to `scripts/plugins/acg.sh`.

### Changed
- **`scripts/lib/help/utils.sh`**: Added `ACG sandbox` category (`acg_*`) to the help system.
- **`docs/plans/roadmap-v1.md`**: Reframed vision as kops-for-k3s — dropped EKS/GKE/AKS scope; revised v1.x milestones to focus on k3s multi-node, full-stack provisioning, k3dm-mcp, and home lab.

### Fixed (Copilot review — commit `7987453`)
- **`_acg_check_credentials`**: replaced `_err` (calls `exit 1`) with `printf >&2; return 1` — callers using `|| return 1` now work correctly.
- **`_acg_get_instance_id` / `_acg_get_instance_attr`**: added `--soft` to `_run_command` so `|| true` fallback is reachable.
- **`_acg_update_ssh_config`**: replaced `read -r -d ''` heredoc (returns non-zero at EOF) with `$(cat <<PY)`. Fixed `\\1${ip}` backreference to `\\g<1>${ip}` to prevent group-11 ambiguity.
- **`_acg_check_k3s`**: added `--soft` so ssh failure is handled as a warning (else branch no longer unreachable).
- **VPC/SG idempotency**: added `_acg_find_vpc()` and `_acg_find_sg()` — provision stack reuses existing VPC and SG by tag instead of always creating new ones.
- **Security**: added `ACG_ALLOWED_CIDR` env var (default `0.0.0.0/0` with warning). Set to `<your-ip>/32` to restrict SSH/6443 ingress.
- **`scripts/tests/plugins/acg.bats`**: added `source test_helpers.bash` to align with `tunnel.bats` pattern.

### Documentation
- **`README.md`**: added ACG sandbox Quick Start section; renumbered steps; added ACG Plugin link under API Reference.
- **`docs/api/functions.md`**: added `tunnel_start/stop/status`, `deploy_app_cluster`, and all four ACG functions to the Plugins table.

---

## [Unreleased] v0.9.5 — deploy_app_cluster via k3sup

### Added
- **`deploy_app_cluster`** (`scripts/plugins/shopping_cart.sh`): Automates single-node EC2 k3s lifecycle via k3sup. Installs k3s on a remote host over SSH, waits for node Ready, and merges the kubeconfig into `~/.kube/config` as the `ubuntu-k3s` context. Prints ArgoCD registration next steps. Replaces manual Gemini rebuild session. Requires `--confirm` to prevent accidental runs; configurable via `UBUNTU_K3S_*` env vars.
- **`scripts/tests/plugins/shopping_cart.bats`**: BATS test suite covering help flag, missing --confirm guard, k3sup not-found error, and argocd dir prerequisite check.

### Changed
- **`bin/acg-sandbox.sh`**: Updated k3s-not-responding warning to direct operators to `./scripts/k3d-manager deploy_app_cluster --confirm` instead of a stale Gemini rebuild spec reference.

### Process
- Sprint story rule (max 5 plan docs per release) added to CLAUDE.md, AGENTS.md, GEMINI.md.
- v0.9.4 retrospective documented at `docs/retro/2026-03-21-v0.9.4-retrospective.md`.
- v0.9.6 scope updated: frontend LoadBalancer deferred to v1.0.0 (needs multi-node).

---

## v0.9.0 — k3dm-mcp Planning + Agent Workflow Lessons — dated 2026-03-14

### Added
- **k3dm-mcp planning**: Architecture decision recorded — log aggregation via MCP; separate repo at `wilddog64/k3dm-mcp` identified as next milestone.
- **vcluster as v1.1.0 provider**: `docs/plans/roadmap-v1.md` updated after Loft Labs platform advocate contact.

### Documentation
- **Agent workflow lessons** added to `memory-bank/activeContext.md`:
  - Codex fabricates commit SHAs when reporting completion — always verify with `gh api`.
  - Codex reports "done" after writing docs without implementing code — require a PR URL as proof.
  - Codex silently reverts intentional decisions across session restarts — three-layer defense: Agent Instructions in `CLAUDE.md` + inline `DO NOT REMOVE` comments + memory-bank sections.

### Validation
- BATS: no regressions on existing test suites.
- shellcheck: clean on all `.sh` files touched.

---

## v0.8.0 — Vault ArgoCD Deploy Keys + cert-manager ACME + Istio IngressClass — dated 2026-03-13

### Added
- **`configure_vault_argocd_repos`** (`scripts/plugins/argocd.sh`): Vault-managed SSH deploy keys for shopping-cart repos. Creates `argocd-deploy-key-reader` Vault policy, dedicated ESO SecretStore + ServiceAccount, and one ExternalSecret per repo syncing from `secret/argocd/deploy-keys/<repo>` into ArgoCD repository secrets. Supports `--seed-vault` and `--dry-run`.
- **`deploy_cert_manager`** (`scripts/plugins/cert-manager.sh`): cert-manager v1.20.0 via Helm with ACME HTTP-01 challenge support through Istio ingress. Deploys staging ClusterIssuer by default; `--production` for internet-accessible clusters; `--skip-issuer` for Helm-only install. Validates `ACME_EMAIL`, waits for webhook readiness, checks Istio IngressClass before applying issuers.
- **`istio` IngressClass** (`scripts/etc/istio-ingressclass.yaml`): Applied automatically by `_provider_k3d_configure_istio` after `istioctl install`. Required for cert-manager HTTP-01 challenge routing.
- **`scripts/hooks/install-hooks.sh`**: Installs all tracked git hooks as symlinks into `.git/hooks/`. Run once per clone to keep hooks in sync with the repo.
- **New docs**: `docs/api/functions.md`, `docs/api/vault-pki.md`, `docs/guides/jenkins-authentication.md`, `docs/guides/plugin-development.md`, `docs/providers/k3s.md`, `docs/providers/orbstack.md`. README restructured to two-cluster quick start.

### Fixed
- **`deploy_argocd` if-count**: Extracted `_argocd_helm_deploy_release`, `_argocd_configure_vault_eso`, `_argocd_configure_post_deploy` to bring function under `AGENT_AUDIT_MAX_IF=8` threshold.
- **`configure_vault_argocd_repos` if-count**: Extracted `_argocd_validate_deploy_key_prereqs`, `_argocd_setup_deploy_key_resources`, `_argocd_apply_repo_deploy_keys`.
- **`cert-manager.sh` vars path**: Plugin now sources `$SCRIPT_DIR/etc/cert-manager/vars.sh` (was incorrectly `$PLUGINS_DIR`).

### Validation
- BATS: `argocd_deploy_keys.bats` 8/8; `cert_manager.bats` 10/10; `istio_ingressclass.bats` 4/4 — all `env -i` clean.
- `deploy_cert_manager` live cluster verify: PASS on M2 Air infra cluster (k3d/OrbStack). cert-manager pods Running, webhook Available, staging ClusterIssuer created.
- shellcheck: clean on all modified `.sh` files.
- All functions ≤ 8 if-blocks (`AGENT_AUDIT_MAX_IF=8` audit passing).

---

## v0.7.3 — Shopping Cart CI/CD + Two-Cluster GitOps — dated 2026-03-10

### Added
- **Reusable GitHub Actions workflow** (`shopping-cart-infra`): Build + Trivy scan + push to `ghcr.io` + kustomize image update. Used by all 5 shopping cart service repos.
- **Caller workflows** in all 5 service repos: `basket-service`, `order-service`, `payment-service`, `product-catalog-service`, `frontend-service`.
- **`shopping_cart.sh` plugin** (`scripts/plugins/shopping_cart.sh`): Two new public functions:
  - `add_ubuntu_k3s_cluster` — auto-exports Ubuntu k3s kubeconfig via SSH, rewrites server IP, verifies connectivity, registers cluster in ArgoCD
  - `register_shopping_cart_apps` — applies ArgoCD Application CRs from `shopping-cart-infra`
- **Ubuntu k3s SSH vars** (`scripts/etc/k3s/vars.sh`): `UBUNTU_K3S_SSH_HOST`, `UBUNTU_K3S_SSH_USER`, `UBUNTU_K3S_EXTERNAL_IP`, `UBUNTU_K3S_REMOTE_KUBECONFIG`, `UBUNTU_K3S_LOCAL_KUBECONFIG` — all overridable via env.
- **Pre-commit hook** (`scripts/hooks/pre-commit`): Tracked in repo, wires `_agent_lint` + `_agent_audit` to run on every commit.
- **`.envrc` dotfiles symlink**: Replaced static `.envrc` with symlink to dotfiles repo.

### Fixed
- **ArgoCD Application CR `repoURLs` + `destination.server`**: Updated to use SSH URLs and correct Ubuntu k3s API (`10.211.55.14:6443`).
- **`add_ubuntu_k3s_cluster`**: Rewrote from stub (fail-if-missing) to full SSH export + IP rewrite + ArgoCD registration.
- **BATS teardown**: `teardown_file()` added to `provider_contract.bats` — cleans up `k3d-test-orbstack-exists` cluster after test run.
- **Trivy restore + repin**: All 5 service repos repinned after transient GitHub rate-limit failure.

### Validation
- Infra cluster rebuilt on M2 Air: Vault, ESO, Istio, Jenkins, ArgoCD, OpenLDAP, Keycloak — all healthy.
- Ubuntu k3s app cluster: ESO 2/2 SecretStores Ready, shopping-cart-data Running.
- ArgoCD→Ubuntu cluster registration: `ubuntu-k3s` Ready at `https://10.211.55.14:6443`.
- Shopping cart apps: 5/5 registered + synced. `ImagePullBackOff` expected until CI pushes images.
- BATS: 158/158 passing (M2 Air, Bash 5.0+).

### Known Issues
- Shopping cart pods in `ImagePullBackOff` — images not yet pushed by CI. Unblocked once service repo CI workflows complete a successful run.
- ArgoCD deploy keys: per-repo passphrase-free SSH keys. Vault-managed rotation planned for v0.8.0.

---

## v0.7.0 — lib-foundation Subtree + deploy_cluster Hardening — dated 2026-03-07

### Added
- **lib-foundation git subtree** (`scripts/lib/foundation/`): Pulls `lib-foundation` main into the repo via `git subtree add --squash`. Dispatcher sources subtree copies of `core.sh` and `system.sh` first, falling back to local copies during transition.
- **`_deploy_cluster_prompt_provider`** (`scripts/lib/core.sh`): Extracted helper — prompts user to select a cluster provider interactively.
- **`_deploy_cluster_resolve_provider`** (`scripts/lib/core.sh`): Extracted helper — resolves provider from env var, positional arg, or interactive prompt.

### Fixed
- **`deploy_cluster` if-count violation** (`scripts/lib/core.sh`): Refactored from 12 to 5 `if` blocks after extracting provider helpers. Issue: `docs/issues/2026-03-07-deploy-cluster-if-count-violation.md`.
- **`CLUSTER_NAME` env var ignored** (`scripts/lib/core.sh`): When no positional cluster name is supplied, `deploy_cluster` now reads `$CLUSTER_NAME` from the environment and exports it before calling the provider. Verified via `_cluster_provider_call` stub test.
- **ESO SecretStore `identity/vault-kv-store` unauthorized** (`scripts/plugins/vault.sh`): `_vault_configure_secret_reader_role` now binds `eso-ldap-directory` to both `directory` and `identity` namespaces. Previously only `directory` was bound, causing `InvalidProviderConfig` within minutes of deploy. Issue: `docs/issues/2026-03-07-eso-secretstore-identity-namespace-unauthorized.md`.
- **`pushd`/`popd` unguarded in `_install_istioctl`** (`scripts/lib/core.sh`): Added `|| return` guards to both calls.

### Validation
- OrbStack macOS ARM64: 158/158 BATS, all services Running (Vault, ESO, Istio, OpenLDAP, Jenkins, ArgoCD, Keycloak).
- Ubuntu k3s Linux: 158/158 BATS, all services Ready.

### Known Issues (deferred to v0.7.x backlog)
- BATS test teardown: `k3d-test-orbstack-exists` cluster not cleaned up post-test, can block port 8000/8443 on next `deploy_cluster`. Issue: `docs/issues/2026-03-07-k3d-rebuild-port-conflict-test-cluster.md`.
- colima VM inotify limit not persistent across restarts. Manual fix: `colima ssh -- sudo sysctl -w fs.inotify.max_user_instances=512`.
- ESO + shopping-cart deployment on Ubuntu app cluster deferred to next milestone.

---

## v0.6.5 — Agent Rigor Coverage + lib-foundation Extraction — dated 2026-03-07

### Fixed
- **`_agent_audit` awk portability** (`scripts/lib/agent_rigor.sh`): The if-count-per-function check used a multi-parameter awk user-defined function rejected by macOS BSD awk (20200816), causing a noisy syntax error on every commit. Replaced with a pure bash `while IFS= read -r line` loop — bash 3.0+ compatible, no external tool dependency, identical logic. Issue: `docs/issues/2026-03-07-agent-audit-awk-macos-compat.md`.
- **SC2155 splits in `system.sh`**: `local var=$(...)` declarations in `_add_exit_trap` and `_detect_cluster_name` split into two-line form for shellcheck compliance.

### Added
- **BATS coverage for `_agent_audit` new checks** (`scripts/tests/lib/agent_rigor.bats`): 4 new tests for the v0.6.4 bare sudo and kubectl exec credential detections. Each test uses a real mini git repo — no git stubs. Suite: 9/9. Full BATS: 158/158.
  - `_agent_audit: flags bare sudo in unstaged diff`
  - `_agent_audit: ignores _run_command sudo in diff`
  - `_agent_audit: flags kubectl exec with credential env var in staged diff`
  - `_agent_audit: passes clean staged diff`

### Infrastructure
- **`lib-foundation` repository created**: https://github.com/wilddog64/lib-foundation — shared Bash foundation library. Branch protection, required CI (shellcheck + BATS 1.13.0), linear history enforced.
- **`core.sh` + `system.sh` extracted**: Copied to `lib-foundation` branch `extract/v0.1.0`. All shellcheck warnings resolved. PR #1 open on lib-foundation, CI green.

### Verification
- BATS suite: 158/158 passing (clean `env -i` environment, Ubuntu 24.04 VM).
- shellcheck: PASS on all touched `.sh` files.
- Pre-commit hook: no awk error on macOS M-series.

---

## v0.6.4 — Linux k3s Validation + Agent Harness Hardening — dated 2026-03-07

### Validation
- **Linux k3s gate**: Full 5-phase teardown/rebuild verified on Ubuntu 24.04 VM (`CLUSTER_PROVIDER=k3s`). `_detect_platform` correctly returns `debian`. Kubeconfig owner correct after copy. systemd path taken by `_start_k3s_service`. Vault, ESO, Istio, OpenLDAP, Jenkins, ArgoCD, Keycloak all deployed and healthy.
- **BATS suite**: 154/154 passing (30 new contract tests added).

### Fixed
- **BATS source install 404** (`scripts/lib/system.sh`): `_install_bats_from_source` and `_ensure_bats` defaulted to `1.10.0` — a non-existent GitHub release tag. Updated to `1.11.0`. GitHub archive URL (`archive/refs/tags/`) used for stability over `releases/download/`.
- **`_provider_orbstack_expose_ingress` missing** (`scripts/lib/providers/orbstack.sh`): Contract tests revealed `orbstack.sh` was missing the `expose_ingress` interface function. Added delegate following the established pattern.

### Added
- **`_agent_audit` hardening** (`scripts/lib/agent_rigor.sh`): Two new mechanical checks:
  - Bare sudo detection — flags direct `sudo` calls bypassing `_run_command --prefer-sudo`
  - Credential pattern scan — flags secrets passed inline to `kubectl exec` args
- **Pre-commit hook** (`.git/hooks/pre-commit`): Wires `_agent_audit` to run automatically on every commit. Violations block the commit with a structured error.
- **Provider contract BATS suite** (`scripts/tests/lib/provider_contract.bats`): 30 tests enforcing that every cluster provider (`k3d`, `k3s`, `orbstack`) implements the full 10-function interface. Fails immediately if a required function is missing.

### Docs / Tooling
- **CLAUDE.md**: Trimmed 439 → 104 lines — navigation layer only, stale content removed.
- **AGENTS.md**: Deleted — task spec pattern via memory-bank replaced its purpose.
- **`docs/plans/task-spec-template.md`**: Mandatory change checklist format for all agent task specs — prevents scope creep.
- **Roadmap updated** (`docs/plans/roadmap-v1.md`): Architectural boundary (plugin layer is k8s-agnostic), v0.8.0/v0.8.1 observability (OTel + optional Jaeger), agent safety guards, One AI Layer Rule (`K3DM_ENABLE_AI=0` in MCP subprocess), env isolation design constraints.
- **Branch protection**: `required_linear_history=true` — force-push and rebase-push blocked at remote.

---

## v0.6.3 — Refactoring & Digital Auditor — dated 2026-03-06

### Refactoring
- **Permission cascade elimination**: Collapsed 7 multi-attempt sudo escalation patterns across `core.sh` into single `_run_command --prefer-sudo` calls (`_ensure_path_exists`, `_k3s_stage_file`, `_install_k3s`, `_start_k3s_service`, `_install_docker`, `_create_nfs_share`, `deploy_cluster`).
- **`_detect_platform` helper**: New single source of truth for OS detection in `system.sh` — returns `mac`, `wsl`, `debian`, `redhat`, or `linux`. Replaces scattered inline `_is_mac`/`_is_debian_family` dispatch chains in `core.sh`.
- **`_create_nfs_share_mac` extracted**: Relocated from `core.sh` to `system.sh` with quoting fixes (`"$HOME/k3d-nfs"`). `core.sh` now delegates via a guarded wrapper.
- **`_run_command` TTY flakiness fixed**: Removed `auto_interactive` block — `[[ -t 0 ]]` TTY detection caused CI vs local behaviour divergence. Privilege escalation now determined solely by flags (`--prefer-sudo`, `--require-sudo`).

### Added
- **`_agent_lint`** (`scripts/lib/agent_rigor.sh`): Copilot-backed architectural linter. Gated on `K3DM_ENABLE_AI=1`. Reads rules from `scripts/etc/agent/lint-rules.md` and reviews staged `.sh` files for violations before commit.
- **`_agent_audit`** (`scripts/lib/agent_rigor.sh`): Pure-bash post-implementation rigor check. Detects test weakening (removed assertions, decreased `@test` count), excessive `if`-density per function, and runs `shellcheck` on changed files.
- **Agent lint rules** (`scripts/etc/agent/lint-rules.md`): 5 architectural rules enforced by `_agent_lint` — no permission cascades, centralised platform detection, secret hygiene, namespace isolation, prompt scope.
- **BATS suite** (`scripts/tests/lib/agent_rigor.bats`): Tests for `_agent_checkpoint`, `_agent_lint`, and `_agent_audit`.

### Verification
- BATS suite: 124/124 passing (1 test removed — sudo-retry behaviour intentionally eliminated by permission cascade de-bloat).
- Full infra cluster teardown/rebuild verified on OrbStack (macOS ARM64): Vault, ESO, Istio, OpenLDAP, Jenkins, ArgoCD, Keycloak all healthy.
- Individual smoke tests passed: `test_vault`, `test_eso`, `test_istio`.

---

## v0.6.2 — Copilot CLI & Agent Rigor — dated 2026-03-06

### Added
- **Agent Rigor Protocol**: `_agent_checkpoint` in `scripts/lib/agent_rigor.sh` — spec-first git checkpointing with dependency guard; requires `system.sh` sourced first.
- **Copilot CLI Management**: Scoped `_k3d_manager_copilot` wrapper with `K3DM_ENABLE_AI` gate, deny-tool guardrails (8 forbidden shell fragments), PATH sanitization, and CDPATH/OLDPWD isolation. Auto-install via `_ensure_copilot_cli` (brew → curl fallback).
- **Node.js Management**: `_ensure_node` / `_install_node_from_release` — auto-install helpers following `_ensure_bats` pattern (brew → apt-get/apt → dnf/yum/microdnf → release tarball); all package manager paths gated on `_sudo_available`.
- **PATH Hardening**: `_safe_path` and `_is_world_writable_dir` guard against PATH poisoning — rejects world-writable directories (sticky-bit exemption removed) and relative/empty path entries. Uses glob-safe `IFS=':' read -r -a` array split.
- **BATS Suites**: `ensure_node.bats`, `ensure_copilot_cli.bats`, `k3d_manager_copilot.bats`, `safe_path.bats` — 120/120 passing.

### Security
- **VAULT_TOKEN stdin injection**: `ldap-password-rotator.sh` — token and kv payload piped via stdin into the pod's bash session; extracted with a `while IFS="=" read -r key value` loop inside `bash -c`. Token never appears in `kubectl exec` argument list or `/proc/*/cmdline`.
- **Sticky-bit exemption removed**: `_is_world_writable_dir` no longer exempts `1777` dirs — sticky bit prevents deletion but not creation of malicious binaries, so world-writable remains world-writable for PATH safety.
- **Prompt guard hardened**: `_copilot_prompt_guard` checks 8 forbidden fragments: `shell(cd`, `shell(git push --force)`, `shell(git push)`, `shell(rm`, `shell(eval`, `shell(sudo`, `shell(curl`, `shell(wget`.
- **Exit code fix**: `_k3d_manager_copilot` uses `|| rc=$?` pattern so copilot failure exit codes are correctly propagated.

---

## v0.6.1 - dated 2026-03-02

### Bug Fixes

- **k3d/OrbStack:** `destroy_cluster` now defaults to `k3d-cluster` if no name is provided, matching the behavior of `deploy_cluster`.
- **LDAP:** `deploy_ldap` now correctly proceeds with default settings when called without arguments, instead of displaying help.
- **ArgoCD:** Fixed a deployment hang by disabling Istio sidecar injection for the `redis-secret-init` Job via Helm annotations.
- **Jenkins:** 
  - Fixed a hardcoded namespace bug where `deploy_jenkins` was only looking for the `jenkins-ldap-config` secret in the `jenkins` namespace instead of the active deployment namespace (e.g., `cicd`).
  - Disabled Istio sidecar injection for the `jenkins-cert-rotator` CronJob pods to prevent them from hanging in a "NotReady" state after completion.

### Verification

- End-to-end infra cluster rebuild verified on OrbStack (macOS ARM64).
- All components (Vault, ESO, OpenLDAP, Jenkins, ArgoCD, Keycloak) confirmed healthy in new namespace structure (`secrets`, `identity`, `cicd`).
- Full test suite passed: `test_vault`, `test_eso`, `test_istio`, `test_keycloak`.
- Cross-cluster Vault auth verified via `configure_vault_app_auth` with real Ubuntu k3s CA certificate.

---

## v0.6.0 - dated 2026-03-01

### App Cluster Vault Auth

- `configure_vault_app_auth` — new top-level command that registers the Ubuntu k3s app
  cluster as a second Kubernetes auth mount (`auth/kubernetes-app/`) in Vault, then
  creates an `eso-app-cluster` role so ESO on the app cluster can authenticate and fetch
  secrets
- Uses default local JWT validation — Vault verifies ESO's JWT against the provided app
  cluster CA cert without calling the Ubuntu k3s TokenReview API (avoids OrbStack
  networking uncertainty; no `token_reviewer_jwt` needed)
- Required env vars: `APP_CLUSTER_API_URL`, `APP_CLUSTER_CA_CERT_PATH`
- Optional env vars with defaults: `APP_K8S_AUTH_MOUNT` (`kubernetes-app`),
  `APP_ESO_VAULT_ROLE` (`eso-app-cluster`), `APP_ESO_SA_NAME` (`external-secrets`),
  `APP_ESO_SA_NS` (`secrets`)
- Idempotent: safe to re-run; existing mount and policy are detected and skipped

### Bug Fixes

- `configure_vault_app_auth` step (d) — replaced `_vault_set_eso_reader` call with an
  inline `_vault_policy_exists` check + policy write; prevents `_vault_set_eso_reader`
  from reconfiguring the infra cluster's `auth/kubernetes` mount and overwriting
  `auth/kubernetes/role/eso-reader` with app cluster SA values

### Tests

- `scripts/tests/plugins/vault_app_auth.bats` — 5 cases:
  - exits 1 when `APP_CLUSTER_API_URL` is unset
  - exits 1 when `APP_CLUSTER_CA_CERT_PATH` is unset
  - exits 1 when CA cert file is missing
  - calls vault commands with correct args including `disable_local_ca_jwt=true`
  - idempotent: second run exits 0

### Verification

- `shellcheck scripts/plugins/vault.sh` clean
- `bats scripts/tests/plugins/vault_app_auth.bats` 5/5 passed (Gemini 2026-03-01)
- `test_vault` passed against live infra cluster (Gemini 2026-03-01)

---

## v0.5.0 - dated 2026-03-03

### Keycloak Plugin — Infra Cluster Complete

- `deploy_keycloak [--enable-ldap] [--enable-vault] [--skip-istio]` — deploys Bitnami
  Keycloak chart to the `identity` namespace with full ESO/Vault and LDAP federation
  support
- `_keycloak_seed_vault_admin_secret` — generates a random 24-char admin password and
  seeds it at `${KEYCLOAK_VAULT_KV_MOUNT}/${KEYCLOAK_ADMIN_VAULT_PATH}` in Vault on
  first deploy; skips if secret already exists
- `_keycloak_setup_vault_policies` — writes Vault policy and Kubernetes auth role for
  the ESO service account; idempotent
- `_keycloak_apply_realm_configmap` — renders `realm-config.json.tmpl` via `envsubst`
  (LDAP bind credential injected from K8s secret), applies as ConfigMap
  `keycloak-realm-config` consumed by `keycloakConfigCli`

### New Templates (`scripts/etc/keycloak/`)

| File | Purpose |
|---|---|
| `vars.sh` | All Keycloak config variables with sane defaults |
| `values.yaml.tmpl` | Bitnami Helm values — ClusterIP, `keycloakConfigCli` enabled |
| `secretstore.yaml.tmpl` | ESO SecretStore + ServiceAccount backed by Vault Kubernetes auth |
| `externalsecret-admin.yaml.tmpl` | Admin password synced from Vault |
| `externalsecret-ldap.yaml.tmpl` | LDAP bind password synced from existing `ldap/openldap-admin` path |
| `realm-config.json.tmpl` | Keycloak 17+ `components` format realm JSON with OpenLDAP federation |
| `virtualservice.yaml.tmpl` | Istio VirtualService — namespace and gateway fully parameterised |

### Bug Fixes

- `realm-config.json.tmpl` — uses modern Keycloak 17+ `components` format (not
  deprecated `userFederationProviders`)
- `values.yaml.tmpl` — `keycloakConfigCli.podAnnotations` sets
  `sidecar.istio.io/inject: "false"` to prevent Istio sidecar blocking Job completion
  (same root cause as ArgoCD `redis-secret-init` — see
  `docs/issues/2026-03-01-istio-sidecar-blocks-helm-pre-install-jobs.md`)
- `_keycloak_apply_realm_configmap` — LDAP credentials read from K8s secret at deploy
  time and passed via `envsubst` environment, not hardcoded
- `envsubst` whitelist includes `$KEYCLOAK_LDAP_USERS_DN` so `usersDn` in the realm
  JSON is correctly substituted

### Tests

- `scripts/tests/plugins/keycloak.bats` — 6 cases:
  - `deploy_keycloak --help` exits 0 with usage text
  - `deploy_keycloak` skips when `CLUSTER_ROLE=app`
  - `KEYCLOAK_NAMESPACE` defaults to `identity`
  - `KEYCLOAK_HELM_RELEASE` defaults to `keycloak`
  - `deploy_keycloak` rejects unknown option with exit 1
  - `_keycloak_seed_vault_admin_secret` is defined as a function

### Verification

- `shellcheck scripts/plugins/keycloak.sh` clean
- `bats scripts/tests/plugins/keycloak.bats` 6/6 passed (verified by Gemini 2026-03-03)

---

## v0.4.0 - dated 2026-03-02

### ArgoCD Phase 1 — Core Deployment

- `deploy_argocd [--enable-ldap] [--enable-vault] [--bootstrap]` now fully wired for
  the `cicd` namespace (v0.3.0 default)
- `deploy_argocd_bootstrap [--skip-applicationsets] [--skip-appproject]` applies
  AppProject and ApplicationSet resources to the running ArgoCD instance

### Bug Fixes

- `scripts/etc/argocd/projects/platform.yaml` → `platform.yaml.tmpl`
  - Converted live cluster dump to clean declarative template
  - Namespace field parameterised as `${ARGOCD_NAMESPACE}` (rendered via `envsubst`)
  - Destinations updated to v0.3.0 names: `secrets`, `cicd`, `identity`
  - Stale Kubernetes server metadata (`uid`, `resourceVersion`, `creationTimestamp`) removed
- `scripts/etc/argocd/applicationsets/{platform-helm,services-git,demo-rollout}.yaml`
  - Same metadata cleanup applied to all three files
  - `namespace: argocd` → `cicd` in metadata and template destinations
  - GitHub org placeholder `your-org` → `wilddog64`
- `_argocd_deploy_appproject` — renders `platform.yaml.tmpl` via
  `envsubst '$ARGOCD_NAMESPACE'` before `kubectl apply`
- `_argocd_seed_vault_admin_secret` — new helper; seeds a random 24-char password at
  `${ARGOCD_VAULT_KV_MOUNT}/${ARGOCD_ADMIN_VAULT_PATH}` in Vault on first deploy so
  the ESO ExternalSecret can sync it immediately

### Tests

- `scripts/tests/plugins/argocd.bats` — new suite, 6 cases:
  - `deploy_argocd --help` exits 0 with usage text
  - `deploy_argocd` skips when `CLUSTER_ROLE=app`
  - `deploy_argocd_bootstrap --help` exits 0
  - `deploy_argocd_bootstrap --skip-applicationsets --skip-appproject` no-ops cleanly
  - `_argocd_deploy_appproject` fails with clear error when template is missing
  - `ARGOCD_NAMESPACE` defaults to `cicd`

### Verification

- `shellcheck scripts/plugins/argocd.sh` clean
- `bats scripts/tests/plugins/argocd.bats` 6/6 passed (verified by Gemini 2026-03-02)

---

## v0.3.1 - dated 2026-03-01

### Bug Fixes

- `deploy_jenkins --namespace cicd` no longer fails with namespace mismatch error
  - `scripts/etc/jenkins/jenkins-home-pv.yaml.tmpl`: `namespace: $JENKINS_NAMESPACE` (was hardcoded `jenkins`)
  - `_create_jenkins_pv_pvc`: exports `JENKINS_NAMESPACE` before calling `envsubst` so template substitution takes effect
  - `deploy_jenkins` line 1281: falls back to `${JENKINS_NAMESPACE:-jenkins}` so env var override works without `--namespace` flag

### Verification

- `shellcheck scripts/plugins/jenkins.sh` clean
- `bats scripts/tests/lib/test_auth_cleanup.bats` 1/1 passed

---

## v0.3.0 - dated 2026-03-02

### Two-Cluster Architecture

- Added `CLUSTER_ROLE=infra|app` dispatcher gating — `app` mode skips Vault/Jenkins/LDAP/ArgoCD
- Cross-cluster SecretStore: `_eso_configure_remote_vault()` in `scripts/plugins/eso.sh`
- New env vars: `REMOTE_VAULT_ADDR`, `REMOTE_VAULT_K8S_MOUNT`, `REMOTE_VAULT_K8S_ROLE`
- `VAULT_ENDPOINT` now dynamic: `http://vault.${VAULT_NS}.svc:8200`

### Namespace Renames (new defaults, env var overrides preserved)

| Old | New | Override var |
|-----|-----|--------------|
| `vault` + `external-secrets` | `secrets` | `VAULT_NS`, `ESO_NAMESPACE` |
| `jenkins` | `cicd` | `JENKINS_NAMESPACE` |
| `directory` | `identity` | `LDAP_NAMESPACE` |
| `argocd` | `cicd` | `ARGOCD_NAMESPACE` |

### Bug Fixes

- `deploy_vault` now respects `VAULT_NS` env var (`ns` initialises from `${VAULT_NS:-$VAULT_NS_DEFAULT}`)
- `_cleanup_cert_rotation_test` EXIT trap fixed — no longer references out-of-scope local `jenkins_ns`; uses `${JENKINS_NAMESPACE:-cicd}` directly
- `deploy_eso` remote SecretStore now passes `$ns` to `_eso_configure_remote_vault` instead of `${ESO_NAMESPACE:-secrets}`
- All hardcoded `-n jenkins` / `-n vault` namespace strings replaced with env var refs in `test.sh`, `check_cluster_health.sh`, `run-cert-rotation-test.sh`, `openldap.sh`
- `ARGOCD_LDAP_HOST` and `JENKINS_LDAP_HOST` updated to `identity` namespace

### Tests

- `test_auth_cleanup.bats` regression fixed — sub-calls restored to main baseline (only first call pins `VAULT_NS=vault`)
- ESO plugin bats suite: 4/4 passing
- shellcheck clean across all modified scripts

---

## v0.2.0 - dated 2026-02-27

### OrbStack Provider
- Added `scripts/lib/providers/orbstack.sh` — k3d lifecycle operations via OrbStack's Docker runtime
- Auto-detection on macOS: prefers OrbStack when `orb` daemon is running, falls back to k3d
- Validated on M4 and M2 Macs — full stack (cluster, Vault, Jenkins, Istio, smoke tests) green
- Stage 2 CI now runs on OrbStack (m2-air self-hosted runner)

### Vault
- `deploy_vault` now ensures `system:auth-delegator` ClusterRoleBinding exists (idempotent)
- `test_vault` reverted to hard-fail on pod auth failure — workaround removed

### Jenkins
- Fixed Kubernetes agents: ServiceAccount mismatch, envsubst placeholders, crumb issuer, port alignment (8080)
- SMB CSI Phase 1: `deploy_smb_csi` no-ops with warning on macOS (cifs module unavailable)

### Housekeeping
- Renamed `LDAP_PASSWORD_ROTATOR_IMAGE` → `LDAP_ROTATOR_IMAGE` (GitGuardian false positive fix)
- Stage 2 CI (`test_vault`, `test_eso`, `test_istio`) green on m2-air

---

## OrbStack Provider Support - dated 2026-02-24

- Added `scripts/lib/providers/orbstack.sh` to run all k3d lifecycle operations against OrbStack's Docker runtime without touching Colima/Docker Desktop installers.
- Cluster provider auto-detection now prefers OrbStack on macOS when the `orb` daemon is running, falling back to the previous `k3d` default otherwise.
- Documentation (`README.md`, `CLAUDE.md`, `.clinerules`, memory bank) updated to list `orbstack` as a supported `CLUSTER_PROVIDER` value and describe the new behavior.
- Plan `docs/plans/orbstack-provider.md` reflects Phase 1 + 2 completion; Phase 3 (native OrbStack Kubernetes) remains pending.


## Active Directory Integration - dated 2025-11-10

bda2bf3 k3d-manager::tests::jenkins: add Active Directory integration tests
b25f0a8 k3d-manager::plugins::jenkins: add production AD support with connectivity validation
32676f3 k3d-manager::jenkins: improve deployment reliability and observability
517edd7 k3d-manager::plugins::jenkins: add --enable-ad flag for AD schema testing
182d972 k3d-manager: add Jenkins authentication mode templates
ef1ef14 k3d-manager: improve deployment command consistency and AD DN configuration

### Features Added
- **Active Directory Testing Mode** (`--enable-ad`): Deploy OpenLDAP with AD schema for local testing
- **Production AD Integration** (`--enable-ad-prod`): Connect to production Active Directory servers
- **Pre-flight Validation**: Automatic DNS and LDAPS connectivity checks before deployment
- **Validation Bypass**: `--skip-ad-validation` flag for testing environments
- **Template-based Authentication**: Three distinct modes (default, AD testing, production AD)
- **Comprehensive Testing**: 8 new bats tests covering flag validation and mutual exclusivity

### Documentation
- Added Jenkins Authentication Modes section to README.md
- Updated CLAUDE.md with AD integration configuration details
- Documented all three authentication modes with usage examples

## Previous Releases - dated 2024-06-26

d509293 k3d-manager: release notes
598c4e6 test: cover Jenkins VirtualService headers
b89c02c docs: note Jenkins reverse proxy headers
f5ec68d k3d-manager::plugins::jenkins: setup reverse proxy
38d6d43 k3d-manager::plugins::jenkins: setup SAN -- subject alternative name
926d543 k3d-manager: change HTTPS_PORT dfault from 9443 to 8443
33f66f0 k3d-manager::plugins::vault: give a warning instead of bail out
482dcbe k3d-manager::plugins::vault: refactor _vault_post_revoke_request
64754f5 k3d-manager::plugins::vault: refactor _vault_exec to allow passing --no-exit, --perfer-sudo, and --require-sudo
7ae2a37 k3d-manager::plugins::vault: remove vault login from _vault_exec
8a37d38 k3d-manager::plugins::vault: add a _mount_vault_immediate_sc
499ff86 k3d-manager::plugins::vault: fix incorrect casing for wait condition
f350d11 Document test log layout
e3d0220 Refine test log handling
1bc3751 Document test case options
b510f3e Extend test runner CLI
a961192 k3d-manager: update k3s setup
43b1a93 Require sudo for manual k3s start
34a154a Test manual k3s start path
943bc83 Support k3s without systemd
5cda24d Stub systemd in bats
81ec87b Skip systemctl when absent
986c1c8 Cover sudo retry in tests
ce9d52b Guard sudo fallback in ensure
348b391 Improve k3s path creation fallback
a28c1b5 Ensure bats availability and fix Jenkins stubs
4d54a30 k3d-manager::tests::jenkins: set JENKINS_DEPLOY_RETRIES=1 in the failure test and relaxed stderr assert to match the updated error messages
edc251e k3d-manager::plugins::jenkins: add configurable retries, and cleanup failed pod between attempts
c1233b1 k3d-manager: guardrail pv/pvc mount
0e29a1e k3d-manager: make all mktemp come with namespace so we can clean leftover file easily
ec5f100 k3d-manager::tests::test_auth_cleanup: update _curl stub to follow the dynamic host
d0721e6 k3d-manager::test: jenkins tls check now respects VAULT_PKI_LEAF_HOST
9a19d04 k3d-manager::README: prune references and ctags entries for public wrappers
9366213 k3d-manager::plugins::jenkins: align with private helpers
f67eab9 k3d-manager::vault_pki: dropped the legacy extract_/remoovek_certificate_serial shims
a4d49f4 k3d-manager::cluster_provider: remove public wrappers
35d8301 Merge branch 'partial-working'
1f957db k3d-manager: update README and tags
2802acb k3d-manager::plugins::jenkins: switch internal calls to private vault helper from cert-rotator
0a7c327 k3d-manager::lib::vault_pki: add wrapper shims so the old function names can be call the new implementations
691cfa4 k3d-manager::lib/cluster_provider: resore original public cluster_provider_* to hide _prviate productions
8351f87 k3d-manager: update tags
4161077 k3d-manager: update README
f894ab9 k3d-manager::tests::vault: update call _vault_pki_extract_certificate_serial in assertions
7354361 k3d-manager::plugins::vault: swap to _vault_pki_* helpers after issuing or revoking certs
0886973 k3d-manager::plugins::jenkins: check _cluster_provider_is instead of the older public helper
6ca07c9 k3d-manager::plugins::jenkins: reused the private vault helpers
0094a95 k3d-manager::core::vault_pki: prefix serial helpers with _vault_pki_* to mark them private
fc952fb k3d-manager::core:: use a logger fallback in _cleanup_on_success and updated the provider setter call
8b64182 k3d-manager: switch to new _cluster_provider_* entry points
1005b9d k3d-manager::cluster_provider: scope cluster-provider helpers as private functions
dee3b23 k3d-manager::tests::test_helpers: rework read_lines fallback to avoid mapfile/printf incompatiblities
b6f3bb8 k3d-manager::tests::install_k3s: new test harness verifying _install_k3s
8befa5d k3d-manager::tests::vault: swap mapfile usage for the portable helper to keep vault tests
ad6abff k3d-manager::tests::jenkins: harden trap parsing for MacOS bash 3 edge cases
8fdadd9 k3d-manager::tests::deploy_cluster: avoid mapfile, and a python envsubst stub
eb5476e k3d-manager::plugins::jenkins: hardened trap parsing for MacOS bash 3 edge cases
e7a9b80 k3d-manager::vault_pki: replace bash-4 uppercase expand with portble tr call
68b6bcc k3d-manager::plugins::jenkins: made logging portable, resolved kubectl override via share helper
0e08c14 k3d-manager::provider::k3s: ensure provider install/deploy paths pass the cluster name
7b6913b k3d-manager::core:: add k3s assert staging, config rendering, and instller wiring
cd09d45 k3d-manager: remove https
2589792 k3d-manager: update AGENTS.md
5e6875d k3d-manager: add AGENTS.md
3d6a31d k3d-manager: use k3d.internal
7a3f38a k3d-manager::plugins::jenkins: update helm values.yaml to use controller.probes structure
2378f84 k3d-manager::plugins::jenkins: update helm value to use current probes structure
d22a79c k3d-manager::plugins::jenkins: remove duplicate functions
73501d4 k3d-manager::tests::jenkins: update test cases
be54ca2 k3d-manager::plugins::jenkins: update kubectl discovery helpers
132d6ab k3d-manager::plugins::jenkins: remove invalid syntax from cert-rotator.sh
