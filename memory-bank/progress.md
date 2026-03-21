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
- [x] Codex: fix app manifests — PRs merged to main; order `d109004`, product-catalog `aa5de3c`, infra `1a5c34d`; tagged v0.1.1; `docs/next-improvements` branch created
- [x] Codex: fix frontend manifests — PR #11 CLOSED; Copilot P1 confirmed original port 8080 + /health was correct; root cause is resource exhaustion not manifest error; deferred to v1.0.0
- [x] Gemini: Re-enable ArgoCD auto-sync — all apps reconciled to `HEAD`

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

- **v1.0.0** — 3-node k3s via k3sup + Samba AD DC (NEXT — replaces single t3.medium; resolves resource exhaustion)
- **v1.1.0** — EKS provider + ACG lifecycle + AWS Managed AD
- **v1.2.0** — k3dm-mcp (gate: EKS delivered)
- **v1.3.0** — GKE + AD plugin: Google Cloud Identity
- **v1.4.0** — AKS
- **v1.5.0** — vCluster

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| frontend CrashLoopBackOff | REGRESSION | Was fixed with emptyDir patch; ArgoCD sync may have overwritten it — re-check volumes |
| order-service CrashLoopBackOff | OPEN | PostgreSQL auth/schema FIXED; VAULT_ENABLED=false FIXED; now RabbitMQ `Connection refused` only |
| payment-service Pending | OPEN | Memory constraints on `t3.medium` |
| product-catalog OutOfSync | OPEN | Manifest fix `aa5de3c` on main; ArgoCD not yet synced to it |
| SSH Tunnel timeouts | OPEN | Connection resets during heavy ArgoCD sync |
| ~/.claude credentials exposed | FIXED | Tokens rotated, history purged |
