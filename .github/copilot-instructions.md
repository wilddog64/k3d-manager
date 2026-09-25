# GitHub Copilot Instructions — k3d-manager

k3d-manager is a modular Bash utility for managing local Kubernetes development clusters.
Use the rules below to shape all code suggestions and PR reviews.

---

## Architecture

- **Entry point**: `scripts/k3d-manager` — dispatcher with lazy plugin loading.
- **Core libraries**: `scripts/lib/system.sh`, `scripts/lib/core.sh`, `scripts/lib/agent_rigor.sh`.
- **Plugins**: `scripts/plugins/` — sourced on demand, no side effects at source time.
- **Privilege escalation**: always via `_run_command --prefer-sudo` or `--require-sudo` — never bare `sudo`.
- **OS detection**: always via `_detect_platform` — never inline `_is_mac`/`_is_debian_family` dispatch chains.
- **Secret backends**: interface in `scripts/lib/secret_backends/` — Vault is complete, others stubbed.
- **Cluster providers**: `scripts/lib/providers/` — `k3d`, `orbstack`, `k3s-aws`, `k3s-oci`, `k3s-gcp`, `k3s-az`, `k3s-hostinger`. **v1.28.0+: parallel multi-cloud supported** — multiple providers can be active concurrently. Provider-scoped state stored under `${_ACG_STATE_DIR}/<provider>/` via `scripts/lib/provider.sh` helpers (`_acg_record_provider`, `_acg_unrecord_provider`, `_acg_list_active_providers`). `bin/require-unambiguous-provider` gate refuses bare `make down/status` when ≥2 providers live + no explicit `CLUSTER_PROVIDER`. Self-resolution: explicit env > active-provider file (legacy fallback) > reachable-context probe > default `k3s-aws`.
- **ACG plugin**: `scripts/plugins/acg.sh` — `acg_get_credentials`, `acg_provision`, `acg_status`, `acg_extend`, `acg_watch`, `acg_teardown`. Manages Pluralsight ACG sandbox lifecycle via CloudFormation + k3sup (AWS) or GCP.
- **GCP plugin**: `scripts/plugins/gcp.sh` — `gcp_login`, `gcp_get_credentials`. OAuth automation via CDP; GCE cluster provisioning via k3sup.
- **Playwright**: `scripts/lib/foundation/scripts/lib/acg/playwright/` — static Node.js scripts: `acg_credentials.js` (AWS/GCP credential extraction), `acg_extend.js` (sandbox TTL extend), `gcp_login.js` (Google OAuth flow automation). All connect to Chrome via CDP (`localhost:9222`). Source of truth is `wilddog64/lib-foundation` (the standalone `lib-acg` repo was absorbed into lib-foundation as of v1.8.0); pulled into k3d-manager as part of the lib-foundation git subtree under `scripts/lib/foundation/`.
- **Browser automation**: `scripts/plugins/gemini.sh` — `_browser_launch`. Launches Chrome with `--remote-debugging-port=9222 --password-store=basic`. On Linux, `--no-sandbox` is added only when running as root (`$EUID -eq 0`) or `ANTIGRAVITY_CHROME_NO_SANDBOX=1`. As of v1.8.0 the Copilot-review functions invoke the Go-based Antigravity CLI (`agy --dangerously-skip-permissions`) — the retired `@google/gemini-cli` is no longer used; public `gemini_*` names are retained.
- **ACG module (absorbed)**: `scripts/lib/foundation/scripts/lib/acg/` — ACG/GCP Playwright automation library, now part of lib-foundation (`wilddog64/lib-foundation`). Contains `scripts/plugins/acg.sh`, `scripts/plugins/gcp.sh`, `scripts/lib/cdp.sh`, `playwright/` scripts, and `scripts/vars.sh`. k3d-manager stubs in `scripts/plugins/acg.sh`, `scripts/plugins/gcp.sh`, and `scripts/plugins/gemini.sh`, plus `bin/cluster-up`/`bin/cluster-refresh`, repoint here. The standalone `scripts/lib/acg/` subtree and its `lib-acg` git remote were removed in v1.8.0.
- **Tunnel**: `scripts/plugins/tunnel.sh` — `tunnel_start`, `tunnel_stop`, `tunnel_status`. autossh + launchd; forward tunnel (k3s API :6443) + reverse tunnel (Vault :8200).
- **Vault plugin**: `scripts/plugins/vault.sh` — `vault_init`, `vault_install_unseal_watchdog` (Tier 3 P2a in-cluster unseal watchdog CronJob), `configure_vault_app_auth_for_context` (provider-agnostic Kubernetes auth for app clusters, v1.10.0+), `vault_deploy_hub_into_context` (hub-Vault relocation into app cluster, v1.10.0+). Vault server lifecycle and app-cluster auth config; portable across providers (EKS/AKS/ACG/Azure/OCI/Hostinger).
- **AWS helpers**: `scripts/plugins/aws.sh` — `aws_import_credentials`.
- **Shopping Cart plugin**: `scripts/plugins/shopping_cart.sh` — `add_ubuntu_k3s_cluster`, `deploy_shopping_cart_data`, `shopping_cart_sync_vault_backed_secrets`, `shopping_cart_load_ghcr_pat_*`, `shopping_cart_resolve_ghcr_pat`, `shopping_cart_create_ghcr_pull_secret`, `shopping_cart_create_vault_bridge`, `shopping_cart_install_helm_and_eso`, `shopping_cart_apply_vault_token_and_cluster_secret_store`, `shopping_cart_seed_sandbox_vault_kv`, `shopping_cart_prepare_*`, `shopping_cart_reconcile_*`, `register_shopping_cart_apps`, `deploy_app_cluster`. Manages full-stack shopping-cart app deployment with ESO credential sync, Vault integration, and ArgoCD GitOps.
- **OCI Storage plugin**: `scripts/lib/providers/k3s-oci-storage.sh` — `oci_backup` (etcd snapshot → OCI object storage), `oci_restore` (restore from OCI object storage → etcd). Auto-backup runs after `k3s-oci` deploy. Snapshot names validated against `^k3s-etcd-[0-9]{8}-[0-9]{6}\.db$` pattern.
- **Copilot plugin**: `scripts/plugins/copilot.sh` — `copilot_triage_pod <ns> <pod>` (collects kubectl describe + logs → Copilot diagnosis), `copilot_draft_spec '<desc>'` (collects git context → scaffolds a `docs/bugs/` spec). Both require `K3DM_ENABLE_AI=1`. Route through `_ai_agent_review` in `scripts/lib/system.sh` and keep `_copilot_review` as the backend implementation.
- **Observability plugin**: `scripts/plugins/observability.sh` — `deploy_observability` (Hub kube-prometheus-stack + Trivy via ArgoCD), `deploy_observability_acg` (ACG minimal Prometheus + Trivy via ArgoCD), `observability_status`, `trivy_scan_report`, `_observability_seed_grafana_if_absent` (idempotent Grafana KV seed, self-heal on rebuild, v1.29.0+). Hub Grafana federates ACG Prometheus via `host.internal:19090`; `bin/acg-up` Step 14 starts the port-forward (`acg-prom-pf.pid`); `bin/acg-down` kills it. ApplicationSets: `scripts/etc/argocd/applicationsets/observability.yaml` (Hub) and `observability-acg.yaml` (ACG). Helm values under `scripts/etc/helm/observability/`.
- **Hermes Phase-1 plugin** (v1.29.0+): `bin/k3dm-hermes` — off-hub, laptop-side read-only monitoring agent. Five stdlib-only sensors (ESO sync via webhook, ArgoCD per-app health via get-only `hermes` account, public-endpoint reachability, node/data-layer via webhook, GitHub Actions CI read-only API). Deterministic multi-signal correlator (≥2 degraded in-window, anti-flap debounce), budgeted LLM (non-Claude default, 10/day cap, deterministic fallback). Installed via lib-foundation **v0.4.15** `_install_hermes_agent`/`_uninstall_hermes_agent` (off-hub launchd agent, bounded `StartInterval`, jitter). Read-only access model: webhook bearer token (reused), ArgoCD `hermes` get-only account in `scripts/etc/argocd/values.yaml.tmpl`, user-minted GitHub fine-grained read-only PAT. No mutation path, no direct kube-apiserver credential, no kubeconfig. Guide: `docs/guides/hermes.md`. Agent entry: `bin/k3dm-hermes` (no-arg poll cycle) plus `preflight` (v1.31.0+, scope-check tool), `list` / `approve <action-id>` (v1.30.0+, Phase 2 repairs) subcommands; configuration is env-var driven (no config-file flag). Install: `bin/k3dm-hermes-setup`, uninstall: `bin/k3dm-hermes-setup --uninstall`.
- **Image signing plugin**: `scripts/plugins/signing.sh` — `signing_init` (seed/rotate cosign keypair into Vault + ESO + Keychain backup), `signing_status` (verify key presence), `signing_rotate_key` (regenerate keypair), `deploy_image_signing` (install Kyverno + verifyImages policy). Three-latch CVE-loop: BUILD signs and attests, PROMOTE verifies attestation, ADMIT (Kyverno) enforces signature + attestation. Shipped inert by default; staged Audit→Enforce (v1.27.0+).
- **Istio Ambient plugin**: `scripts/plugins/istio_ambient.sh` — `deploy_istio_ambient` (v1.16.0+). Applies the istio-ambient ApplicationSet to deploy Istio in ambient mode (ztunnel + istio-cni, zero sidecar containers, HBONE/mTLS). Substrate-aware: resolves CNI conf/bin directories to Cilium defaults (`/etc/cni/net.d`, `/opt/cni/bin`) or k3s flannel paths via `AMBIENT_CNI_CONF_DIR`/`AMBIENT_CNI_BIN_DIR` environment variables.
- **Keycloak plugin**: `scripts/plugins/keycloak.sh` — `deploy_keycloak`, `test_keycloak`, `keycloak_seed_smoke_user` (v1.17.0+). Keycloak lifecycle, LDAP federation, and the login-verification smoke identity: `keycloak_seed_smoke_user` seeds a k3d-manager-owned `k3dm-smoke` public client (direct-access-grant enabled) plus a local user, storing the generated password in the `identity/k3dm-smoke-user` Secret. It exists because the app-owned `frontend` client has `directAccessGrantsEnabled=false`, so a password grant can never succeed against it. Idempotent — re-run to restore after an app-owned realm reconcile. Seeded users MUST carry the Keycloak 24+ required User Profile attributes (`email`, `firstName`, `lastName`, `emailVerified`) or the direct-grant mint fails `invalid_grant "Account is not fully set up"`.
- **E2E testing plugins**: `scripts/plugins/e2e.sh` (Tier 1 local vCluster), `scripts/plugins/e2e_remote.sh` (Tier 2 ACG/Stripe acceptance), `scripts/plugins/smoke.sh` (unified `make smoke` target; Tier 1 & Tier 2 health probes, skip-tier semantics). E2E logs routed through Hermes deterministic triage (v1.36.0+), failure classification stable across suite updates.
- **Hub snapshot plugin**: `scripts/plugins/hub_snapshot.sh` — `hub_snapshot_capture`, `hub_snapshot_list`, `hub_snapshot_restore` (v1.36.0+). Captures hub state (PVCs + snapshots) to M2 remote via rsync; Loki recovery record stored in Vault for unattended `hub_recovery_restore` (v1.33.0+). Idempotent capture, checksum-verified transfer, retention policy driven by `K3DM_SNAPSHOT_RETENTION_DAYS`.
- **Hub recovery plugin**: `scripts/plugins/hub_recovery.sh` — `hub_recovery_plan`, `hub_recovery_validate`, `hub_recovery_targets`, `hub_recovery_restore` (v1.33.0+). Kine control-plane recovery for the seven durable hub local-path claims, keyed on stable `(namespace, claim)` identity rather than PVC UID. `plan`, `validate` and `targets` are **read-only**; `validate` is fail-closed and requires exactly one source tree per approved claim. `restore` renders by default and only copies under an explicit `--confirm` — it never recreates a cluster or deletes a volume. Review any change here for that confirm gate and for the read-only guarantee of the other three.
- **Health smoke login checks**: `bin/k3dm-webhook` `_smoke_test_logins` — verifies **real logins** (credentialed token POST / authed request) for Keycloak, Frontend, ArgoCD, Grafana rather than fetching health pages, which false-green on a stale-session HTTP 200. Grading contract: 2xx→pass, a smoke-client `401`/`403`→skip (`ok=None`, audience-strict deployment), anything else→fail.
- **Webhook modules (v1.37.0+)**: `bin/k3dm-webhook` is the entrypoint; the implementation lives in `scripts/lib/webhook/` — `policy.py` (authorization + the explicit route table), `auth.py`, `smoke.py` (browser-emulating SSO client), `agent.py` (AI invocation, role-gated cluster-mutation decision, prompt-injection filter), `lifecycle.py` (long-running orchestration), `status.py` (read-only reporting), plus `config.py`, `make_targets.py`, `proc.py`, `render.py`. Dependencies are injected by the entrypoint — a module must not reach back into it. Review any change here against three rules the decomposition established: an **unknown actor role normalizes to `reader`**, never `admin` (the requirement side keeps its `admin` default); POST authorization enforces the route's `min_role` floor with the effective requirement the **stricter** of floor and dynamic policy; and every request is audited **exactly once**, including requests with no dynamic policy. `cmd[0]` at every spawn site must stay a literal, and request-derived argv must stay constrained by anchored, metacharacter-free `fullmatch` patterns — that invariant is what makes the four dismissed CodeQL `posix_spawn` alerts false positives, so a change that loosens it turns them real.
- **Remaining plugins** (no dedicated bullet above, all in `scripts/plugins/`): `argocd.sh` (`deploy_argocd`, `deploy_argocd_applicationsets`, `register_app_cluster`, `argocd_check_values_branch`, `argocd_reclaim_release_ownership`, `argocd_reconcile_app_cluster_registrations`, the `argocd_sync_*_secret` family), `azure.sh` (`create_az_sp`, `deploy_azure_eso`, `eso_akv`), `cert-manager.sh` (`deploy_cert_manager`), `eso.sh` (`deploy_eso`), `ldap.sh` (`deploy_ldap`, `deploy_ad`, `ldap_get_user_password`), `loadtest.sh` (`loadtest_run`, `loadtest_status`), `smb-csi.sh` (`deploy_smb_csi`), `ssm.sh` (`ssm_wait`, `ssm_exec`, `ssm_tunnel`), `vcluster.sh` (`vcluster_create`, `vcluster_destroy`, `vcluster_use`, `vcluster_list`), `hello.sh` (`hello`, dispatcher smoke test), and `jenkins.sh` (`deploy_jenkins` — **deprecated**, disabled by default and not deployed; do not suggest extending it).
- **Convenience scripts**: `bin/acg-up`, `bin/acg-down`, `bin/acg-refresh`, `bin/acg-status`, `bin/acg-sync-apps`, `bin/rotate-ghcr-pat`, `bin/cluster-status`, `bin/cluster-status-summary` — orchestrate plugin calls for common one-shot operations. `bin/cluster-status` is the backend for Make targets `make status` (concise service-health summary, default), `make status-full` (detailed diagnostics), and `make status-json` (stable machine-readable output); accepts `--service <name>` for single-service focus (v1.24.1+).

---

## Review Focus

### Shell Injection (OWASP A03)
- All variable expansions in command arguments must be double-quoted: `"$var"`, not `$var`.
- Never pass user-supplied or external input to `eval`.
- Use `--` to separate options from arguments where arguments may contain hyphens.
- Variables expanded via `envsubst` in `*.yaml.tmpl` files must not contain shell metacharacters.

### Privilege Escalation
- Bare `sudo` calls in production code are a bug — all privilege escalation must go through `_run_command`.
- `_run_command --prefer-sudo` for operations that may succeed without sudo.
- `_run_command --require-sudo` for operations that always need root.
- Flag any multi-attempt permission cascades (trying the same operation 2+ times with escalating privilege).
- When reviewing shell scripts, check that every privileged operation is routed through `_run_command`; only the runner internals may call `sudo` directly.
- When reviewing shell scripts, call out unquoted variables, direct `eval`, ad hoc `sudo`, and commands that will fail non-interactively in CI.

### Platform Detection
- `_detect_platform` is the single source of truth for OS detection in `core.sh`.
- Flag inline dispatch chains (`if _is_mac; elif _is_debian_family; elif ...`) with more than 2 branches — these should route through `_detect_platform`.
- `linux` returned by `_detect_platform` means an unsupported generic Linux — do not route it into Debian or RedHat install paths.
- **`base64` decode flag:** use `base64 --decode` — it is the only spelling accepted by BOTH GNU coreutils and BSD/macOS. Do **not** suggest `base64 -D` or a `--decode || -D` fallback: `-D` is rejected by GNU coreutils (`invalid option`), so the fallback arm can only fail on Linux, and in a pipeline (`cmd | base64 --decode || base64 -D`) the fallback re-runs with no stdin of its own and silently decodes nothing. `-d` also works on current macOS but is not the house form. (Measured v1.17.0 — see `docs/issues/2026-07-24-copilot-pr107-review-findings.md`.)

### Secret Hygiene (OWASP A02)
- Vault tokens and passwords must never appear in `kubectl exec` command strings — they would be visible in `/proc/*/cmdline` and logs.
- New sensitive CLI flags (e.g. `--token`, `--password`, `--secret`) must be registered in `_args_have_sensitive_flag` in `system.sh`.
- No hardcoded credentials, tokens, or IP addresses in any file.
- Test credentials (`alice/password`, etc.) are dev-only — flag if they appear outside test files.
- **Xtrace secret-leak guard (v1.29.0+):** When `set -x` debugging is active, Bash echoes the fully-expanded calling line BEFORE function bodies execute. Functions that load secrets from Keychain or Vault must wrap the sensitive operations in `set +x` / `set -x` guards, including the password generation, variable assignment, and any subshell that uses the secret. Pattern: `{ set +x; <secret-load>; <use-secret>; set -x; }`. Without this guard, the secret appears in logs even if the function has its own internal `set +x` guards. Precursors: `scripts/plugins/observability.sh:_observability_seed_grafana_if_absent` (v1.29.0 commit `60c01632`) and `scripts/plugins/signing.sh:_signing_restore_vault_from_keychain`.

### Least Privilege (OWASP A01)
- New Vault policies must grant only the minimum required paths (`read` unless `write` is explicitly needed).
- New Kubernetes ServiceAccounts must not use `cluster-admin` — use namespace-scoped Role + RoleBinding.
- Every new deployed service must use its own namespace — never `default`.

### Multi-Cloud / Kubeconfig Portability
- **Kubeconfig context ≠ cluster name:** in kubeconfig, a context name and its cluster name are independent fields. When reading cluster server/CA from kubeconfig, always resolve `.contexts[?(@.name=="<context>")].context.cluster` first to get the cluster name, then query `.clusters[?(@.name=="<cluster-name>")]`. Never key `.clusters[]` directly on the context name — this breaks on EKS/AKS/GCP where names differ. See `configure_vault_app_auth_for_context` for correct pattern.
- **Base64 portability:** `base64 -d` is GNU-only; use `base64 --decode || base64 -D` dual-flag fallback for macOS/BSD compatibility. Precedent: `scripts/lib/identity_tools.sh:36`.

### Cryptographic Failures (OWASP A02)
- `insecureSkipVerify: true` and `TRUST_ALL_CERTIFICATES` are dev-only — flag if introduced in production paths.
- Vault PKI leaf cert TTL must stay ≤720h — flag increases without justification.
- Never add `--insecure` or `-k` to scripts that may run against production endpoints.

### Supply Chain (OWASP A08)
- GitHub Actions steps must pin to a version tag (`@v4`) — never `@main` or `@latest`.
- Container image references in `*.yaml.tmpl` must use a pinned tag, not `latest`.

### ACG / Playwright / Browser Automation
- AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`) must never appear in log output — even at INFO level. Use redacted placeholders or omit entirely.
- `PLURALSIGHT_EMAIL` and `PLURALSIGHT_PASSWORD` must never be logged or echoed.
- `acg_provision`, `acg_teardown` must check for existing resources before creating/deleting — "resource already exists" is not an error (`--soft` pattern or describe-stacks check).
- CloudFormation stack operations must always check stack existence before delete: `describe-stacks` → if None, skip.
- Playwright selectors (`input[aria-label="Copyable input"]`) are fragile — flag hardcoded positional index fallbacks that assume a fixed UI layout without a comment explaining why.
- For Playwright scripts that may attach via CDP: in the `finally` block, only call `browserContext.close()` when the context was launched by the script (`!_cdpBrowser`). Never call `browser.close()` on a CDP-attached session — it shuts down the entire Chrome process and disrupts other sessions.
- Chrome must always be launched with `--password-store=basic` and a dedicated `--user-data-dir` — flag any launch path that omits these flags.
- `GHCR_PAT` and GitHub PATs must be passed via stdin or env var — never as CLI arguments visible in `ps aux`.

### Idempotency
- Every public function must be safe to run more than once.
- "Resource already exists" → skip, not error.
- "Helm release already deployed" → upgrade, not re-install.

### Test Reachability (v1.35.0+)
- A new BATS suite must be reachable by the dispatcher's **directory discovery** (`scripts/tests/{lib,core,plugins,etc}`), never added to a hand-maintained file list. A hand-maintained list is how `scripts/tests/plugins/e2e_image_prune.bats` stayed dark in CI while `make test` was red locally.
- A suite placed in `scripts/tests/bin/` is run by `make test-bin`, **not** `make test` — the two are different runner roots. "make test is green" is not "the suite is green"; only `make test-all` covers both.
- A new `bin/` script should come with a `scripts/tests/bin/*.bats` case. Credential-rotation scripts are the priority — silent failure there is expensive.
- A new Python module under `scripts/lib/hermes/` or a new `bin/` Python script must be covered by `make test-pytest` or `make test-python-unit`. Neither ran in any automated path before v1.35.0.
- Flag any test that reads host state (`uname`, `date`, `$HOME`, the real clock) without stubbing it. Such a test passes on the author's macOS workstation and fails on the Linux CI runner — or, worse, passes on both and asserts nothing.
- Flag a timeout loop whose deadline is checked **before** the first attempt. `date +%s` is integer-second, so a pre-test guard can expire before one probe is issued and report failure having asked nothing. The budget bounds how long to keep retrying, never whether to try.

### Assertion Strength (v1.36.0+)

A green test proves nothing about a test that asserts nothing. These three patterns all pass while gating nothing, so a passing CI run cannot surface any of them — they have to be caught in review.

- **Flag `run <binary>` followed by a non-zero-status assertion.** `run rg …` + `[ "$status" -ne 0 ]` is satisfied by exit **127** — command not found. If the binary is absent from the runner, the case is not merely red, it is **vacuously green**: it passes for the wrong reason and would keep passing if the behaviour under test disappeared. Two such cases shipped in `argocd_reclaim_release_ownership.bats` and `argocd_appset_live_overrides.bats` and survived until v1.35.0 lit up the dark suites. Require either a positive assertion about `output`, or an explicit guard that the binary exists (`command -v <bin>` + `skip`). Only `grep`, `awk`, `sed`, `python3` and the repo's own scripts may be assumed present.
- **Flag `grep -F` of a whole line of source code.** Pinning an entire statement gates its *formatting*, not its behaviour: the test breaks when the line is reformatted, reordered or extended, while telling you nothing about whether the requirement still holds. Assert the tokens that carry the meaning — `grep -E` over the stable parts, a per-element membership loop for a collection literal, or `declare -F <name>` where the suite already sources the file under test (strictly stronger than matching a `function …()` signature, because it proves the function actually loaded). This applies to Python, JavaScript and `*.sh.tmpl` targets too, not just shell.
- **Flag a narrowed assertion that dropped a token the test's name claims.** When a whole-line assertion is replaced by a narrower one, the replacement must still assert every *requirement* the original did — narrowing, never weakening. Matching a distinctive substring is how you locate the statement; it is not how you decide what to assert about it. The check is the `@test` name: a token that name claims must survive, a token it does not claim may go. Three regressions of this kind reached review in PR #129 — a payload gate that dropped `namespace`, a relay gate that dropped `payload` and `meta`, and an ask-transcript gate that dropped `delete=False` (with `delete=True` the transcript the test "captures" is destroyed on close). All three still matched a distinctive token and all three stayed green. Ask for mutation evidence: the assertion must fail against a copy of the source with that token removed.

---

## Skip / Do Not Flag

- Pre-existing `shellcheck` warnings (SC2164 `pushd`/`popd`, etc.) in lines that were **not changed** by the PR.
- `_is_mac` / `_is_wsl` guards used as simple feature-skip (1–2 branch guards) — these are legitimate, not bloat.
- `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` and `insecureSkipVerify: true` in existing dev config files — already documented as dev-only.
- Test stubs and helper overrides in `scripts/tests/` — these intentionally override production functions.
- `set -euo pipefail` absence in sourced library files (`scripts/lib/`) — these are sourced, not executed directly.

---

## Code Style
- Public functions: no leading underscore.
- Private/helper functions: prefix with `_`.
- All new bash scripts must have `set -euo pipefail`.
- LF line endings only — no CRLF.
- No inline comments unless logic is non-obvious.
