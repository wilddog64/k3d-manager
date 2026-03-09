# Progress — k3d-manager

## Overall Status

**v0.7.2 SHIPPED** — squash-merged to main (4738fd8), PR #26, 2026-03-08.
**v0.7.3 ACTIVE** — branch `k3d-manager-v0.7.3` cut from main 2026-03-08.

---

## What Is Complete

### Released (v0.1.0 – v0.7.2)

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
- [x] Ubuntu app cluster: ESO 3/3 SecretStores Ready, shopping-cart-data running

---

## What Is Pending

### Priority 1 — v0.7.3 (active)

- [x] Cluster rebuild + pre-commit hook smoke test (Gemini) — `docs/plans/v0.7.3-gemini-rebuild.md`
- [ ] Reusable GitHub Actions workflow (build + Trivy + ghcr.io + kustomize update)
- [ ] Caller workflow in each service repo (basket, order, payment, catalog, frontend)
- [ ] Fix ArgoCD Application CR repoURLs + destination.server (`10.211.55.14:6443`)
- [ ] `shopping_cart.sh` — `add_ubuntu_k3s_cluster` + `register_shopping_cart_apps`
- [ ] Gemini: end-to-end verification (push → ghcr → ArgoCD → pod on Ubuntu)

### Priority 2 — lib-foundation

- [ ] `_run_command` if-count refactor (v0.3.0) — `docs/issues/2026-03-08-run-command-if-count-refactor.md`
- [ ] Sync deploy_cluster fixes upstream (CLUSTER_NAME, provider helpers)
- [ ] Route bare sudo in `_install_debian_helm` / `_install_debian_docker` through `_run_command`
- [ ] Add `.github/copilot-instructions.md` to lib-foundation

### Priority 3 — v0.8.0

- [ ] `k3dm-mcp` — lean MCP server wrapping k3d-manager CLI
- [ ] Expose: deploy, destroy, test, unseal as MCP tools

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| Ubuntu k3s CPU capacity (2 cores) | OPEN | shopping-cart-apps exceed capacity. Fix: replicas=1 in ArgoCD manifests (v0.7.3 Task 3). |
| Shopping Cart Apps ImagePullBackOff | OPEN | Images never pushed — blocked on v0.7.3 CI/CD pipeline. |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround. |
| BATS teardown `k3d-test-orbstack-exists` | FIXED v0.7.2 | `teardown_file()` in provider_contract.bats. |
