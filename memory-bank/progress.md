# Progress – k3d-manager

## Overall Status

**v0.6.2 SHIPPED** — tag `v0.6.2` pushed, PR #19 merged 2026-03-06.
**v0.6.3 ACTIVE** — branch `k3d-manager-v0.6.3` cut from main 2026-03-06.

---

## What Is Complete

### Released (v0.1.0 – v0.6.2)

- [x] k3d/OrbStack/k3s cluster provider abstraction
- [x] Vault PKI, ESO, Istio, Jenkins, OpenLDAP, ArgoCD, Keycloak (infra cluster)
- [x] Active Directory provider (external-only, 36 tests passing)
- [x] Two-cluster architecture (`CLUSTER_ROLE=infra|app`)
- [x] Cross-cluster Vault auth (`configure_vault_app_auth`)
- [x] `_agent_checkpoint` + Agent Rigor Protocol (`scripts/lib/agent_rigor.sh`)
- [x] `_ensure_copilot_cli` / `_ensure_node` auto-install helpers
- [x] `_k3d_manager_copilot` scoped wrapper (8-fragment deny list, `K3DM_ENABLE_AI` gate)
- [x] `_safe_path` / `_is_world_writable_dir` PATH poisoning defense (sticky-bit exemption removed)
- [x] VAULT_TOKEN stdin injection in `ldap-password-rotator.sh`
- [x] BATS suites: `ensure_node`, `ensure_copilot_cli`, `k3d_manager_copilot`, `safe_path` — 120/120 passing

---

## What Is Pending

### Priority 1 — v0.6.3 (active)

Plans: `docs/plans/v0.6.3-refactor-and-audit.md`, `docs/plans/v0.6.3-codex-run-command-fix.md`

**Who does what:**
- **Codex**: all production code changes (system.sh, core.sh, agent_rigor.sh)
- **Gemini**: BATS suite for agent_rigor.bats; verify full suite locally after Codex delivers
- **Claude**: review diffs, run BATS locally, commit, open PR

- [x] Remove `auto_interactive` TTY-detection from `_run_command` (Codex — task: `docs/plans/v0.6.3-codex-run-command-fix.md`)
- [x] Audit `--prefer-sudo` call sites for implicit interactive-sudo dependency (E2E rebuild verified)
- [x] Gemini: Verification tasks (BATS pass 125/125, E2E cluster rebuild, individual smoke tests PASS)
- [x] De-bloat `scripts/lib/core.sh` — collapse permission cascade anti-patterns (Codex) ✅
- [x] De-bloat `scripts/lib/system.sh` — add `_detect_platform` helper (Codex) ✅
- [x] Implement `_agent_lint` + `_agent_audit` in `agent_rigor.sh` (Codex) ✅
- [x] BATS suite: `scripts/tests/lib/agent_rigor.bats` (Gemini) ✅
- [x] Gemini Phase 2: Teardown/Rebuild verification — PASS; found 3 regressions in install_k3s.bats
- [x] Codex: Fix install_k3s.bats regressions A, B, C (task: `docs/plans/v0.6.3-codex-install-k3s-bats-fix.md`)
- [x] Claude: BATS 124/124 PASS, changelog written, PR open

### Priority 2 — v0.6.4

- [ ] Linux k3s validation gate — Gemini runs full 5-phase teardown/rebuild on Ubuntu VM (`ssh ubuntu`, `CLUSTER_PROVIDER=k3s`) to validate refactored `_install_k3s`, `_start_k3s_service`, `_ensure_path_exists`, `_detect_platform`, `_install_docker` under real Linux conditions
- [ ] Create `lib-foundation` repository
- [ ] Extract `core.sh` and `system.sh` via git subtree

### Priority 3 — v0.7.0

- [ ] ESO deploy on Ubuntu app cluster (SSH)
- [ ] shopping-cart-data (PostgreSQL, Redis, RabbitMQ) on Ubuntu
- [ ] shopping-cart-apps (basket, order, payment, catalog, frontend) on Ubuntu
- [ ] Rename infra cluster to `infra`; fix `CLUSTER_NAME` env var

### Priority 4 — v0.8.0

- [ ] `k3dm-mcp` — lean MCP server wrapping k3d-manager CLI
- [ ] Target clients: Claude Desktop, Codex, Atlas, Comet
- [ ] Expose: deploy, destroy, test, unseal as MCP tools

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| GitGuardian: 1 internal secret incident (2026-02-28) | OPEN | False positive — IPs in docs. Mark in dashboard. See `docs/issues/2026-02-28-gitguardian-internal-ip-addresses-in-docs.md`. |
| `CLUSTER_NAME` env var ignored during `deploy_cluster` | OPEN | Cluster created as `k3d-cluster` instead of override value. See `docs/issues/2026-03-01-cluster-name-env-var-not-respected.md`. |
| `deploy_jenkins` (no flags) broken | OPEN | Policy creation always runs; `jenkins-admin` Vault secret absent. Use `--enable-vault`. |
| No `scripts/tests/plugins/jenkins.bats` suite | BACKLOG | `test_auth_cleanup.bats` covers auth flow. Full suite is future work. |
