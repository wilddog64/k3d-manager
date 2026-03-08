# Progress — k3d-manager

## Overall Status

**v0.7.1 SHIPPED** — squash-merged to main (e847064), PR #25, 2026-03-08. Colima support dropped.
**v0.7.2 ACTIVE** — branch `k3d-manager-v0.7.2` cut from main 2026-03-08.

---

## What Is Complete

### Released (v0.1.0 – v0.7.1)

- [x] k3d/OrbStack/k3s cluster provider abstraction
- [x] Vault PKI, ESO, Istio, Jenkins, OpenLDAP, ArgoCD, Keycloak (infra cluster)
- [x] Two-cluster architecture (`CLUSTER_ROLE=infra|app`)
- [x] Cross-cluster Vault auth (`configure_vault_app_auth`)
- [x] Agent Rigor Protocol — `_agent_checkpoint`, `_agent_lint`, `_agent_audit`
- [x] `_ensure_copilot_cli` / `_ensure_node` auto-install helpers
- [x] `_k3d_manager_copilot` scoped wrapper (`K3DM_ENABLE_AI` gate, 8-fragment deny list)
- [x] `_safe_path` / `_is_world_writable_dir` PATH poisoning defense
- [x] `lib-foundation` subtree at `scripts/lib/foundation/` (v0.1.2)
- [x] `deploy_cluster` refactored — 12→5 if-blocks, CLUSTER_NAME fix
- [x] `eso-ldap-directory` Vault role binds `directory` + `identity` namespaces
- [x] OrbStack + Ubuntu k3s validation — 158/158 BATS, all services healthy
- [x] Colima support dropped — OrbStack is the macOS Docker runtime (v0.7.1)
- [x] `_install_docker` mac case — fail-fast with clear message if Docker absent

### v0.7.2 (in progress)
- [x] `.envrc` → `~/.zsh/envrc/k3d-manager.envrc` symlink (dotfiles-managed)
- [x] `scripts/hooks/pre-commit` — tracked hook (`_agent_audit` always + `_agent_lint` when `K3DM_ENABLE_AI=1`)

---

## What Is Pending

### Priority 1 — v0.7.2 (active)

- [ ] Fix BATS test teardown — `k3d-test-orbstack-exists` cluster left behind after tests (Gemini)
- [x] ESO deploy on Ubuntu app cluster (Gemini — verified 3/3 SecretStores Ready)
- [ ] shopping-cart-data / apps deployment on Ubuntu (🔄 Data layer PASS; apps BLOCKED)

### Priority 2 — lib-foundation

- [x] v0.2.0 — `agent_rigor.sh` — merged PR #4, tagged, subtree synced into k3d-manager
- [x] `k3d-manager.envrc` — `AGENT_LINT_GATE_VAR=K3DM_ENABLE_AI`, `AGENT_LINT_AI_FUNC=_k3d_manager_copilot`, `AGENT_AUDIT_MAX_IF=15`
- [ ] Sync deploy_cluster fixes back into lib-foundation (CLUSTER_NAME, provider helpers)
- [ ] Route bare sudo in `_install_debian_helm` / `_install_debian_docker` through `_run_command`
- [ ] `_run_command` if-count refactor (v0.3.0) — see `docs/issues/2026-03-08-run-command-if-count-refactor.md`
- [ ] Add `.github/copilot-instructions.md` to lib-foundation (v0.2.1 or v0.3.0)

### Priority 3 — v0.7.3 (planned)

- [ ] Reusable GitHub Actions workflow (build + Trivy scan + push ghcr.io + update kustomization)
- [ ] Caller workflow in each service repo (basket, order, payment, catalog, frontend)
- [ ] Fix ArgoCD Application CR repoURLs (placeholder → real GitHub URLs)
- [ ] `register_shopping_cart_apps` in k3d-manager (`scripts/plugins/shopping_cart.sh`)
- [ ] Gemini: end-to-end verification (push → image in ghcr → ArgoCD → pod on Ubuntu)
- [ ] Resolve open questions: ArgoCD location, ghcr visibility, CPU capacity

### Priority 4 — v0.8.0

- [ ] `k3dm-mcp` — lean MCP server wrapping k3d-manager CLI
- [ ] Target clients: Claude Desktop, Codex, Atlas, Comet
- [ ] Expose: deploy, destroy, test, unseal as MCP tools

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| BATS test teardown — `k3d-test-orbstack-exists` | OPEN | Holds ports 8000/8443 on next deploy. Issue: `docs/issues/2026-03-07-k3d-rebuild-port-conflict-test-cluster.md`. Gemini — v0.7.2. |
| Ubuntu k3s CPU capacity (2 cores) reached | OPEN | Data layer + apps exceeds 2.0 CPU requests. Requires ns scale-down. |
| Shopping Cart Apps ImagePullBackOff | OPEN | Kustomize manifests reference `shopping-cart/*:latest` images missing on Ubuntu. |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround. |
| No `scripts/tests/plugins/jenkins.bats` suite | BACKLOG | Future work. |
