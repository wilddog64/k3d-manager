# Progress — k3d-manager

## Overall Status

**v0.9.2 SHIPPED** — squash-merged to main (f0cec06), PR #35, 2026-03-15. Tagged + released.
**v0.9.3 ACTIVE** — branch cut from main 2026-03-15.

---

## What Is Complete

### Released (v0.1.0 – v0.9.2)

- [x] k3d/OrbStack/k3s cluster provider abstraction
- [x] Vault PKI, ESO, Istio, Jenkins, OpenLDAP, ArgoCD, Keycloak, cert-manager (infra cluster)
- [x] Two-cluster architecture (`CLUSTER_ROLE=infra|app`)
- [x] Cross-cluster Vault auth, Vault-managed ArgoCD deploy keys
- [x] Agent Rigor Protocol — `_agent_checkpoint`, `_agent_lint`, `_agent_audit`
- [x] `_k3d_manager_copilot` scoped wrapper, `_safe_path` PATH defense
- [x] `lib-foundation` subtree at `scripts/lib/foundation/`
- [x] Shopping Cart ecosystem — CI, ArgoCD, 5 apps Synced
- [x] vCluster plugin + E2E composite actions (v0.9.1–v0.9.2)
- [x] 11-finding Copilot hardening (v0.9.2)

---

## What Is Pending

### v0.9.3 — active

- [x] lib-foundation v0.3.2 subtree pull — commit `e4d2eed`
- [x] TTY fix — `_DCRS_PROVIDER` global in core.sh — commit `04522b5`
- [ ] **Cluster rebuild smoke test** — assigned to Gemini (`docs/plans/v0.9.3-cluster-rebuild-smoke-test.md`)

### v0.9.4 — planned

- [ ] Trigger CI in all 5 shopping-cart repos → images pushed to ghcr.io
- [x] NVD API key set in order + payment repos (2026-03-16)
- [ ] Verify ArgoCD: all 5 apps Synced + Healthy on Ubuntu k3s (Gemini)
- [ ] Re-enable `shopping-cart-e2e-tests` scheduled run
- [ ] Playwright E2E green in CI — milestone gate
- Spec: `docs/plans/v0.9.4-full-stack-health.md`

### After v0.9.x — k3dm-mcp v0.1.0

- Separate repo `~/src/gitrepo/personal/k3dm-mcp`
- Demo: k3dm-mcp → cluster_status → verify apps Running → Playwright E2E via MCP

### Deferred

- [ ] Playwright MCP E2E — prereq: images in ghcr.io + k3dm-mcp v0.1.0
- [ ] Google ACG sandbox (v1.1.0)
- [ ] M2 Air + Ubuntu pre-commit hooks — run `install-hooks.sh`

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| Shopping Cart Apps ImagePullBackOff | OPEN | Images not pushed to ghcr.io — blocked on v0.9.4 CI trigger |
| Ubuntu k3s CPU capacity (2 cores) | OPEN | shopping-cart-apps may exceed capacity — reduce replicas |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround |
