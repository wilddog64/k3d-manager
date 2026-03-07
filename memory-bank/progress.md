# Progress – k3d-manager

## Overall Status

**v0.6.4 SHIPPED** — tag `v0.6.4` pushed, PR #22 merged 2026-03-07.
**v0.6.5 ACTIVE** — branch `k3d-manager-v0.6.5` cut from main 2026-03-07.

---

## What Is Complete

### Released (v0.1.0 – v0.6.4)

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
- [x] Permission cascade elimination in `core.sh`
- [x] `_detect_platform` — single source of truth for OS detection
- [x] `_run_command` TTY flakiness fix
- [x] Linux k3s gate — 5-phase teardown/rebuild on Ubuntu 24.04 VM
- [x] BATS source install 404 fix — 1.10.0 → 1.13.0, archive URL
- [x] `_agent_audit` hardening — bare sudo detection + kubectl exec credential scan
- [x] Pre-commit hook — `_agent_audit` wired to every commit
- [x] Provider contract BATS suite — 30 tests (3 providers × 10 functions)
- [x] `_provider_orbstack_expose_ingress` missing function added
- [x] Copilot P1/P2 fixes — `git diff --cached`, diff-based sudo scan, `\b` pattern
- [x] BATS suite: 154/154 passing

---

## What Is Pending

### Priority 1 — v0.6.5 (active)

- [ ] BATS tests for `_agent_audit` new checks — bare sudo + kubectl exec (Gemini)
- [x] Create `lib-foundation` repository + branch protection + CI (owner) — https://github.com/wilddog64/lib-foundation
- [ ] Extract `core.sh` + `system.sh` via git subtree (Codex)

### Priority 2 — v0.7.0

- [ ] ESO deploy on Ubuntu app cluster
- [ ] shopping-cart-data (PostgreSQL, Redis, RabbitMQ) on Ubuntu
- [ ] shopping-cart-apps (basket, order, payment, catalog, frontend) on Ubuntu
- [ ] `CLUSTER_NAME` env var respected during `deploy_cluster`
- [ ] Keycloak provider interface

### Priority 3 — v0.8.0

- [ ] `k3dm-mcp` — lean MCP server wrapping k3d-manager CLI
- [ ] Target clients: Claude Desktop, Codex, Atlas, Comet
- [ ] Expose: deploy, destroy, test, unseal as MCP tools

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| GitGuardian: 1 internal secret incident (2026-02-28) | OPEN | False positive — mark in dashboard. |
| `CLUSTER_NAME` env var ignored during `deploy_cluster` | OPEN | See `docs/issues/2026-03-01-cluster-name-env-var-not-respected.md`. |
| `deploy_jenkins` (no flags) broken | OPEN | Use `--enable-vault` as workaround. |
| No `scripts/tests/plugins/jenkins.bats` suite | BACKLOG | Future work. |
