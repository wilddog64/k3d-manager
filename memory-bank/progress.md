# Progress — k3d-manager

## Shipped — pointer, not record

The authoritative release record lives in `docs/releases.md`, `CHANGE.md`, and `git tag -l`. Retros for each release are under `docs/retro/`. This file tracks **in-flight** work only.

**Most recent shipped:**

- v1.2.0 — lib-acg extraction + shopping-cart bootstrap + GHCR hardening (PR #67, `f628c3cb`, 2026-04-30)
- v1.1.0 — Unified ACG automation AWS + GCP (PR #65, `e013d23b`, 2026-04-25)
- v1.0.6 — AWS SSM support for `k3s-aws` (PR #64, `a54e152f`, 2026-04-11)
- v1.0.5 — antigravity decoupling + LDAP Vault KV seeding + Copilot fix-up (PR #62/#63, `71c88b05`, 2026-04-11)

Pre-v1.0.5 detail removed; see `git log --tags` and `docs/retro/`.

---

## v1.3.0 Track (branch: `k3d-manager-v1.3.0`)

- [x] **`${K3D_MANAGER_BRANCH}` cleanup** — DONE `23475ac0`. Reverted to hardcoded `main` in `services-git.yaml`; removed export from `bin/acg-up`.
- [x] **lib-acg subtree pull** — DONE `dec36c9f`. Extend timing fix (lib-acg PR #3, `9b39df02`) pulled in.
- [ ] **ACG Watcher extend button** — extend works; post-extend modal not dismissed in CDP mode. Spec: `docs/bugs/2026-05-01-acg-extend-session-extended-modal-not-dismissed.md`. Assign to Codex.
- [ ] **Keycloak deployment** — OPEN. Spec: `docs/plans/v1.2.0-deploy-keycloak.md`. Assign to Codex.
- [ ] **LDAP hardcoded password** — OPEN. Spec: `docs/bugs/2026-04-26-ldap-users-hardcoded-test-password.md`.
- [ ] **vault-bridge pod-origin traffic** — OPEN. `ClusterSecretStore/vault-backend` stays `Ready=False`. Spec: `docs/issues/2026-04-28-clustersecretstore-vault-bridge-pod-traffic-empty-reply.md`.
- [ ] **k3d-manager / shopping-cart decoupling** — OPEN (v1.3.0). Spec: `docs/issues/2026-04-27-k3d-manager-shopping-cart-tight-coupling.md`.
- [ ] **stage2 CI cluster health** — OPEN. Requires live OrbStack cluster on self-hosted runner; always fails in PR context. Needs label-gate or optional workflow step.
- [ ] **GCP E2E smoke test** — BLOCKED. Full `make up` on live GCP sandbox not verified.

---

## v1.2.1 Track (shopping-cart upstream fixes — Codex)

Spec: `docs/plans/v1.2.0-fix-orders-init-sql-and-security-config.md`

- [x] **Fix 1** — `shopping-cart-infra` init SQL UUID. Merged `0bf8b8ec` (PR #32).
- [x] **Fix 2** — `shopping-cart-order` SecurityConfig `/actuator/health/**`. Merged `64f82fe3` (PR #27).
- [x] **Fix 3b** — `shopping-cart-order` namespace cleanup. Merged `6195bd42` (PR #28).
- [x] **Fix 3c** — `shopping-cart-product-catalog` namespace cleanup. Merged `19d5a2b7` (PR #19).
- [x] **Post-Fix-1 cleanup** — DONE `9aaa0cea`. Removed `SPRING_JPA_HIBERNATE_DDL_AUTO=update` from `services/shopping-cart-order/kustomization.yaml`.
- [ ] **Post-Fix-2 cleanup** — BLOCKED on RabbitMQHealthIndicator JAR fix. Remove TCP socket probe patches only after that lands too.

---

## Sandbox Rebuild Fixes — 2026-05-01

- [x] **cdp.sh path bug** — `../foundation` → `foundation`; `3c70c3a8` (k3d-manager), `369ef9f` (lib-acg)
- [x] **payment-db-credentials ESO** — `dfb65c73`; postgres password from Vault, ArgoCD ignoreDifferences
- [x] **shopping-cart-payment CI** — FIXED. SHAs: `4fa5fc1` (trivy) + `ff5c6ad` (changelog) merged to `shopping-cart-payment` main directly. CI green (`25213671956`); `shopping-cart-payment:latest` pushed to GHCR. Spec: `docs/bugs/2026-05-01-shopping-cart-payment-ci-broken-trivy-sha.md`.
- [x] **ghcr-pull-secret PAT validation** — FIXED (`3a0901cc`). `acg-up` Step 5 and `rotate-ghcr-pat` now validate Vault PAT against `api.github.com/user` before use and prompt for a replacement if expired. Spec: `docs/bugs/2026-05-01-ghcr-pat-validation-missing-acg-up-step5.md`.
- [ ] **Makefile OAuth fallback for GHCR_PAT** — ASSIGNED to Codex. `Makefile` line 7 sets `GHCR_PAT=$(gh auth token)`, bypassing Vault validation on every `make up`. Fix: remove OAuth fallback + add env-var validation in `acg-up`. Spec: `docs/bugs/2026-05-01-makefile-ghcr-pat-oauth-fallback.md`.

---

## Known Bugs / Gaps

- [ ] **Orchestration Fragility** — OPEN. `docs/bugs/2026-04-23-infra-orchestration-fragility.md`.
- [ ] **Dual-cluster Status UX** — OPEN. `docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`.
- [ ] **Repo Retention Cleanup** — OPEN. `docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`.
- [ ] **Whitespace Enforcement** — OPEN. `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh`.
- [ ] **GCP single-node vs AWS 3-node** — OPEN. `docs/bugs/2026-04-25-gcp-single-node-vs-aws-three-node.md`.
