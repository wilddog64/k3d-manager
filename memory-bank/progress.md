# Progress — k3d-manager

## Overall Status

**v0.9.3 SHIPPED** — squash-merged to main (8046c73), PR #36, 2026-03-16. Tagged + released.
**v0.9.4 ACTIVE** — branch cut from main 2026-03-16.

---

## v0.9.4 — Completed

- [x] README releases table — v0.9.3 added — `1e3a930`
- [x] lib-foundation v0.3.3 subtree pull — `7684266`
- [x] Multi-arch workflow pin — all 5 app repos merged to main 2026-03-18
- [x] ArgoCD cluster registration fix — manual cluster secret `cluster-ubuntu-k3s` with `insecure: true`
- [x] Missing `frontend` manifest — `argocd/applications/frontend.yaml` in shopping-cart-infra (PR #17)
- [x] Verify `ghcr-pull-secret` — present in `apps`, `data`, `payment` namespaces
- [x] Tag refresh for ARM64 images — `newTag: latest` in all 5 repos
- [x] Codex: kubeconfig merge automation — `6699ce8`
- [x] payment-service missing Secrets — PR #14 merged (9d9de98)
- [x] Fix `_run_command` non-interactive sudo failure — `fix(system): fall back to interactive sudo when sudo -n unavailable and TTY present`
- [x] autossh tunnel plugin — `feat(tunnel): add autossh tunnel plugin with launchd boot persistence`
- [x] ArgoCD cluster registration automation — `register_app_cluster` + cluster-secret template
- [x] Smoke tests — `bin/smoke-test-cluster-health.sh`
- [x] Reduce replicas to 1 + remove HPAs — merged 2026-03-20
- [x] Fix frontend nginx CrashLoopBackOff — `65b354f` merged to main 2026-03-21; tagged v0.1.1
- [x] Gemini: rebuild Ubuntu k3s + E2E verification — `7d614bc`
- [x] Gemini: ArgoCD cluster registration + app sync — `7d614bc`
- [x] Force ArgoCD sync — order-service + product-catalog — verified
- [x] Gemini: deploy data layer to ubuntu-k3s — all Running in `shopping-cart-data`
- [x] Gemini: Fix PostgreSQL auth issues — patched `order-service` and `product-catalog` secrets
- [x] Gemini: Fix PostgreSQL schema mismatch — added columns to `orders` table
- [x] Gemini: Fix product-catalog health check — patched readiness probe path
- [x] Gemini: Fix NetworkPolicies — unblocked `payment-service` and local DNS

---

## v0.9.4 — Pending

- [ ] **Safety gate audit** — `deploy_*` functions called with no args should print help, NOT trigger deployment.
- [ ] **`--dry-run` / `-n` mode** — all `deploy_*` print every command without executing.
- [ ] **`plan` mode** — prototype with Vault first.
- [ ] Confirm all 5 pods `Running` on Ubuntu k3s — basket/product-catalog/frontend: Running ✅; order-service: Crashing (RabbitMQ); payment-service: Pending (Memory)
- [ ] Re-enable `shopping-cart-e2e-tests` scheduled run — after pods Running
- [ ] Playwright E2E green — milestone gate
- [ ] Re-enable `enforce_admins` on shopping-cart-payment main branch

---

## v0.9.5 — Planned

- [ ] Service mesh — Istio full activation; `PeerAuthentication` / `AuthorizationPolicy` / `Gateway`
- [ ] **`deploy_app_cluster` via k3sup** — remote k3s install + kubeconfig merge
- [ ] **sudo whitelist** — `scripts/etc/sudoers/k3d-manager` template
- [ ] **Vault backup/restore** — `backup_vault` / `restore_vault`
- [ ] **GitHub PAT rotation** — expires 2026-04-12

---

## Roadmap

- **v1.1.0** — EKS provider + ACG lifecycle
- **v1.2.0** — k3dm-mcp
- **v1.3.0** — GKE + AD plugin: Google Cloud Identity
- **v1.4.0** — AKS
- **v1.5.0** — vCluster

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| frontend CrashLoopBackOff | FIXED | Manually patched with `emptyDir` volumes |
| order-service CrashLoopBackOff | OPEN | PostgreSQL auth/schema FIXED; now RabbitMQ `Connection refused` |
| payment-service Pending | OPEN | Memory constraints on `t3.medium` |
| SSH Tunnel timeouts | OPEN | Connection resets during heavy ArgoCD sync |
| ~/.claude credentials exposed | FIXED | Tokens rotated, history purged |
