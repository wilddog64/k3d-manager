# Progress — k3d-manager

## Overall Status

**v0.7.3 SHIPPED** — squash-merged to main (9bca648), PR #27, 2026-03-11. Tagged + released.
**v0.8.0 ACTIVE** — branch `k3d-manager-v0.8.0` cut from main 2026-03-11.

---

## What Is Complete

### Released (v0.1.0 – v0.7.3)

- [x] k3d/OrbStack/k3s cluster provider abstraction
- [x] Vault PKI, ESO, Istio, Jenkins, OpenLDAP, ArgoCD, Keycloak (infra cluster)
- [x] Two-cluster architecture (`CLUSTER_ROLE=infra|app`)
- [x] Cross-cluster Vault auth (`configure_vault_app_auth`)
- [x] Agent Rigor Protocol — `_agent_checkpoint`, `_agent_lint`, `_agent_audit`
- [x] `_k3d_manager_copilot` scoped wrapper (`K3DM_ENABLE_AI` gate, 8-fragment deny list)
- [x] `_safe_path` / `_is_world_writable_dir` PATH poisoning defense
- [x] `lib-foundation` subtree at `scripts/lib/foundation/` (v0.2.0)
- [x] `deploy_cluster` refactored — 12→5 if-blocks, CLUSTER_NAME fix
- [x] OrbStack + Ubuntu k3s validation — all services healthy
- [x] Colima support dropped (v0.7.1)
- [x] `.envrc` → dotfiles symlink, `scripts/hooks/pre-commit` tracked hook (v0.7.2)
- [x] `_agent_audit` — bare sudo, if-count, BATS removal, kubectl exec credential checks
- [x] CI: bats pinned to v1.11.0, subtree guard with `K3DM_SUBTREE_SYNC=1` bypass
- [x] Ubuntu app cluster: ESO SecretStores Ready, shopping-cart-data running
- [x] `shopping_cart.sh` plugin — `add_ubuntu_k3s_cluster` + `register_shopping_cart_apps` (v0.7.3)
- [x] Reusable GitHub Actions CI/CD workflow — build + Trivy + ghcr.io push + kustomize update (v0.7.3)
- [x] ArgoCD: `ubuntu-k3s` registered, all 5 shopping-cart apps Synced (v0.7.3)
- [x] Infra cluster rebuilt on M2 Air — ArgoCD→Ubuntu connectivity fixed (v0.7.3)

---

## What Is Pending

### Priority 1 — v0.8.0 (active)

- [ ] Vault-managed ArgoCD deploy keys — `configure_vault_argocd_repos`; ESO syncs from Vault KV → `cicd` ns secrets
- [ ] `deploy_cert_manager` plugin — cert-manager + ACME for external certs (SC-081 readiness)
- [ ] lib-foundation v0.3.0 — `_run_command` if-count refactor
- [ ] lib-foundation — sync `deploy_cluster` fixes upstream (CLUSTER_NAME, provider helpers)
- [ ] lib-foundation — route bare sudo in `_install_debian_helm` / `_install_debian_docker`
- [ ] Shopping cart branch protection — automate via `gh api` across 5 repos

**k3dm-mcp:** separate repo (`~/src/gitrepo/personal/k3dm-mcp`) — starts after v0.8.0 ships.

### Priority 2 — lib-foundation backlog

- [ ] `_run_command` if-count refactor (v0.3.0) — `docs/issues/2026-03-08-run-command-if-count-refactor.md`
- [ ] Sync deploy_cluster fixes upstream (CLUSTER_NAME, provider helpers)
- [ ] Route bare sudo in `_install_debian_helm` / `_install_debian_docker` through `_run_command`
- [ ] Add `.github/copilot-instructions.md` to lib-foundation

### Priority 3 — Shopping Cart Hygiene

- [ ] Branch protection on all 5 shopping-cart repos — automate via `gh api` script
- [ ] Google Antigravity: shopping-cart-frontend E2E testing (once frontend stable)
- [ ] Google Antigravity: ACG sandbox login + credential extraction (v1.0.0)

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| ArgoCD Cluster Registration Timeout | FIXED v0.7.3 | Root cause: infra on M4 Air had no route to Ubuntu. Fixed by rebuilding infra on M2 Air. |
| Shopping Cart Apps ImagePullBackOff | OPEN | Images not yet pushed — CI/CD pipeline exists but no push trigger yet. |
| Ubuntu k3s CPU capacity (2 cores) | OPEN | shopping-cart-apps may exceed capacity — reduce replicas in ArgoCD manifests. |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround. |
| BATS teardown `k3d-test-orbstack-exists` | FIXED v0.7.2 | `teardown_file()` in provider_contract.bats. |
