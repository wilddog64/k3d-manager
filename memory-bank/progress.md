# Progress — k3d-manager

## Overall Status

**v0.8.0 SHIPPED** — squash-merged to main (aaf2aee), PR #28, 2026-03-13. Tagged + released.
**v0.9.0 SHIPPED** — squash-merged to main (616d868), PR #30, 2026-03-15. Tagged + released.
**v0.9.1 ACTIVE** — branch `k3d-manager-v0.9.1` cut from main 2026-03-15.

---

## What Is Complete

### Released (v0.1.0 – v0.8.0)

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
- [x] Vault-managed ArgoCD deploy keys — `configure_vault_argocd_repos` + 6 helper refactors; BATS 8/8 (v0.8.0)
- [x] `deploy_cert_manager` plugin — cert-manager v1.20.0 + ACME HTTP-01 via Istio; BATS 10/10; live cluster verify PASS (v0.8.0)
- [x] `istio-ingressclass.yaml` — auto-applied by `_provider_k3d_configure_istio`; BATS 4/4 (v0.8.0)
- [x] `scripts/hooks/install-hooks.sh` — symlink tracked pre-commit hook; M4 Air verified (v0.8.0)
- [x] `docs/api/functions.md` — full public functions reference added (v0.8.0)

### Shopping Cart Ecosystem (orchestrated from k3d-manager, code in shopping-cart-* repos)

- [x] CI stabilization — all 5 repos merged to main 2026-03-14
- [x] Branch protection — applied to all 5 repos 2026-03-14
- [x] P4 linters — basket (golangci-lint), product-catalog (ruff+mypy), order (Checkstyle+OWASP), payment (Checkstyle+SpotBugs) — all merged 2026-03-14
- [x] v0.1.0 releases — all 6 repos (basket, product-catalog, order, payment, frontend, infra) — shipped 2026-03-14

---

## What Is Pending

### v0.9.1 — active

- [x] `AGENTS.md` — agent session rules (read memory-bank, proof of work, no-revert, scope discipline)
- [x] vCluster plugin spec — `docs/plans/v0.9.1-vcluster-plugin.md` (decisions recorded: v0.32.1, k8s distro, --print kubeconfig, 500m/512Mi limits)
- [x] Codex task spec — `docs/plans/v0.9.1-vcluster-codex-task.md` (DoD checklist, do-not-do list)
- [x] vCluster plugin implementation — `scripts/plugins/vcluster.sh` + `scripts/etc/vcluster/values.yaml` + `scripts/tests/plugins/vcluster.bats` — **Codex** (commit `6020fc4c88df520c98d971051a415b1f40fe6edf`, PR pending; `bats scripts/tests/plugins/vcluster.bats` 8/8, `env -i ... bats` 8/8, `shellcheck scripts/plugins/vcluster.sh` clean, `AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh scripts/plugins/vcluster.sh` PASS)
- [ ] Playwright E2E in CI — `shopping-cart-infra` — starts after vCluster plugin ships

### Next after v0.9.1 — k3dm-mcp v1.0.0

- Separate repo `~/src/gitrepo/personal/k3dm-mcp`

### lib-foundation Backlog

- [ ] `_run_command` if-count refactor (v0.3.0) — `docs/issues/2026-03-08-run-command-if-count-refactor.md`
- [ ] Sync `deploy_cluster` fixes upstream (CLUSTER_NAME, provider helpers)
- [ ] Route bare sudo in `_install_debian_helm` / `_install_debian_docker`
- [ ] Add `.github/copilot-instructions.md` to lib-foundation

### Deferred

- [ ] Playwright MCP E2E testing (v0.8.1) — prerequisite: images in ghcr.io + services running
- [ ] Google Antigravity ACG sandbox (v1.1.0) — login + credential extraction via browser automation
- [ ] M2 Air pre-commit hook — SSH key not loaded; fix: `ssh-add` then re-run `install-hooks.sh`
- [ ] Ubuntu pre-commit hook — checkout v0.9.0 + run `install-hooks.sh`

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| Shopping Cart Apps ImagePullBackOff | OPEN | Images not pushed to ghcr.io — CI stabilization complete but images not yet built |
| Ubuntu k3s CPU capacity (2 cores) | OPEN | shopping-cart-apps may exceed capacity — reduce replicas in ArgoCD manifests |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround |
| NVD API key missing | OPEN | Register at nvd.nist.gov — add as `NVD_API_KEY` secret to order + payment repos |
