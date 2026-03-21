# Changes - k3d-manager

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
