# Progress — k3d-manager

## Shipped — pointer, not record

The authoritative release record lives in `docs/releases.md`, `CHANGE.md`, and `git tag -l`. Retros for each release are under `docs/retro/`. This file tracks **in-flight** work only.

**Most recent shipped:**

- lib-foundation v0.3.18 — `_copilot_auth_check` rewrite: env tokens → apps.json → gh auth status; 6 BATS (PR #25, `ce9e5dbc`, 2026-05-02); k3d-manager subtree pulled at `cb08a90d`
- v1.4.0 — Copilot CLI plugin + `_copilot_review` rename + pre-commit AI lint wiring (PR #69, `a805dee0`, 2026-05-01)
- v1.3.0 — Sandbox rebuild hardening: GHCR PAT validation, payment ESO, cdp.sh path, stage2 gate (PR #68, `8136c4e3`, 2026-05-01)
- v1.2.0 — lib-acg extraction + shopping-cart bootstrap + GHCR hardening (PR #67, `f628c3cb`, 2026-04-30)
- v1.1.0 — Unified ACG automation AWS + GCP (PR #65, `e013d23b`, 2026-04-25)

Pre-v1.1.0 detail removed; see `git log --tags` and `docs/retro/`.

---

## v1.4.1 Track (branch: `k3d-manager-v1.4.1`)

- [x] **`_ai_agent_review` abstraction** — DONE (`448560a` / `c8ac9b2f`). Spec: `docs/plans/v1.4.1-ai-agent-review-abstraction.md`. lib-foundation adds `_ai_agent_review`; k3d-manager updates `copilot.sh`, pre-commit hook, BATS, and howto docs.
- [x] **Bugfix: `_copilot_review` K3DM_ENABLE_AI gate** — DONE (`657fd91` / `f6362f79`). Spec: `docs/plans/v1.4.1-bugfix-copilot-review-k3dm-gate.md`. Gate removed from lib-foundation; subtree pulled into k3d-manager. Smoke test error changed from K3DM_ENABLE_AI message to Copilot CLI exit 1 (environment, not code).
- [x] **ACG credentials 30s timeout** — DONE. lib-acg fix `076f65d` merged (PR #4, `c34c0d80`); subtree pulled into k3d-manager at `dcfeec75`.
- [x] **ACG credentials timeout values + _waitForSandboxEntry arg-slot bug** — DONE. lib-acg PR #5 merged (`f744901`); subtree pulled into k3d-manager at `ce7077ca`.
- [x] **ACG credentials provision timeout + waitForFunction CDP reliability** — DONE. lib-acg PR #6 merged (`671b8b23`); subtree pulled into k3d-manager at `b23e29fb` (2026-05-02).
- [x] **Bugfix: `_copilot_auth_check` K3DM_ENABLE_AI gate** — DONE. lib-foundation PR #25 merged (`ce9e5dbc`) 2026-05-02; subtree pulled into k3d-manager at `cb08a90d`.
- [x] **BATS suite for copilot plugin** — DONE (`d371b47b`). Spec: `docs/plans/v1.4.1-copilot-plugin-bats.md`. 9 tests for `copilot_triage_pod` + `copilot_draft_spec`. New file: `scripts/tests/plugins/copilot.bats`.
- [x] **ACG credentials CDP empty-contexts fix** — DONE. lib-acg PR #7 merged (`027b5765`) 2026-05-02; subtree pulled into k3d-manager at `cccd69d5`. PUT /json/new blank-tab recovery + disconnect guard.
- [x] **ACG credentials CDP reconnect after blank tab** — DONE. lib-acg PR #8 merged (`3091744`) 2026-05-02; subtree pulled into k3d-manager at `fc152a34`. Disconnect + reconnect after PUT /json/new so Playwright re-discovers the default context.
- [x] **shopping-cart-infra order-service schema mismatch** — MERGED (`7c2b164`). `shopping-cart-infra` main now includes the `cancellation_reason` schema fix; stale issue row removed from the k3d-manager backlog.
- [x] **shopping-cart-infra order-service schema expansion (11 columns)** — MERGED. PR #34 (`b8ff919d`, 2026-05-03). Codex commit `2e8d0bf`; Copilot fixes `aefa5c4`. `enforce_admins` restored.
- [x] **lib-acg Chrome SingletonLock Collision** — MERGED (`e26396b`). `lib-acg` main now includes the CDP profile-lock guard; subtree pulled into k3d-manager at `eb25604b`.
- [ ] **shopping-cart-infra payment-service DB auth failure** — OPEN. Spec: `shopping-cart-infra/docs/bugs/2026-05-03-payment-service-db-auth-failure.md`. Branch: `bug/payment-service-db-auth-failure`. Assigned to Codex. Fix: add `ignoreDifferences` for `payment-db-credentials` Secret in `argocd/applications/payment-service.yaml`.
- [x] **Bugfix: `acg-up` empty PAT guard** — DONE (`bbca2198`). Spec: `docs/bugs/v1.4.1-bugfix-acg-up-empty-pat-guard.md`. Guard added before namespace loop in `bin/acg-up`.

---

## v1.3.0 Carry-forward (open items not yet resolved)

- [ ] **ACG Watcher extend button** — post-extend modal not dismissed. Spec: `docs/bugs/2026-05-01-acg-extend-session-extended-modal-not-dismissed.md`.
- [ ] **Keycloak deployment** — Spec: `docs/plans/v1.2.0-deploy-keycloak.md`. Assign to Codex.
- [ ] **LDAP hardcoded password** — Spec: `docs/bugs/2026-04-26-ldap-users-hardcoded-test-password.md`.
- [ ] **vault-bridge pod-origin traffic** — `ClusterSecretStore/vault-backend` stays `Ready=False`. Spec: `docs/issues/2026-04-28-clustersecretstore-vault-bridge-pod-traffic-empty-reply.md`.
- [ ] **k3d-manager / shopping-cart decoupling** — Spec: `docs/issues/2026-04-27-k3d-manager-shopping-cart-tight-coupling.md`.
- [ ] **GCP E2E smoke test** — BLOCKED.
- [ ] **Post-Fix-2 cleanup** — BLOCKED on RabbitMQHealthIndicator JAR fix.

---

## Known Bugs / Gaps

- [ ] **Orchestration Fragility** — OPEN. `docs/bugs/2026-04-23-infra-orchestration-fragility.md`.
- [ ] **Dual-cluster Status UX** — OPEN. `docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`.
- [ ] **Copilot wrapper auth preflight** — OPEN. `docs/issues/2026-05-01-copilot-wrapper-noninteractive-order-bug.md`. Use the existing local Copilot auth cache when present; prompt only when auth is missing or invalid.
- [ ] **Copilot docs drift after `_ai_agent_review` refactor** — OPEN. `docs/issues/2026-05-01-copilot-docs-still-reference-stale-gate-and-caller-surface.md`. Current docs still mix `_ai_agent_review` with stale `K3DM_ENABLE_AI` / `_copilot_review` wording.
- [ ] **Repo Retention Cleanup** — OPEN. `docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`.
- [ ] **Whitespace Enforcement** — OPEN. `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh`.
- [ ] **GCP single-node vs AWS 3-node** — OPEN. `docs/bugs/2026-04-25-gcp-single-node-vs-aws-three-node.md`.
