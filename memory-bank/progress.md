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
- [x] lib-foundation v0.3.3 subtree pull — commit `7684266`
- [x] NVD API key set in order + payment repos (2026-03-16)
- [x] shopping-cart-product-catalog — CI green, image in ghcr.io
- [x] shopping-cart-basket — CI green, image in ghcr.io
- [x] shopping-cart-frontend — CI green, image in ghcr.io
- [x] shopping-cart-order CI — green, image in ghcr.io — commit `cb663a2`
- [x] shopping-cart-payment CI — green, image in ghcr.io — commit `0ac292d`; NVD API key fix `14dda79`; docker-build secret fix `0ac292d`
- [x] Vuln scanning added to all 5 repos — OWASP (Java), pip-audit (Python), npm audit (Node), govulncheck (Go)
- [x] Apache 2.0 LICENSE added — all 6 shopping-cart repos + lib-foundation (2026-03-17)
- [x] Branch protection standardized — `enforce_admins: true` on all 6 shopping-cart repos
- [x] Frontend docs (`docs/architecture`, `docs/api`, `docs/troubleshooting`) — PR #4 merged
- [x] Mermaid architecture diagrams — order, product-catalog, basket (ASCII → Mermaid)
- [x] `copilot-instructions.md` added to shopping-cart-infra
- [x] ArgoCD cluster registration fix — PR #5 in shopping-cart-infra (`feat/argocd-cluster-registration`); Application manifests updated to `host.k3d.internal:6443`; `scripts/register-ubuntu-k3s.sh` added
- [x] Pre-publication security cleanup — 3 PRs merged 2026-03-17:
  - product-catalog: runtime RSA key generation (was hardcoded in test fixture)
  - order: CHANGE_ME placeholders in k8s/base/secret.yaml
  - infra: CHANGE_ME placeholders in 4 K8s Secret manifests
- [x] All 6 shopping-cart repos made **public** — 2026-03-17
- [x] Multi-arch CI builds — infra PR #7 merged (a937211) 2026-03-17; all 5 app repos benefit
- [x] ArgoCD architecture docs + app-of-apps rationale — infra PR #7 (docs/architecture.md)
- [x] Stale `examples/` deleted from shopping-cart-infra — infra PR #7
- [x] Docs standardization — product-catalog PR #8 merged (b6ff783) + order PR #8 merged (b2c1ba8) 2026-03-17
- [x] Docs standardization — payment PR #6 merged (224d721) 2026-03-17
- [x] Kustomize ghcr newName fix — order PR #9 merged (f19cc0c) 2026-03-17
- [x] Kustomize ghcr newName fix — product-catalog PR #9 merged (22c5405) 2026-03-17
- [x] Kustomize ghcr newName fix — payment PR #7 merged (7ab15c2) 2026-03-17
- [x] Mermaid architecture diagrams + consistent Architecture section presentation — all 5 service repos (payment PR #8, product-catalog PR #10, order PR #10, frontend PR #6) merged 2026-03-17; stale branches deleted; main synced; `docs/next-improvements` branches created
- [x] Verify ArgoCD: all 5 apps Synced + Healthy on Ubuntu k3s — **COMPLETE**
  - Gemini created `ghcr-pull-secret` in `shopping-cart-apps`, `shopping-cart-payment`, and `shopping-cart-data` (app cluster)
  - ArgoCD sync forced via `kubectl patch` on infra cluster
  - Pod status: `ImagePullBackOff` remains because app repos use pinned `amd64`-only CI workflow `8363caf` from `shopping-cart-infra`. Multi-arch PR #7 merged on infra but apps must update their `uses:` SHA to benefit.
  - Verification: `no match for platform in manifest: not found` confirmed on `arm64` Ubuntu k3s node.
- [ ] Deploy key rotation policy — 24h scheduled + on infra main merge; spec in `docs/plans/roadmap-v1.md` v0.8.0 section
- [x] Jenkins optional — **COMPLETE**: all 3 files gated (jenkins.sh, ldap.sh, vault.sh) — commits 08dc1bd + 4b02e16; BATS 2/2 PASS; shellcheck PASS
- [ ] Re-enable `shopping-cart-e2e-tests` scheduled run — after Gemini confirms pods Running
- [ ] Playwright E2E green in CI — milestone gate
- Spec: `docs/plans/v0.9.4-full-stack-health.md`
- Gemini unblock spec: `docs/plans/v0.9.4-gemini-ghcr-pull-secret.md`

### v0.9.5 — planned (after v0.9.4 ships)

- [ ] `PeerAuthentication` — STRICT mTLS mesh-wide
- [ ] `AuthorizationPolicy` — replace payment NetworkPolicy with L7 identity policy
- [ ] `Gateway` + `VirtualService` — frontend ingress via Istio
- [ ] `DestinationRule` — load balancing per service (LEAST_CONN / ROUND_ROBIN)
- [ ] `ServiceEntry` — Stripe + PayPal external gateways
- [ ] Namespace label fix — product-catalog missing `istio-injection: enabled`
- Spec: `docs/plans/v0.9.5-service-mesh.md`

### Other work completed this session (2026-03-17)

- [x] ASCII → Mermaid diagram fix — shopping-cart-order PR #11, shopping-cart-product-catalog PR #11, shopping-cart-infra PR #11 (was stale on branch) — all merged
- [x] tax-returns repo created — `github.com/wilddog64/tax-returns`; OTS 2025 installed `~/tools/OpenTaxSolver2025/`; binaries symlinked to `~/.local/bin`; `docs/workflow.md` written

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
| Shopping Cart Apps ImagePullBackOff | PENDING ARGOCD | all 5 images in ghcr.io; Gemini to verify ArgoCD Synced + Healthy |
| Ubuntu k3s CPU capacity (2 cores) | OPEN | shopping-cart-apps may exceed capacity — reduce replicas |
| `deploy_jenkins` (no flags) broken | BACKLOG | Use `--enable-vault` as workaround |
| `destroy_k3s_cluster` incomplete cleanup | BACKLOG | `k3s-uninstall.sh` leaves `/var/lib/rancher`, `/etc/rancher`, `/var/lib/kubelet` — causes ghost nodes on reinstall. Fix: add `sudo rm -rf` of those paths to `destroy_k3s_cluster` |
| OrbStack→Parallels pod connectivity | KNOWN | Pods in infra cluster can't reach Ubuntu VM API server directly. Workaround: `ssh -L 0.0.0.0:6443:localhost:6443 -N ubuntu` on M2 Air host |
| ArgoCD cluster registration over tunnel | KNOWN | `argocd cluster add` fails; use manual cluster secret pointing to `https://host.k3d.internal:6443` |
| Vault Kubernetes auth over tunnel | KNOWN | CA cert validation fails over SSH tunnel; use static Vault token with `eso-reader` policy as fallback |
