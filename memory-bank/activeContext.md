# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.2.0` (as of 2026-04-25)

**v1.1.0 SHIPPED** — PR #65 merged to main (`e013d23b`), tagged `v1.1.0`, released 2026-04-25.
Branch protection (`enforce_admins`) restored. Retro: `docs/retro/2026-04-25-v1.1.0-retrospective.md`.

## v1.1.0 Summary (SHIPPED — see `docs/retro/2026-04-25-v1.1.0-retrospective.md`)

Key commits: `3de58f4d` vars.sh, `a986d5bb` robot engine, `9686e5c3` GCP identity bridge,
`3a3806aa` CLUSTER_NAME fix, `1ab14ebf` CDP headless, `e013d23b` merge SHA.
All v1.1.0 bug detail archived in `docs/bugs/` and `git log`.


## v1.2.0 Open Items

- **ACG repo extraction** — IN PROGRESS (`docs/plans/v1.2.0-lib-acg-extraction.md`). P1 COMPLETE, P2 COMPLETE, P3 COMPLETE (`f1c577c`), P4 COMPLETE (`99b2e143`), P4b COMPLETE (`c54de858`). Residual ArgoCD help/login verification gaps remain tracked in `docs/issues/2026-04-25-phase4-verification-argocd-preexisting-failures.md`.
- **ACG repo extraction P4b bug** — COMPLETE (`c54de858`). Replaced source-only `acg.sh` / `gcp.sh` stubs with grep-compatible wrapper functions so the dispatcher can discover `acg_*` and `gcp_*` entry points.
- **ACG repo extraction P4** — COMPLETE (`99b2e143`). Wired the `wilddog64/lib-acg` subtree into `scripts/lib/acg/`, replaced `scripts/plugins/acg.sh` and `scripts/plugins/gcp.sh` with stubs, and updated `scripts/plugins/gemini.sh` to source CDP helpers from the subtree.
- **ACG repo extraction P3** — COMPLETE (`f1c577c`). Migrated acg/gcp/playwright files from k3d-manager to `wilddog64/lib-acg` and pushed `feat/phase3-migration`.
- **ACG repo extraction P1** — COMPLETE (`20df717c`). Renamed `antigravity.sh` → `gemini.sh`; all `antigravity_*` → `gemini_*`.
- **ACG repo extraction P2** — COMPLETE (`b253b9b`). `wilddog64/lib-acg` created; skeleton + lib-foundation subtree committed and pushed; branch protection set.
- **GCP E2E smoke test** — BLOCKED. `k3s-gcp` provisioning logic is in place; full `make up` end-to-end on a live GCP sandbox has not been verified. Blocked by CDP startup on Linux.
- **Whitespace enforcement** — OPEN. `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh` files.
- **Orchestration Fragility** — OPEN (`docs/bugs/2026-04-23-infra-orchestration-fragility.md`). Hub orchestration does not explicitly sequence ArgoCD install + bootstrap + app-cluster registration.
- **Dual-cluster Status UX** — OPEN (`docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`). `make up/status` do not clearly separate Hub health from app-cluster health.
- **Vault Resilience Gap** — OPEN. Vault can still drift after Mac sleep; `docs/bugs/2026-04-23-vault-keychain-sync-mismatch.md` tracks the remaining gap.
- **Repo Retention Cleanup** — OPEN (`docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`). `scratch/` and historical docs should be reviewed for purge.
