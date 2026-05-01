# Progress — k3d-manager

## Shipped — pointer, not record

The authoritative release record lives in `docs/releases.md`, `CHANGE.md`, and `git tag -l`. Retros for each release are under `docs/retro/`. This file tracks **in-flight** work only.

**Most recent shipped:**

- v1.4.0 — Copilot CLI plugin + `_copilot_review` rename + pre-commit AI lint wiring (PR #69, `a805dee0`, 2026-05-01)
- v1.3.0 — Sandbox rebuild hardening: GHCR PAT validation, payment ESO, cdp.sh path, stage2 gate (PR #68, `8136c4e3`, 2026-05-01)
- v1.2.0 — lib-acg extraction + shopping-cart bootstrap + GHCR hardening (PR #67, `f628c3cb`, 2026-04-30)
- v1.1.0 — Unified ACG automation AWS + GCP (PR #65, `e013d23b`, 2026-04-25)

Pre-v1.1.0 detail removed; see `git log --tags` and `docs/retro/`.

---

## v1.4.1 Track (branch: `k3d-manager-v1.4.1`)

- [ ] **`_ai_agent_review` abstraction** — OPEN. Spec: `docs/plans/v1.4.1-ai-agent-review-abstraction.md`. Assign to Codex.
- [ ] **BATS suite for copilot plugin** — OPEN. `scripts/tests/plugins/copilot.bats`. Follow-on from v1.4.0 Copilot finding.

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
- [ ] **Repo Retention Cleanup** — OPEN. `docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`.
- [ ] **Whitespace Enforcement** — OPEN. `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh`.
- [ ] **GCP single-node vs AWS 3-node** — OPEN. `docs/bugs/2026-04-25-gcp-single-node-vs-aws-three-node.md`.
