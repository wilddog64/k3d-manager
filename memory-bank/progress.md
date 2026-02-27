# Progress – k3d-manager

## Overall Status

Branch `ldap-develop` has completed a major test-strategy overhaul (2026-02-20):
mock-heavy BATS suites were retired and E2E smoke testing is now the primary
integration confidence path. Current focus is Jenkins k8s agents/SMB CSI and
continued end-to-end validation for auth/deploy modes.

---

## What Is Complete ✅

### Core Infrastructure
- [x] Dispatcher + lazy plugin loading pattern (`scripts/k3d-manager`)
- [x] `_run_command` wrapper (sudo probing, trace auto-disable for sensitive flags)
- [x] Configuration-driven strategy pattern (CLUSTER_PROVIDER, DIRECTORY_SERVICE_PROVIDER, SECRET_BACKEND)
- [x] k3d provider implementation (Docker-based, macOS default)
- [x] k3s provider implementation (systemd-based, Linux)
- [x] Bats test framework integration (auto-install via `_ensure_bats`)
- [x] Test log hierarchy (`scratch/test-logs/<suite>/<case-hash>/<timestamp>.log`)
- [x] Test strategy overhaul: removed brittle mock-heavy BATS suites
- [x] Added `test smoke` E2E subcommand in `scripts/lib/help/utils.sh`

### Vault & Secrets
- [x] Vault deployment via Helm with auto-init and unseal
- [x] Vault PKI bootstrap (root CA + issuing role for jenkins-tls)
- [x] Vault K8s auth method setup for ESO integration
- [x] ESO deployment + SecretStore wiring to Vault
- [x] `reunseal_vault` helper (Keychain/libsecret shard retrieval)
- [x] Secret backend abstraction (`SECRET_BACKEND` env var, `vault` backend complete)

### Jenkins
- [x] Jenkins deployment via Helm with Vault-issued TLS cert
- [x] ExternalSecret resources for Jenkins credentials via ESO
- [x] Jenkins cert rotation CronJob (`jenkins-cert-rotator`) — code complete
- [x] Jenkins cert rotation auth/template fixes (`envsubst` default handling)
- [x] JCasC authorization in flat `permissions:` format (matrix-auth plugin safe)
- [x] `bin/smoke-test-jenkins.sh` integrated into `test smoke` workflow

### Directory Services
- [x] Directory service provider abstraction (interface contract defined)
- [x] OpenLDAP provider — full implementation
- [x] OpenLDAP with AD-compatible schema (`deploy_ad` command, `bootstrap-ad-schema.ldif`)
- [x] Active Directory provider — all interface functions implemented
- [x] AD provider: 36 automated Bats tests, 100% passing
- [x] `--enable-ad` flag (OpenLDAP + AD schema testing mode)
- [x] `--enable-ad-prod` flag (external real AD via `AD_DOMAIN`)
- [x] `--enable-ldap` flag (standard OpenLDAP)
- [x] `TOKENGROUPS` strategy for efficient real-AD nested group resolution
- [x] `AD_TEST_MODE=1` for offline unit testing

### Documentation & Rules
- [x] CLAUDE.md (comprehensive dev guide)
- [x] `.clinerules` built from docs/ (2026-02-19, covers all known patterns and gotchas)
- [x] `memory-bank/` created (this session, 2026-02-19)
- [x] `docs/tests/certificate-rotation-validation.md` (test plan ready)
- [x] `docs/tests/active-directory-testing-instructions.md`
- [x] `docs/plans/` — full set of interface and integration design docs
- [x] `docs/issues/` updated with operational issues through 2026-02-20

---

## What Is Pending ⏳

### Priority 1 (Current implementation focus)

- [ ] **Jenkins Kubernetes agents + SMB CSI**
  - Plan: `docs/plans/jenkins-k8s-agents-and-smb-csi.md`
  - Goal: reliable dynamic agents and storage-backed workload validation.

### Priority 2 (Validation)

- [ ] **End-to-End AD Integration Test** — validate both AD modes
  - `--enable-ad` (OpenLDAP + AD schema): deploy, login as alice/bob/charlie, verify group mapping
  - `--enable-ad-prod` (real AD): requires access to AD environment
  - Guide: `docs/tests/active-directory-testing-instructions.md`

- [ ] **Broaden smoke coverage for deploy/auth combinations**
  - Continue live-cluster validation via `test smoke`.
  - Include key Jenkins/Vault/LDAP/AD flag paths.

### Priority 3 (Documentation — complete before or shortly after merge)

- [ ] `docs/guides/certificate-rotation.md` — operator guide for cert rotation
- [ ] `docs/guides/mac-ad-setup.md` — macOS AD connectivity setup
- [ ] `docs/guides/ad-connectivity-troubleshooting.md` — AD debugging guide

### Priority 3.5 (CI / Repository hygiene)

- [x] **Branch protection enabled on `main`** (2026-02-22, updated 2026-02-24)
  - 1 PR approval required, stale review dismissal, enforce admins
  - `lint` job now required as status check (added 2026-02-24)

- [x] **Self-hosted runner installed** (2026-02-24)
  - Runner: `m2-air` (macOS, ARM64) — online on `wilddog64/k3d-manager`

- [ ] **CI workflow implementation**
  - Plan: `docs/plans/ci-workflow.md`
  - **Stage 1:** shellcheck + bash -n + yamllint (workflow files only) + lib unit BATS (no cluster)
    - Status: **Implemented and green (2026-02-23)**
    - Added: `.github/workflows/ci.yml`, `.github/actions/setup/action.yml`, `.shellcheckrc`
    - Shellcheck baseline: `disable=SC2148`
    - Shellcheck scope: files with Bash shebang only
  - **Stage 2:** integration tests against pre-built cluster (self-hosted Mac runner)
    - **Stage 2.0:** `scripts/ci/check_cluster_health.sh` — implemented ✅
    - **Stage 2.1:** `test_vault`, `test_eso`, `test_istio` — namespace isolation done ✅
    - **Stage 2.2:** `stage2` job added to `.github/workflows/ci.yml` (2026-02-26) — awaiting m2-air validation + required status check update
  - **Stage 3:** destructive tests via `workflow_dispatch` only — not yet created

### Priority 4 (Nice-to-have / future)

- [ ] `bootstrap-basic-schema.ldif` for standard LDAP with pre-seeded users
- [ ] `--keep-test-users` flag for `deploy_ldap`
- [ ] `bin/smoke-test-jenkins.sh` Phases 4–5 (auth flow, LDAP-specific tests)
- [ ] `test_jenkins_smoke` command in main dispatcher
- [ ] Azure secret backend: complete wiring (`azure` plugin exists, partial)
- [ ] AWS / GCP secret backends (planned in `SECRET_BACKEND` abstraction)
- [ ] Monitoring recommendations (Prometheus alerts for cert expiry)
- [ ] Additional automated Bats tests for Jenkins and ESO plugins
- [ ] **Argo CD implementation** — Phase 1 design complete in `docs/plans/argocd-implementation-plan.md`
      Core deployment + LDAP/Dex + Vault/ESO + Istio integration (~4-6 hours for Phase 1)
- [ ] **OrbStack provider** — Plan: `docs/plans/orbstack-provider.md`
  - [x] Phase 1: OrbStack as k3d runtime (`CLUSTER_PROVIDER=orbstack`) — implemented 2026-02-24
  - [x] Phase 2: Auto-detection — OrbStack picked automatically when active
  - [x] **m4 local validation** — Phase 1+2 verified on `m4` Mac (2026-02-24)
    - Auto-detection and provider fixes verified.
    - Full-stack tests documented two integration issues (`deploy_vault` path creation and `deploy_jenkins` none-auth smoke test).
  - [ ] **m2-air validation** — full stack test required before Phase 1+2 considered production-ready
    - Prerequisite: OrbStack installed on `m2-air`
    - Sequence: `create_cluster` → `deploy_vault` → `reunseal_vault` (ESO included in deploy_vault; Istio included in create_cluster)
    - If passes: `m2-air` cluster becomes Stage 2 CI fixture
  - [ ] Phase 3: OrbStack native Kubernetes provider (no k3d overhead) — half day
- [ ] **Rename `LDAP_PASSWORD_ROTATOR_*` → `LDAP_ROTATOR_*`** — fix GitGuardian false positive
  - See `docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md`
  - Affects: `scripts/etc/ldap/vars.sh` and any referencing scripts

- [ ] **AI-powered code review via GitHub Actions**
  - Automate PR analysis using a cost-optimized model (Claude Haiku or GPT-4o-mini — ~20x cheaper than GPT-4o)
  - Inspired by: https://dev.to/paul_robertson_e844997d2b/ai-powered-code-review-automate-pull-request-analysis-with-github-actions-j90
  - Key capabilities to implement:
    - Smart filtering: skip generated files, files >50KB, vendored paths
    - Differential analysis: review only changed lines, not entire files
    - Inline PR comments via GitHub API (not just summary)
    - Severity-based output (blocker / warning / suggestion)
  - Builds on existing workflow: Copilot already opens sub-PRs with real code changes
  - Formalize the counter-argue protocol already in `.clinerules` as a required review gate
  - Consider: model-diff validation step (compare Claude vs GPT-4o disagreements on same diff)
    - Reference: https://dev.to/lakshmisravyavedantham/i-built-a-tool-that-shows-exactly-where-gpt-4-and-claude-disagree-the-results-were-surprising-2n65

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| `deploy_jenkins` (no vault) broken | OPEN | Policy creation always runs; jenkins-admin secret missing |
| `--enable-ldap` without `--enable-vault` broken | OPEN | LDAP secrets require Vault |
| Basic LDAP deploys empty directory | OPEN | No bootstrap LDIF yet; use `deploy_ad` as workaround |
| LDAP password JCasC/envsubst interpolation | OPEN | `$${...}` escape attempt not yet confirmed working |
| `test_cert_rotation` via dispatcher | OPEN | Manual cert rotation works; dispatcher flow still unreliable/hangs |
| `test_vault` fails — ClusterRoleBinding conflict | FIXED | 2026-02-26: test now reuses the existing `vault` namespace/release, validates readiness up front, and only cleans up the test namespace, Vault role, and seeded secret. See `docs/issues/2026-02-26-test-vault-clusterrolebinding-conflict.md`. |
| `test_eso` fails — ClusterSecretStore API version mismatch | FIXED | 2026-02-27: `v1beta1` → `v1` in `scripts/lib/test.sh` line 591. Detected on m2-air by Gemini. See `docs/issues/2026-02-27-test-eso-apiversion-mismatch.md`. |
| `test_eso` fails — `insecureSkipVerify` removed in ESO v1 | FIXED | 2026-02-27: Vault uses HTTP internally; switched server URL to `http://` and removed `tls` block. See `docs/issues/2026-02-27-test-eso-v1-schema-incompatibility.md`. |
| `test_eso` fails — jsonpath single-quote interpolation | FIXED | 2026-02-27: switched to double quotes so `${secret_key}` expands before `kubectl` runs. Locally validated via `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_eso`. See `docs/issues/2026-02-27-test-eso-jsonpath-interpolation-failure.md`. |
| ESO SecretStore `mountPath` wrong | FIXED | Must be `kubernetes` not `auth/kubernetes` |
| LDAP bind DN mismatch | FIXED | Keep `LDAP_BASE_DN` consistent with LDIF base DN |
| Jenkins pod readiness timeout | FIXED | 10m timeout + pod existence check |
| GitGuardian false positive: `LDAP_PASSWORD_ROTATOR_IMAGE` | FALSE POSITIVE | Variable name contains "PASSWORD", value is a Docker image. Fix: rename to `LDAP_ROTATOR_IMAGE`. See `docs/issues/2026-02-23-gitguardian-false-positive-ldap-rotator-image.md` |
| OrbStack: `deploy_cluster` unsupported provider | FIXED | Added `orbstack` to the provider guard in `scripts/lib/core.sh`. See `docs/issues/2026-02-24-orbstack-unsupported-provider-in-core.md`. |
| OrbStack: `--dry-run` flag broken in `create_cluster` | FIXED | `create_cluster` now parses `--dry-run` and the k3d provider uses `grep -q --` to avoid option parsing. See `docs/issues/2026-02-24-orbstack-dry-run-errors.md`. |
| `deploy_vault` fails on macOS — host path mkdir | FIXED | `_vault_ensure_data_path` now skips host `mkdir` on macOS; validation via `CLUSTER_PROVIDER=orbstack ./scripts/k3d-manager deploy_vault`. See `docs/issues/2026-02-24-macos-vault-local-path-creation-failure.md`. |
| Jenkins `none` auth mode smoke test failure | FIXED | Local realm + matrix permissions rebuilt via `scripts/plugins/jenkins.sh` awk patch. Jenkins deploy succeeds; issue documented in `docs/issues/2026-02-24-jenkins-none-auth-mode-smoke-test-failure.md`. |
| Jenkins smoke test fails on macOS — Istio LB IP unreachable | FIXED | `_jenkins_run_smoke_test` now tunnels through `istio-system/svc/istio-ingressgateway` so the fallback hits a real HTTPS listener; rest of the RFC-1918 detection + trap cleanup stays unchanged. See `docs/issues/2026-02-25-jenkins-smoke-test-routing-service-mismatch.md`. |
| Smoke script silent failure (unbound PLUGINS_DIR) | FIXED | Verified (2026-02-26): `bin/smoke-test-jenkins.sh` normalized paths to allow standalone and orchestrated library sourcing. |
| Jenkins VirtualService hostname detection fails | FIXED | Verified (2026-02-26): `_jenkins_run_smoke_test` namespace query fixed; custom hostnames now auto-detected. |
