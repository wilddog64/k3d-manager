# Progress – k3d-manager

## Overall Status

**v0.6.3 SHIPPED** — tag `v0.6.3` pushed, PR #21 merged 2026-03-07.
**v0.6.4 ACTIVE** — branch `k3d-manager-v0.6.4` cut from main 2026-03-07.

---

## What Is Complete

### Released (v0.1.0 – v0.6.3)

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
- [x] Permission cascade elimination in `core.sh` — single `_run_command --prefer-sudo`
- [x] `_detect_platform` — single source of truth for OS detection in `system.sh`
- [x] `_run_command` TTY flakiness fix — `auto_interactive` block removed
- [x] `.github/copilot-instructions.md` — shaped Copilot PR reviews
- [x] BATS suites: 124/124 passing

---

## What Is Pending

### Priority 1 — v0.6.4 (active)

- [x] Linux k3s validation gate — Gemini full 5-phase teardown/rebuild on Ubuntu VM (124/124 BATS pass, Smoke tests PASS)
- [x] Fix `_install_bats_from_source` default `1.10.0` → `1.11.0` + robust URL (Gemini)
- [x] `_agent_audit` hardening — bare sudo detection + credential pattern check in `kubectl exec` args (Codex)
- [x] Pre-commit hook — wire `_agent_audit` to `.git/hooks/pre-commit` (Codex)
- [x] Contract BATS tests — provider interface enforcement (Gemini) (154/154 pass)
- [ ] Create `lib-foundation` repository (owner action)
- [ ] Extract `core.sh` and `system.sh` via git subtree (Codex)

### Priority 2 — v0.7.0

- [ ] ESO deploy on Ubuntu app cluster (SSH)
- [ ] shopping-cart-data (PostgreSQL, Redis, RabbitMQ) on Ubuntu
- [ ] shopping-cart-apps (basket, order, payment, catalog, frontend) on Ubuntu
- [ ] Rename infra cluster to `infra`; fix `CLUSTER_NAME` env var
- [ ] Keycloak provider interface

### Priority 3 — v0.8.0

- [ ] `k3dm-mcp` — lean MCP server wrapping k3d-manager CLI
- [ ] Target clients: Claude Desktop, Codex, Atlas, Comet
- [ ] Expose: deploy, destroy, test, unseal as MCP tools

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| GitGuardian: 1 internal secret incident (2026-02-28) | OPEN | False positive — IPs in docs. Mark in dashboard. |
| `CLUSTER_NAME` env var ignored during `deploy_cluster` | OPEN | See `docs/issues/2026-03-01-cluster-name-env-var-not-respected.md`. |
| `deploy_jenkins` (no flags) broken | OPEN | Use `--enable-vault` as workaround. |
| No `scripts/tests/plugins/jenkins.bats` suite | BACKLOG | Future work. |
