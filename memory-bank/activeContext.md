# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.2.0` (as of 2026-04-25)

**v1.1.0 SHIPPED** — PR #65 merged to main (`e013d23b`), tagged `v1.1.0`, released 2026-04-25.
Branch protection (`enforce_admins`) restored. Retro: `docs/retro/2026-04-25-v1.1.0-retrospective.md`.

## v1.1.0 Summary (SHIPPED — see `docs/retro/2026-04-25-v1.1.0-retrospective.md`)

Key commits: `3de58f4d` vars.sh, `a986d5bb` robot engine, `9686e5c3` GCP identity bridge,
`3a3806aa` CLUSTER_NAME fix, `1ab14ebf` CDP headless, `e013d23b` merge SHA.
All v1.1.0 bug detail archived in `docs/bugs/` and `git log`.


## v1.2.0 Open Items

- **ACG repo extraction** — PLANNED (`docs/plans/v1.1.0-acg-extraction-repo-split.md`). Extract browser/CDP/Playwright automation into its own repo. First task for v1.2.0.
- **GCP E2E smoke test** — BLOCKED. `k3s-gcp` provisioning logic is in place; full `make up` end-to-end on a live GCP sandbox has not been verified. Blocked by CDP startup on Linux.
- **Whitespace enforcement** — OPEN. `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh` files.
- **Orchestration Fragility** — OPEN (`docs/bugs/2026-04-23-infra-orchestration-fragility.md`). Hub orchestration does not explicitly sequence ArgoCD install + bootstrap + app-cluster registration.
- **Dual-cluster Status UX** — OPEN (`docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`). `make up/status` do not clearly separate Hub health from app-cluster health.
- **Vault Resilience Gap** — OPEN. Vault can still drift after Mac sleep; `docs/bugs/2026-04-23-vault-keychain-sync-mismatch.md` tracks the remaining gap.
- **Repo Retention Cleanup** — OPEN (`docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`). `scratch/` and historical docs should be reviewed for purge.
