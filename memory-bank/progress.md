# Progress — k3d-manager

## Overall Status

**v0.8.0 SHIPPED** — squash-merged to main (aaf2aee), PR #28, 2026-03-13. Tagged + released.
**v0.9.0 ACTIVE** — branch `k3d-manager-v0.9.0` cut from main 2026-03-13.

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

---

## What Is Pending

### Priority 1 — v0.9.0 (active)

**Shopping Cart CI Stabilization:**
- Status source of truth: `wilddog64/shopping-cart-infra` memory-bank (`activeContext.md` + `progress.md`).
- Current spec: `docs/plans/ci-stabilization-round3.md` (c5797539).
- Active PRs (all on `fix/ci-stabilization`):
  - `rabbitmq-client-java` PR #1 — ✅ MERGED to main 2026-03-14
  - `shopping-cart-order` PR #1 — ✅ MERGED to main 2026-03-14
  - `shopping-cart-product-catalog` PR #1 — ✅ MERGED to main 2026-03-14
  - `shopping-cart-payment` PR #1 — ✅ MERGED to main 2026-03-14
  - `shopping-cart-frontend` PR #1 — ✅ MERGED to main 2026-03-14. Copilot reviewed — no comments.
- **Branch protection** — ✅ applied to all 5 repos 2026-03-14 (1 review + CI required)
- **P4 linters** — ✅ ALL MERGED to main 2026-03-14:
  - basket: merged PR #1 (golangci-lint)
  - product-catalog: merged PR #2 (ruff + mypy)
  - order: merged PR #2 (Checkstyle + OWASP)
  - payment: merged PR #2 (Checkstyle + SpotBugs)
- **Next:** v0.1.0 release branches on all 6 repos

**lib-foundation Backlog:**
- [ ] `_run_command` if-count refactor (v0.3.0) — `docs/issues/2026-03-08-run-command-if-count-refactor.md`
- [ ] Sync `deploy_cluster` fixes upstream (CLUSTER_NAME, provider helpers)
- [ ] Route bare sudo in `_install_debian_helm` / `_install_debian_docker`
- [ ] Add `.github/copilot-instructions.md` to lib-foundation

**k3dm-mcp:** separate repo (`~/src/gitrepo/personal/k3dm-mcp`) — active after v0.8.0 ships.

### Priority 2 — Deferred

- [ ] **Playwright MCP E2E testing (v0.8.1)** — prerequisite: CI green → images in ghcr.io → services running
- [ ] **Google Antigravity ACG sandbox (v1.0.0)** — login + credential extraction via browser automation

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| ArgoCD Cluster Registration Timeout | FIXED v0.7.3 | Root cause: infra on M4 Air had no route to Ubuntu. Fixed by rebuilding infra on M2 Air. |
| Shopping Cart Apps ImagePullBackOff | OPEN | CI/CD failing — images not being pushed to ghcr.io. Blocked by CI failures below. |
| Shopping Cart CI — Trivy install failure | OPEN P1 | basket + product-catalog: custom install script fails. Fix: use trivy-action in infra workflow. |
| Shopping Cart CI — Frontend lint/type errors | OPEN P1 | PR #1 removes imports + adds vite/client types; lint now fails on pre-existing `react-refresh/only-export-components` warnings in Badge/Button/test-utils (needs decision). |
| Shopping Cart CI — Payment mvnw init | OPEN P2 | `MAVEN_OPTS` now sets `-Dmaven.multiModuleProjectDirectory`, wrapper boots, but build stops earlier because `org.flywaydb:flyway-database-postgresql` lacks a version (pom line 68). |
| Shopping Cart CI — Order missing rabbitmq-client | OPEN P2 | Publish/RPM PRs open; order CI still failing until rabbitmq-client-java PR merges and publishes to GitHub Packages. |
| Ubuntu k3s CPU capacity (2 cores) | OPEN | shopping-cart-apps may exceed capacity — reduce replicas in ArgoCD manifests. |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround. |
| M2 Air pre-commit hook | OPEN | SSH key not loaded. Fix: `ssh-add` then re-run `install-hooks.sh`. |
| Ubuntu pre-commit hook | OPEN | Was on wrong branch. Fix: checkout v0.9.0 + run `install-hooks.sh`. |
