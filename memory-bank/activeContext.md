# Active Context — k3d-manager

## Current Branch: `k3d-manager-v1.2.0` (as of 2026-04-25)

**v1.1.0 SHIPPED** — PR #65 merged to main (`e013d23b`), tagged `v1.1.0`, released 2026-04-25.
Branch protection (`enforce_admins`) restored. Retro: `docs/retro/2026-04-25-v1.1.0-retrospective.md`.

## v1.1.0 Summary (SHIPPED — see `docs/retro/2026-04-25-v1.1.0-retrospective.md`)

Key commits: `3de58f4d` vars.sh, `a986d5bb` robot engine, `9686e5c3` GCP identity bridge,
`3a3806aa` CLUSTER_NAME fix, `1ab14ebf` CDP headless, `e013d23b` merge SHA.
All v1.1.0 bug detail archived in `docs/bugs/` and `git log`.


## v1.2.0 Open Items

- **ACG repo extraction** — IN PROGRESS (`docs/plans/v1.2.0-lib-acg-extraction.md`). P1 COMPLETE, P2 COMPLETE, P3 COMPLETE (`f1c577c`), P4 COMPLETE (`99b2e143`), P4b COMPLETE (`c54de858`), GCP OAuth fix COMPLETE (`04493b3` lib-acg / `d25477c4` k3d-manager). P5 ASSIGNED: lib-acg CI + pre-commit setup (`docs/plans/v1.2.0-phase5-lib-acg-ci-setup.md`).
- **ACG repo extraction P5** — ASSIGNED (Codex, resumes tomorrow). lib-acg CI (shellcheck + node --check + yamllint) + pre-commit hook + CHANGELOG. Spec: `docs/plans/v1.2.0-phase5-lib-acg-ci-setup.md`. Branch: `feat/phase5-ci-setup` in lib-acg (already exists, based on `feat/phase3-migration` + GCP fix).
- **GCP Sign-in-to-Chrome dialog** — ASSIGNED (Codex, resumes tomorrow). `gcp_login.js` does not dismiss Chrome's account-sync prompt that appears mid-OAuth flow. Spec: `docs/bugs/2026-04-25-gcp-login-chrome-signin-dialog.md`. Branch: `feat/phase5-ci-setup` in lib-acg.
- **sync-apps APP_CONTEXT hardwired** — COMPLETE. `make sync-apps CLUSTER_PROVIDER=k3s-gcp` was using `ubuntu-k3s` (AWS) context for pod status check instead of `ubuntu-gcp`. Fixed in Makefile `sync-apps` target. Spec: `docs/bugs/2026-04-25-sync-apps-app-context-hardwired-ubuntu-k3s.md`.
- **GCP OAuth fix (attempt 2)** — COMPLETE (`51afead` lib-acg, `df143452` k3d-manager). `--no-launch-browser` causes `EOFError` (gcloud waits for stdin verification code when run backgrounded). Fix: inject fake `open`/`xdg-open` into PATH so gcloud's browser-open call routes to CDP Chrome; localhost-redirect flow needs no code entry. Spec: `docs/bugs/2026-04-25-gcp-oauth-eof-stdin-crash.md`.
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
