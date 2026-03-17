# Progress — k3d-manager

## Overall Status

**v0.9.3 SHIPPED** — squash-merged to main (8046c73), PR #36, 2026-03-16. Tagged + released.
**v0.9.4 ACTIVE** — branch cut from main 2026-03-16.

---

## What Is Complete

### Released (v0.1.0 – v0.9.3)

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
- [x] TTY fix — `_DCRS_PROVIDER` global in core.sh (v0.9.3)
- [x] lib-foundation v0.3.2 subtree pull (v0.9.3)
- [x] Cluster rebuild smoke test — PASS on M2 Air (v0.9.3)

---

## What Is Pending

### v0.9.4 — active

- [x] README releases table — v0.9.3 added — commit `1e3a930`
- [ ] lib-foundation v0.3.3 subtree pull
- [ ] Trigger CI in all 5 shopping-cart repos → images pushed to ghcr.io (owner action)
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
| `destroy_k3s_cluster` incomplete cleanup | BACKLOG | `k3s-uninstall.sh` leaves `/var/lib/rancher`, `/etc/rancher`, `/var/lib/kubelet` — causes ghost nodes on reinstall. Fix: add `sudo rm -rf` of those paths to `destroy_k3s_cluster` |
| OrbStack→Parallels pod connectivity | KNOWN | Pods in infra cluster can't reach Ubuntu VM API server directly. Workaround: `ssh -L 0.0.0.0:6443:localhost:6443 -N ubuntu` on M2 Air host |
| ArgoCD cluster registration over tunnel | KNOWN | `argocd cluster add` fails; use manual cluster secret pointing to `https://host.k3d.internal:6443` |
| Vault Kubernetes auth over tunnel | KNOWN | CA cert validation fails over SSH tunnel; use static Vault token with `eso-reader` policy as fallback |
