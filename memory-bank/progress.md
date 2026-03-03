# Progress – k3d-manager

## Overall Status

`ldap-develop` merged to `main` via PR #2 (2026-02-27). **v0.1.0 released.**

**v0.6.2 IN PROGRESS 🔄 (2026-03-02)**
Adopting High-Rigor Engineering Protocol (Spec-First + Checkpointing) for App Cluster Deployment.

**v0.6.1 PR OPEN 🔄 (2026-03-02)**
Release branch `rebuild-infra-0.6.0`. Critical fixes for ArgoCD/Jenkins Istio hangs, LDAP defaults, and Jenkins namespace bugs.

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

**High-Rigor App Cluster Deployment:**
- [ ] Checkpoint: Commit `v0.6.2` baseline
- [ ] Spec-First: Ubuntu ESO Deployment Plan
- [ ] ESO deploy on App cluster (Ubuntu)
- [ ] shopping-cart-data (PostgreSQL, Redis, RabbitMQ) deployment on Ubuntu
- [ ] shopping-cart-apps (basket, order, payment, catalog, frontend) deployment on Ubuntu

**v0.6.2 — Copilot CLI Tool Management (BACKLOG):**
- [ ] `_ensure_node()` + `_install_node_from_release()` in `scripts/lib/system.sh`
- [ ] `_ensure_copilot_cli()` in `scripts/lib/system.sh`
- [ ] `scripts/tests/lib/ensure_node.bats` (5 cases)
- [ ] `scripts/tests/lib/ensure_copilot_cli.bats` (2 cases)
- Plan: `docs/plans/v0.6.2-ensure-copilot-cli.md`

---

## Known Bugs / Gaps

| Item | Status | Notes |
|---|---|---|
| GitGuardian: 1 internal secret incident (2026-02-28) | OPEN | No real secrets — likely IPs in docs. Mark false positive in dashboard. See `docs/issues/2026-02-28-gitguardian-internal-ip-addresses-in-docs.md`. |
| `CLUSTER_NAME=automation` env var ignored during `deploy_cluster` | OPEN | 2026-03-01: Cluster created as `k3d-cluster` instead of `automation`. See `docs/issues/2026-03-01-cluster-name-env-var-not-respected.md`. |
| No `scripts/tests/plugins/jenkins.bats` suite | BACKLOG | Jenkins plugin has no dedicated bats suite. `test_auth_cleanup.bats` covers auth flow. Full plugin suite (flag parsing, namespace resolution, mutual exclusivity) is a future improvement — not a gate for current work. |
