# Progress — k3d-manager

## Overall Status

**v0.9.2 SHIPPED** — squash-merged to main (f0cec06), PR #35, 2026-03-15. Tagged + released.
**v0.9.3 ACTIVE** — branch cut from main 2026-03-15.

---

## What Is Complete

### Released (v0.1.0 – v0.9.2)

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
- [x] `shopping_cart.sh` plugin — `add_ubuntu_k3s_cluster` + `register_shopping_cart_apps` (v0.7.3)
- [x] Reusable GitHub Actions CI/CD workflow — build + Trivy + ghcr.io push + kustomize update (v0.7.3)
- [x] ArgoCD: `ubuntu-k3s` registered, all 5 shopping-cart apps Synced (v0.7.3)
- [x] Vault-managed ArgoCD deploy keys — `configure_vault_argocd_repos` (v0.8.0)
- [x] `deploy_cert_manager` plugin — cert-manager v1.20.0 + ACME HTTP-01 via Istio (v0.8.0)
- [x] `docs/api/functions.md` — full public functions reference (v0.8.0)
- [x] Shopping Cart ecosystem — CI stabilized, branch protection, P4 linters, v0.1.0 releases (2026-03-14)
- [x] vCluster plugin — `create/destroy/use/list`, Helm values, BATS 8/8 (v0.9.1)
- [x] Two-tier help — bare summary, `--help` full list (v0.9.1)
- [x] `function test()` refactor — moved to dispatcher, if-count compliant (v0.9.1)
- [x] vCluster E2E composite actions — setup + teardown (v0.9.2)
- [x] 11-finding Copilot hardening — curl safety, mktemp TOCTOU, sudo -n, TAG env, input validation, action_path, teardown deps (v0.9.2)

---

## What Is Pending

### v0.9.3 — active

- [ ] Next milestone TBD
- [ ] Playwright E2E in CI — `shopping-cart-infra` — blocked on ImagePullBackOff

### Next after v0.9.x — k3dm-mcp v1.0.0

- Separate repo `~/src/gitrepo/personal/k3dm-mcp`

### lib-foundation Backlog

- [ ] `_run_command` if-count refactor (v0.3.0) — `docs/issues/2026-03-08-run-command-if-count-refactor.md`
- [ ] Sync `deploy_cluster` fixes upstream (CLUSTER_NAME, provider helpers)
- [ ] Route bare sudo in `_install_debian_helm` / `_install_debian_docker`
- [ ] Add `.github/copilot-instructions.md` to lib-foundation

### Deferred

- [ ] Playwright MCP E2E testing — prerequisite: images in ghcr.io + services running
- [ ] Google Antigravity ACG sandbox (v1.1.0)
- [ ] M2 Air pre-commit hook — SSH key not loaded; fix: `ssh-add` then re-run `install-hooks.sh`
- [ ] Ubuntu pre-commit hook — run `install-hooks.sh`

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| Shopping Cart Apps ImagePullBackOff | OPEN | Images not pushed to ghcr.io — CI stabilized but images not yet built |
| Ubuntu k3s CPU capacity (2 cores) | OPEN | shopping-cart-apps may exceed capacity — reduce replicas |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround |
| NVD API key missing | OPEN | Register at nvd.nist.gov — add as `NVD_API_KEY` secret to order + payment repos |
