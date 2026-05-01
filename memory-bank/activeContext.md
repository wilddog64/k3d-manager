# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.4.1` (as of 2026-05-01)

**Next task:** `_ai_agent_review` refactor — add generic AI dispatch abstraction to lib-foundation; update k3d-manager callers. Spec: `docs/plans/v1.4.1-ai-agent-review-abstraction.md`. Assign to Codex.

---

## Recently Shipped

- **v1.4.0** — Copilot CLI plugin (`copilot_triage_pod`, `copilot_draft_spec`) + `_copilot_review` rename + pre-commit `AGENT_LINT_AI_FUNC` wiring. PR #69 merged `a805dee0`, 2026-05-01. Retro: `docs/retro/2026-05-01-v1.4.0-retrospective.md`. `enforce_admins` restored.
- **v1.3.0** — Sandbox rebuild hardening: GHCR PAT validation, payment ESO postgres creds, cdp.sh subtree path fix, stage2 CI label gate, Makefile OAuth fallback removed. PR #68 merged `8136c4e3`, 2026-05-01. Retro: `docs/retro/2026-05-01-v1.3.0-retrospective.md`.
- **v1.2.0** — lib-acg subtree extraction, shopping-cart bootstrap, GHCR hardening. PR #67 `f628c3cb`, 2026-04-30. Retro: `docs/retro/2026-04-30-v1.2.0-retrospective.md`.

---

## v1.4.1 Open Work

### _ai_agent_review abstraction (NEXT — assign to Codex)
Spec: `docs/plans/v1.4.1-ai-agent-review-abstraction.md`
- lib-foundation: add `_ai_agent_review` to `scripts/lib/system.sh`; `AI_REVIEW_FUNC` (default: `copilot`), `AI_REVIEW_MODEL` (default: `gpt-5.4-mini`)
- k3d-manager: update `copilot.sh` + pre-commit hook + BATS + howto doc

### BATS suite for copilot plugin (follow-on from v1.4.0)
`scripts/tests/plugins/copilot.bats` — argument validation, K3DM_ENABLE_AI gate, `_ai_agent_review` invocation with kubectl/git stubs.

---

## Carry-forward Open Items (from v1.3.0)

- **ACG Watcher extend button** — post-extend modal not dismissed in CDP mode. Spec: `docs/bugs/2026-05-01-acg-extend-session-extended-modal-not-dismissed.md`.
- **Keycloak deployment** — spec: `docs/plans/v1.2.0-deploy-keycloak.md`. Assign to Codex.
- **LDAP hardcoded password** — spec: `docs/bugs/2026-04-26-ldap-users-hardcoded-test-password.md`.
- **vault-bridge pod-origin traffic** — `ClusterSecretStore/vault-backend` stays `Ready=False`. Spec: `docs/issues/2026-04-28-clustersecretstore-vault-bridge-pod-traffic-empty-reply.md`.
- **k3d-manager / shopping-cart decoupling** — spec: `docs/issues/2026-04-27-k3d-manager-shopping-cart-tight-coupling.md`.
- **GCP E2E smoke test** — BLOCKED. Full `make up` on live GCP sandbox not verified.
- **Post-Fix-2 cleanup** — BLOCKED on RabbitMQHealthIndicator JAR fix. Remove TCP socket probe patches from `services/shopping-cart-order/kustomization.yaml` only after JAR fix lands.

## Known Bugs / Gaps (standing)

- **Orchestration Fragility** — `docs/bugs/2026-04-23-infra-orchestration-fragility.md`
- **Dual-cluster Status UX** — `docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`
- **Repo Retention Cleanup** — `docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`
- **Whitespace Enforcement** — `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh`
- **GCP single-node vs AWS 3-node** — `docs/bugs/2026-04-25-gcp-single-node-vs-aws-three-node.md`
