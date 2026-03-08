# Progress — k3d-manager

## Overall Status

**v0.7.0 SHIPPED** — squash-merged to main (eb26e43), PR #24, 2026-03-08.
**v0.7.1 ACTIVE** — branch `k3d-manager-v0.7.1` cut from main 2026-03-08.

---

## What Is Complete

### Released (v0.1.0 – v0.7.0)

- [x] k3d/OrbStack/k3s cluster provider abstraction
- [x] Vault PKI, ESO, Istio, Jenkins, OpenLDAP, ArgoCD, Keycloak (infra cluster)
- [x] Active Directory provider (external-only, 36 tests passing)
- [x] Two-cluster architecture (`CLUSTER_ROLE=infra|app`)
- [x] Cross-cluster Vault auth (`configure_vault_app_auth`)
- [x] Agent Rigor Protocol — `_agent_checkpoint`, `_agent_lint`, `_agent_audit`
- [x] `_ensure_copilot_cli` / `_ensure_node` auto-install helpers
- [x] `_k3d_manager_copilot` scoped wrapper (8-fragment deny list, `K3DM_ENABLE_AI` gate)
- [x] `_safe_path` / `_is_world_writable_dir` PATH poisoning defense
- [x] VAULT_TOKEN stdin injection in `ldap-password-rotator.sh`
- [x] `_detect_platform` — single source of truth for OS detection
- [x] `_run_command` TTY flakiness fix
- [x] Linux k3s gate — 5-phase teardown/rebuild on Ubuntu 24.04 VM
- [x] `_agent_audit` hardening — bare sudo detection + kubectl exec credential scan
- [x] Pre-commit hook — `_agent_audit` wired to every commit
- [x] Provider contract BATS suite — 30 tests (3 providers × 10 functions)
- [x] `_agent_audit` awk → pure bash rewrite (bash 3.2+, macOS BSD awk compatible)
- [x] BATS tests for `_agent_audit` bare sudo + kubectl exec — suite 9/9, total 158/158
- [x] `lib-foundation` repo created + subtree pulled into `scripts/lib/foundation/`
- [x] `deploy_cluster` refactored — 12→5 if-blocks, helpers extracted (Codex)
- [x] `CLUSTER_NAME` env var propagated to provider (Codex)
- [x] `eso-ldap-directory` Vault role binds `directory` + `identity` namespaces (Codex)
- [x] OrbStack + Ubuntu k3s validation — 158/158 BATS, all services healthy (v0.7.0)

---

## What Is Pending

### Priority 1 — v0.7.1 (active)

- [ ] Drop colima support — remove `_install_colima`, `_install_mac_docker`, update `_install_docker` mac case, clean README (Codex — Task 1)
- [ ] Fix BATS test teardown — `k3d-test-orbstack-exists` cluster left behind after tests
- [ ] ESO deploy on Ubuntu app cluster
- [ ] shopping-cart-data (PostgreSQL, Redis, RabbitMQ) on Ubuntu
- [ ] shopping-cart-apps (basket, order, payment, catalog, frontend) on Ubuntu

### Priority 2 — lib-foundation upstream

- [ ] Sync deploy_cluster fixes back into lib-foundation (CLUSTER_NAME, provider helpers, duplicate guard removal)
- [ ] Route bare sudo in `_install_debian_helm` / `_install_debian_docker` through `_run_command`
- [ ] Push tag v0.1.1 to remote

### Priority 3 — v0.8.0

- [ ] `k3dm-mcp` — lean MCP server wrapping k3d-manager CLI
- [ ] Target clients: Claude Desktop, Codex, Atlas, Comet
- [ ] Expose: deploy, destroy, test, unseal as MCP tools

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| BATS test teardown — `k3d-test-orbstack-exists` | OPEN | Holds ports 8000/8443 on next deploy. Issue: `docs/issues/2026-03-07-k3d-rebuild-port-conflict-test-cluster.md`. Gemini — v0.7.1. |
| inotify limit in colima VM | CLOSED — colima support being dropped in v0.7.1 | N/A |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround. |
| No `scripts/tests/plugins/jenkins.bats` suite | BACKLOG | Future work. |
