# Progress – k3d-manager

## Overall Status

`ldap-develop` merged to `main` via PR #2 (2026-02-27). **v0.1.0 released.**

**v0.6.2 IN PROGRESS 🔄 (2026-03-06)**
Codex implementation complete. Gemini SDET + red-team audit is the active gate before PR.

**v0.6.1 MERGED ✅ (2026-03-02)**
Critical fixes for ArgoCD/Jenkins Istio hangs, LDAP defaults, and Jenkins namespace bugs.

**ArgoCD Phase 1 — MERGED ✅ (v0.4.0, 2026-03-02)**
Deployed live to infra cluster. ArgoCD running in `cicd` ns.

---

## What Is Complete ✅

### App Cluster Foundation
- [x] k3d-manager app-cluster mode refactor (v0.3.0)
- [x] End-to-end Infra Cluster Rebuild (v0.6.0)
- [x] Configure Vault `kubernetes-app` auth mount for Ubuntu app cluster
- [x] High-Rigor Engineering Protocol activated (v0.6.2)

### Bug Fixes (v0.6.1)
- [x] `destroy_cluster` default name fix
- [x] `deploy_ldap` no-args default fix
- [x] ArgoCD `redis-secret-init` Istio sidecar fix
- [x] ArgoCD Istio annotation string type fix (Copilot review)
- [x] Jenkins hardcoded LDAP namespace fix
- [x] Jenkins `cert-rotator` Istio sidecar fix
- [x] Task plan `--enable-ldap` typo fix (Copilot review)

---

## What Is Pending ⏳

### Priority 1 (Current focus — v0.6.2)

**v0.6.2 — AI Tooling & Safety Protocol:**
- [x] Implement `_agent_checkpoint` in `scripts/lib/agent_rigor.sh`
- [x] Implement `_ensure_node` + `_install_node_from_release` in `scripts/lib/system.sh`
- [x] Implement `_ensure_copilot_cli` in `scripts/lib/system.sh`
- [x] Implement `_k3d_manager_copilot` with generic params and implicit gating
- [x] Verify via `scripts/tests/lib/ensure_node.bats` and `ensure_copilot_cli.bats`
- [x] Gemini Phase 1: Audit complete — 4 findings in `docs/issues/2026-03-06-v0.6.2-sdet-audit-findings.md`
- [x] Codex fix cycle: fix sticky bit, relative PATH, deny-tool placement, mock integrity — task: `docs/plans/v0.6.2-codex-fix-task.md`
- [x] Gemini Phase 2: Full BATS suite pass + shellcheck (Findings: 115/115 pass with K3DMGR_NONINTERACTIVE=1, shellcheck issues at system.sh:149)
- [x] Gemini Phase 3: Structured RT-1 through RT-6 audit (Findings: RT-2 FAIL, RT-4 FAIL, RT-3 PARTIAL PASS)
- [x] Codex RT fix cycle: RT-2 (vault stdin injection) + RT-4 (deny-tool completeness) — task: `docs/plans/v0.6.2-codex-rt-fix-task.md`
- [ ] Codex Copilot fix cycle: rc propagation, empty PATH, sticky bit — task: `docs/plans/v0.6.2-codex-copilot-review-task.md`
- [ ] Claude: Review, commit, open PR
- Task spec: `docs/plans/v0.6.2-gemini-task.md`
- Implementation plan: `docs/plans/v0.6.2-ensure-copilot-cli.md`

**v0.6.3 — Refactoring & External Audit Integration:**
- [ ] Refactor `core.sh` and `system.sh` to eliminate "Defensive Bloat"
- [ ] Implement `_agent_audit` (Test weakening check)
- [ ] Integrate with `rigor-cli` for external architectural linting
- [ ] Verify via `scripts/tests/lib/agent_rigor.bats`

**v0.6.4 — Shared Library Foundation:**
- [ ] Create `lib-foundation` repository
- [ ] Extract `core.sh` and `system.sh` from `k3d-manager`
- [ ] Implement bi-directional git subtree integration across project ecosystem

**v0.7.0 — Keycloak + App Cluster Deployment:**
- [ ] Keycloak provider interface (Bitnami + Operator support)
- [ ] ESO deploy on App cluster (Ubuntu)
- [ ] shopping-cart-data (PostgreSQL, Redis, RabbitMQ) deployment on Ubuntu
- [ ] shopping-cart-apps (basket, order, payment, catalog, frontend) deployment on Ubuntu

**v0.8.0 — MCP Server (`k3dm-mcp`):**
- [ ] Lean MCP server wrapping `k3d-manager` CLI
- [ ] Target clients: Claude Desktop, OpenAI Codex, ChatGPT Atlas, Perplexity Comet
- [ ] Expose core operations as MCP tools (deploy, destroy, test, unseal)
- [ ] Sovereignty gating for destructive actions

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| GitGuardian: 1 internal secret incident (2026-02-28) | OPEN | No real secrets — likely IPs in docs. Mark false positive in dashboard. See `docs/issues/2026-02-28-gitguardian-internal-ip-addresses-in-docs.md`. |
| `CLUSTER_NAME=automation` env var ignored during `deploy_cluster` | OPEN | 2026-03-01: Cluster created as `k3d-cluster` instead of `automation`. See `docs/issues/2026-03-01-cluster-name-env-var-not-respected.md`. |
| No `scripts/tests/plugins/jenkins.bats` suite | BACKLOG | Jenkins plugin has no dedicated bats suite. `test_auth_cleanup.bats` covers auth flow. Full plugin suite (flag parsing, namespace resolution, mutual exclusivity) is a future improvement — not a gate for current work. |
