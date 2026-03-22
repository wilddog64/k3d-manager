# Progress — k3d-manager

## Overall Status

**v0.9.3 SHIPPED** — squash-merged to main (8046c73), PR #36, 2026-03-16. Tagged + released.
**v0.9.4 SHIPPED** — merged to main (662878a), PR #37, 2026-03-21.
**v0.9.5 SHIPPED** — PR #38 squash-merged to main (`573c0ac`) 2026-03-21. Tagged v0.9.5, released.
**v0.9.6 ACTIVE** — branch cut from main 2026-03-21. Focus: ACG AWS sandbox development.

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
- [x] Codex: add deploy_app_cluster automation — commit `13c79b3` adds k3sup install + kubeconfig merge helper and BATS coverage

---

## v0.9.5 — Completed

- [x] **`deploy_app_cluster` via k3sup** — `k3sup install` on EC2 + kubeconfig merge + ArgoCD cluster registration; replaces manual Gemini rebuild; prerequisite for v1.0.0 multi-node extension
- [x] check_cluster_health.sh hardening — kubectl context pinning, API server retry loop, `kubectl wait` replacing `rollout status`
- [x] Retro: `docs/retro/2026-03-21-v0.9.5-retrospective.md`

---

## v0.9.6 — Active

**Focus: ACG AWS sandbox development — plugin shipped; next up: multi-node k3sup + Samba AD for v1.0.0.**

### Primary
- [x] **ACG plugin** — `scripts/plugins/acg.sh`: `acg_provision`, `acg_status`, `acg_extend`, `acg_teardown`; retire `bin/acg-sandbox.sh`; spec: `docs/plans/v0.9.6-acg-plugin.md`; commit `37a6629`

### Code Quality / Architecture
- [ ] **Upstream local lib edits to lib-foundation** — `scripts/lib/system.sh` (TTY fix + `_run_command_resolve_sudo`) and `scripts/lib/agent_rigor.sh` (allowlist feature) need PRs to lib-foundation `feat/v0.3.4` → subtree pull → remove local divergence
- [ ] **Reduce if-count allowlist** — refactor 13 allowlisted functions (jenkins x6, ldap x7, vault x5, system x2) to under 8-`if` threshold; remainder needs `docs/issues/` entry; no new entries without linked issue
- [ ] **`bin/` script consistency** — `bin/smoke-test-cluster-health.sh` needs `_kubectl`/`_run_command`
- [ ] **Relocate app-layer bug tracking** — file shopping-cart bugs as GitHub Issues in their repos; remove from k3d-manager Known Bugs table

### Secondary (if primary complete)
- [ ] **Safety gate audit** — `deploy_*` with no args should print help, NOT trigger deployment
- [ ] **`--dry-run` / `-n` mode** — all `deploy_*` print every command without executing
- [ ] **`plan` mode** — prototype with Vault first
- [ ] **sudo whitelist** — `scripts/etc/sudoers/k3d-manager` template
- [ ] **Vault backup/restore** — `backup_vault` / `restore_vault`
- [ ] **GitHub PAT rotation** — expires 2026-04-12

### Deferred to v1.0.0 (needs multi-node)
- [ ] All 5 pods Running — order-service (RabbitMQ), payment-service (memory), frontend (resource exhaustion)
- [ ] Re-enable `shopping-cart-e2e-tests` + Playwright E2E green
- [ ] Re-enable `enforce_admins` on shopping-cart-payment
- [ ] Service mesh — Istio full activation

---

## Roadmap

- **v0.9.6** — ACG plugin (`acg_provision`, `acg_extend`, `acg_teardown`) + LoadBalancer for ArgoCD/Keycloak/Jenkins; retire `bin/acg-sandbox.sh`
- **v1.0.0** — 3-node k3s via k3sup + Samba AD DC; `CLUSTER_PROVIDER=k3s-remote`; resolves resource exhaustion; frontend + e2e milestone gate
- **v1.1.0** — Full stack provisioning: `provision_full_stack` single command (k3s + Vault + ESO + Istio + ArgoCD)
- **v1.2.0** — k3dm-mcp (gate: v1.0.0 multi-node proven; k3d + k3s-remote = two backends)
- **v1.3.0** — Home lab: k3s on Mac Mini M5 (`CLUSTER_PROVIDER=k3s-local-arm64`); home automation plugins
- **No EKS/GKE/AKS** — k3d-manager is kops-for-k3s; cloud-managed k8s is out of scope

---

## Known Bugs / Gaps

**Infra / tooling (tracked here):**

| Item | Status | Notes |
|---|---|---|
| SSH Tunnel timeouts | OPEN | Connection resets during heavy ArgoCD sync |

**App-layer (to be filed as GitHub Issues in their repos — v0.9.5 task):**

| Item | Repo | Notes |
|---|---|---|
| frontend CrashLoopBackOff | shopping-cart-frontend | Root cause: resource exhaustion (t3.medium); deferred to v1.0.0 3-node cluster |
| order-service CrashLoopBackOff | shopping-cart-order | PostgreSQL OK; RabbitMQ `Connection refused` only remaining |
| payment-service Pending | shopping-cart-payment | Memory constraints on `t3.medium` |
| product-catalog Degraded | shopping-cart-product-catalog | Synced to `aa5de3c`; `RABBITMQ_USERNAME` ESO key mismatch |
