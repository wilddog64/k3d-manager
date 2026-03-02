# Progress – k3d-manager

## Overall Status

`ldap-develop` merged to `main` via PR #2 (2026-02-27). **v0.1.0 released.**

**ArgoCD Phase 1 — MERGED ✅ (v0.4.0, 2026-03-02)**
Deployed live to infra cluster. ArgoCD running in `cicd` ns.

**Keycloak — PR #13 OPEN 🔄 (v0.5.0)**
Branch `feature/infra-cluster-complete`. All fixes applied (envsubst whitelist, non-Vault admin secret, config CLI flag, shared SecretStore, YAML password quoting). CI green. Awaiting owner merge.

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
- [x] Two-cluster refactor (namespace renames, role gating, remote vault support) — **VERIFIED 2026-03-01**

### Jenkins
- [x] Jenkins deployment via Helm with Vault-issued TLS cert
- [x] ExternalSecret resources for Jenkins credentials via ESO
- [x] Jenkins cert rotation CronJob (`jenkins-cert-rotator`) — code complete
- [x] Jenkins cert rotation auth/template fixes (`envsubst` default handling)
- [x] JCasC authorization in flat `permissions:` format (matrix-auth plugin safe)
- [x] `bin/smoke-test-jenkins.sh` integrated into `test smoke` workflow
- [x] Jenkins `cicd` namespace fix — template now honors `$JENKINS_NAMESPACE` and `deploy_jenkins` respects env var override. **VERIFIED 2026-03-02.**

### ArgoCD
- [x] ArgoCD Phase 1 — Manifest cleanup, namespace substitution (`platform.yaml.tmpl`), Vault admin secret seeding, and new test suite. **VERIFIED 2026-03-02.**
- [x] ArgoCD live deploy — running in `cicd` ns on infra cluster. **DEPLOYED (v0.4.0).**

### Keycloak
- [x] `deploy_keycloak` plugin (Bitnami) — `feature/infra-cluster-complete` (Codex). **VERIFIED 2026-03-02.**
- [ ] Keycloak provider interface (Bitnami + Operator) — **v0.6.0** — spec in `docs/plans/infra-cluster-complete-codex-task.md`

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
- [x] Vault: `system:auth-delegator` ClusterRoleBinding in `deploy_vault` — code complete and validated via `PATH="/opt/homebrew/bin:$PATH" ./scripts/k3d-manager test_vault` (2026-02-27).

### App Cluster Foundation
- [x] k3d-manager app-cluster mode refactor (v0.3.0)
- [x] End-to-end Infra Cluster Rebuild (v0.6.0)
  - [x] Vault + ESO → `secrets` ns
  - [x] OpenLDAP → `identity` ns
  - [x] Istio → `istio-system`
  - [x] Jenkins → `cicd` ns
  - [x] ArgoCD → `cicd` ns
  - [x] Keycloak → `identity` ns
- [x] Configure Vault `kubernetes-app` auth mount for Ubuntu app cluster

---

## What Is Pending ⏳

### Priority 1 (Current focus)

**App Cluster Deployment:**
- [ ] ESO deploy on App cluster (remote Vault addr: `https://<mac-ip>:8200`)
- [ ] shopping-cart-data (PostgreSQL, Redis, RabbitMQ) deployment on Ubuntu
- [ ] shopping-cart-apps (basket, order, payment, catalog, frontend) deployment on Ubuntu

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| GitGuardian: 1 internal secret incident (2026-02-28) | OPEN | No real secrets — likely IPs in docs. Mark false positive in dashboard. See `docs/issues/2026-02-28-gitguardian-internal-ip-addresses-in-docs.md`. |
| `CLUSTER_NAME=automation` env var ignored during `deploy_cluster` | OPEN | 2026-03-01: Cluster created as `k3d-cluster` instead of `automation`. See `docs/issues/2026-03-01-cluster-name-env-var-not-respected.md`. |
| No `scripts/tests/plugins/jenkins.bats` suite | BACKLOG | Jenkins plugin has no dedicated bats suite. `test_auth_cleanup.bats` covers auth flow. Full plugin suite (flag parsing, namespace resolution, mutual exclusivity) is a future improvement — not a gate for current work. |
