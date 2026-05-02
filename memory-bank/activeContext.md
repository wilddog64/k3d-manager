# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.4.1` (as of 2026-05-01)

**Completed:** `_ai_agent_review` refactor — generic AI dispatch abstraction landed in lib-foundation and k3d-manager callers were updated. Spec: `docs/plans/v1.4.1-ai-agent-review-abstraction.md`. lib-foundation SHA `448560a`; k3d-manager SHA `c8ac9b2f`.

---

## Recently Shipped

- **v1.4.0** — Copilot CLI plugin (`copilot_triage_pod`, `copilot_draft_spec`) + `_copilot_review` rename + pre-commit `AGENT_LINT_AI_FUNC` wiring. PR #69 merged `a805dee0`, 2026-05-01. Retro: `docs/retro/2026-05-01-v1.4.0-retrospective.md`. `enforce_admins` restored.
- **v1.3.0** — Sandbox rebuild hardening: GHCR PAT validation, payment ESO postgres creds, cdp.sh subtree path fix, stage2 CI label gate, Makefile OAuth fallback removed. PR #68 merged `8136c4e3`, 2026-05-01. Retro: `docs/retro/2026-05-01-v1.3.0-retrospective.md`.
- **v1.2.0** — lib-acg subtree extraction, shopping-cart bootstrap, GHCR hardening. PR #67 `f628c3cb`, 2026-04-30. Retro: `docs/retro/2026-04-30-v1.2.0-retrospective.md`.

---

## v1.4.1 Completed Work

### _ai_agent_review abstraction (DONE)
Spec: `docs/plans/v1.4.1-ai-agent-review-abstraction.md`
- lib-foundation `448560a`: add `_ai_agent_review` to `scripts/lib/system.sh`; `AI_REVIEW_FUNC` (default: `copilot`), `AI_REVIEW_MODEL` (default: `gpt-5.4-mini`)
- k3d-manager `c8ac9b2f`: update `copilot.sh` + pre-commit hook + BATS + howto doc

### Bugfix: `_copilot_review` K3DM_ENABLE_AI gate (DONE)
Spec: `docs/plans/v1.4.1-bugfix-copilot-review-k3dm-gate.md`
- lib-foundation `657fd91`: removed the `K3DM_ENABLE_AI` gate from `_copilot_review`
- lib-foundation `8d5edd2`: Copilot review fixes — `_ai_agent_review` `--model` dedup, BATS isolation, docs accuracy (PR #24, `108924b9`)
- k3d-manager `37234a96`: subtree pull from lib-foundation main (v0.3.17 + Copilot review fixes)
- enforce_admins restored on lib-foundation. lib-foundation next branch: `feat/v0.3.18`.

### ACG credentials 30s timeout — DONE
lib-acg fix `076f65d` merged PR #4 (`c34c0d80`); subtree pulled into k3d-manager at `dcfeec75` (2026-05-02).

### ACG credentials provision timeout — DONE
lib-acg PR #6 merged (`671b8b23`); subtree pulled into k3d-manager at `b23e29fb` (2026-05-02). Locator polling 420s; `OVERALL_TIMEOUT_MS` 780s.

### Bugfix: `_copilot_auth_check` K3DM_ENABLE_AI gate (PUSHED — needs PR)
Repo: lib-foundation. Spec: `docs/plans/v0.3.18-bugfix-copilot-auth-preflight.md` on branch `feat/v0.3.18`.
Codex implemented env tokens + apps.json checks (`feat/v0.3.18`). Claude patched fallback from `copilot auth status` → `gh auth status` (invalid subcommand in v1.0.40). Commit `eede5c3` pushed to `feat/v0.3.18`. BATS 5/5 pass. Next: `/create-pr` for lib-foundation.

### BATS suite for copilot plugin (OPEN — next task)
`scripts/tests/plugins/copilot.bats` — argument validation, K3DM_ENABLE_AI gate, `_ai_agent_review` invocation with kubectl/git stubs. `k3d_manager_copilot.bats` was updated (`c8ac9b2f`) but is the lib unit test; the plugin suite is a separate file still pending.

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
- **Copilot wrapper auth preflight** — `docs/issues/2026-05-01-copilot-wrapper-noninteractive-order-bug.md` (needs to reuse the local Copilot auth cache in `~/.config/github-copilot/apps.json` and only prompt when auth is missing/invalid)
- **Copilot docs drift after `_ai_agent_review` refactor** — `docs/issues/2026-05-01-copilot-docs-still-reference-stale-gate-and-caller-surface.md` (current docs still mix `_ai_agent_review` with stale `K3DM_ENABLE_AI` / `_copilot_review` wording)
- **Repo Retention Cleanup** — `docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`
- **Whitespace Enforcement** — `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh`
- **GCP single-node vs AWS 3-node** — `docs/bugs/2026-04-25-gcp-single-node-vs-aws-three-node.md`
