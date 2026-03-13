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

- [x] Vault-managed ArgoCD deploy keys — committed `7785033` on `k3d-manager-v0.8.0`
  - `configure_vault_argocd_repos` + 6 helper refactors; BATS 8/8; shellcheck clean; all functions ≤ 8 ifs
- [x] `deploy_cert_manager` plugin — Helm install + ACME issuers with Istio HTTP-01 gateway (awaiting git add permission)
  - Spec: `docs/plans/v0.8.0-cert-manager.md`; artifacts: `shellcheck scripts/plugins/cert-manager.sh`; `env -i HOME="$HOME" PATH="$PATH" bats scripts/tests/plugins/cert_manager.bats` → 10/10; `AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh` ✅
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

### Priority 1b — Shopping Cart CI Stabilization (v0.8.0 milestone)

All 5 service repos have failing CI Publish jobs since 2026-03-09.
Full details: `docs/issues/2026-03-11-shopping-cart-ci-failures.md`

**P1 — Fix immediately (unblocks 3 of 5 services):**
- [ ] `shopping-cart-basket` + `shopping-cart-product-catalog` — Replace custom Trivy install script with `aquasecurity/trivy-action@0.30.0` in `shopping-cart-infra/.github/workflows/build-push-deploy.yml`; update pinned commit hash in both caller workflows
- [ ] `shopping-cart-frontend` — Remove unused imports (Header.tsx, ProtectedRoute.tsx, cartStore.ts); add `"types": ["vite/client"]` to `tsconfig.json`

**P2 — Fix to complete the pipeline:**
- [ ] `shopping-cart-payment` — Verify `mvnw` + `.mvn/wrapper/maven-wrapper.properties` committed; add `-Dmaven.multiModuleProjectDirectory=.` to CI Maven command if needed
- [ ] `shopping-cart-order` — Publish `rabbitmq-client-java` to GitHub Packages, or restructure as multi-module Maven project, or add CI step to build+install before order service build

**P3 — Enforce after CI is green (all 5 repos):**
- [ ] Branch protection on all 5 shopping-cart repos via `gh api` script (must do after CI is green so required status checks have a passing job to reference):
  - Require PR before merging to `main` (no direct push)
  - Require status checks to pass: CI build + test job (per-repo job name)
  - Require branches to be up to date before merging
  - Dismiss stale reviews on new commits
  - No force push, no branch deletion
  - Script location: `scripts/plugins/shopping_cart.sh` → new function `configure_shopping_cart_branch_protection`

**P4 — Add missing linters after CI is green (copilot-instructions enforcement):**
- [ ] `shopping-cart-basket` — Add `golangci-lint` + `go vet` to `go-ci.yml` (currently only `go test` runs — no static analysis)
- [ ] `shopping-cart-order` — Add Checkstyle + OWASP dependency check to `ci.yml` (payment has OWASP, order does not)
- [ ] `shopping-cart-product-catalog` — Add `ruff check`, `mypy`, `black --check` to `ci.yml` (none of the required linters are currently enforced)
- [ ] `shopping-cart-payment` — Add Checkstyle/SpotBugs (OWASP already present; mvnw fix is P2 prerequisite)
- (frontend already enforces ESLint + Prettier + `tsc --noEmit` — no gap once P1 fix applied)

### Priority 3 — Shopping Cart Hygiene

- [ ] **Playwright MCP: E2E testing (deferred to v0.8.1 — services must be running first)**
  - Prerequisite chain: CI green → images in ghcr.io → ArgoCD syncs → services running → branch protection on → then E2E
  - Design: `@playwright/mcp` runs on dev machine (outside cluster); browser connects to services via `port-forward.sh` or Istio ingress; driven by Claude/Copilot/Gemini CLI via MCP tool calls
  - Tests live in `shopping-cart-e2e-tests/` repo (already has Playwright structure + flow specs)
  - No Chrome-in-cluster needed — simpler, no resource pressure on Ubuntu k3s node
  - Copilot already has Playwright MCP built in — zero extra setup required
  - M5 Mac mini (Oct 2026): revisit parallel test execution when hardware upgrades
- [ ] **Google Antigravity: ACG sandbox login + credential extraction (v1.0.0 — not v0.8.x)**
  - Scope: third-party UI automation only — ACG has no API, browser is the only way in
  - Job: login to ACG web UI, start sandbox, extract cloud credentials + expiry time → hand off to k3dm-mcp
  - Does NOT do shopping-cart testing — Playwright MCP owns that

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| ArgoCD Cluster Registration Timeout | FIXED v0.7.3 | Root cause: infra on M4 Air had no route to Ubuntu. Fixed by rebuilding infra on M2 Air. |
| Shopping Cart Apps ImagePullBackOff | OPEN | CI/CD failing — images not being pushed to ghcr.io. Blocked by CI failures below. |
| Shopping Cart CI — Trivy install failure | OPEN P1 | basket + product-catalog: custom install script fails. Fix: use trivy-action in infra workflow. |
| Shopping Cart CI — Frontend lint/type errors | OPEN P1 | Unused imports + missing vite/client types. Fix: remove imports, update tsconfig. |
| Shopping Cart CI — Payment mvnw init | OPEN P2 | Maven wrapper fails to initialize. Fix: verify mvnw committed, set multiModuleProjectDirectory. |
| Shopping Cart CI — Order missing rabbitmq-client | OPEN P2 | `rabbitmq-client:1.0.0-SNAPSHOT` not in any Maven repo. Fix: publish to GitHub Packages. |
| Ubuntu k3s CPU capacity (2 cores) | OPEN | shopping-cart-apps may exceed capacity — reduce replicas in ArgoCD manifests. |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround. |
| BATS teardown `k3d-test-orbstack-exists` | FIXED v0.7.2 | `teardown_file()` in provider_contract.bats. |
