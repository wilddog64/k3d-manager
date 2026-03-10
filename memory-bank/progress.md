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
- [x] Reusable GitHub Actions workflow (build + Trivy + ghcr.io + kustomize update) — Codex, commit 0a28d10
- [x] Caller workflow in each service repo (basket, order, payment, catalog, frontend) — Codex, commits eaa592f/c086e09/96c9c05/e220ac4
- [x] Fix ArgoCD Application CR repoURLs + destination.server (`10.211.55.14:6443`) — Codex, commit 9066bd3
- [x] `shopping_cart.sh` — `add_ubuntu_k3s_cluster` + `register_shopping_cart_apps` — Codex, plugin + dispatcher
- [x] Trivy restore + repin all 5 service repos — Codex, commit 981008c
- [ ] Gemini: end-to-end verification — CI PASS; ArgoCD sync BLOCKED (gRPC transport issues)
- [x] Gemini: Task 8 — Fix k3s API SAN + re-register cluster (Verified SAN already present)
- [x] Gemini: Task 9 — ArgoCD gRPC diagnostics (MTU / source IP / iptables) (PASS — root cause identified)
- [x] Gemini: Re-trigger CI with Trivy restored + investigate ArgoCD connectivity (PASS)

### Priority 2 — lib-foundation

- [ ] `_run_command` if-count refactor (v0.3.0) — `docs/issues/2026-03-08-run-command-if-count-refactor.md`
- [ ] Sync deploy_cluster fixes upstream (CLUSTER_NAME, provider helpers)
- [ ] Route bare sudo in `_install_debian_helm` / `_install_debian_docker` through `_run_command`
- [ ] Add `.github/copilot-instructions.md` to lib-foundation

### Priority 2b — Shopping Cart Repo Hygiene (post v0.7.3 or v0.7.4)

- [ ] Branch protection on all shopping-cart repos (`main`): require PR, required status checks (CI must pass), dismiss stale reviews, no force push, no deletion
  - Automate via `gh api` script — 5+ repos makes manual UI setup impractical
  - Do after Codex completes v0.7.3 Tasks 2–5 (CI workflows must exist before status checks can be required)

### Priority 2c — Shopping Cart E2E Testing (future)

- [ ] **Google Antigravity** — browser agent for UI E2E testing of shopping-cart-frontend
  - Replaces manual Playwright/Selenium — natural language test specs
  - Applicable once frontend is deployed + stable on Ubuntu k3s
  - Use cases: login flow, cart operations, checkout, item catalog browsing
  - Complements BATS suite: BATS covers infra layer, Antigravity covers UI layer
  - Open questions: auth session handling, Vault-managed credentials, reliability at scale
  - Reference: https://dev.to/thamindudev/no-qa-no-problem-replacing-manual-testing-with-google-antigravity-agents-5c7p

### Priority 3 — v0.8.0

- [ ] `k3dm-mcp` — lean MCP server wrapping k3d-manager CLI
- [ ] Expose: deploy, destroy, test, unseal as MCP tools
- [ ] SQLite state cache — pre-aggregate cluster state, never dump raw kubectl output to LLM
  - Two-phase: sync (on deploy/destroy/unseal) + query (cluster_status reads SQLite only)
  - Every response includes `last_synced_at` + `stale: true` flag if beyond `K3DM_MCP_CACHE_TTL`
  - Full decision: `docs/plans/roadmap-v1.md` → v0.8.0 Context Architecture section
- [ ] Destructive operation controls — blast radius classification, dry-run gate, pre-destroy snapshot, independent confirmation per call
  - Motivated by real AI+Terraform incident (production DB + snapshots deleted, no recovery)
  - Full decision: `docs/plans/roadmap-v1.md` → v0.8.0 Destructive Operation Controls section

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| ArgoCD Cluster Registration Timeout | OPEN | Local Mac cannot reach Ubuntu 6443 API via direct or tunnel. Blocks GitOps sync. |
| Ubuntu k3s CPU capacity (2 cores) | OPEN | shopping-cart-apps exceed capacity. Fix: replicas=1 in ArgoCD manifests (v0.7.3 Task 3). |
| Shopping Cart Apps ImagePullBackOff | OPEN | Images never pushed — blocked on v0.7.3 CI/CD pipeline. |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround. |
| BATS teardown `k3d-test-orbstack-exists` | FIXED v0.7.2 | `teardown_file()` in provider_contract.bats. |
