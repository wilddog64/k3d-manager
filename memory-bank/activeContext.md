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
- **status APP_CONTEXT hardwired** — COMPLETE. Same root cause: `make status CLUSTER_PROVIDER=k3s-gcp` showed empty nodes from unreachable `ubuntu-k3s`. Fixed with same Makefile pattern. Spec: `docs/bugs/2026-04-25-status-app-context-hardwired-ubuntu-k3s.md`.
- **status ArgoCD CLI requires port-forward** — COMPLETE. Replaced `argocd app list` (requires active port-forward) with `kubectl get applications.argoproj.io -A --context INFRA_CONTEXT` (reads CRDs directly, no port-forward needed). Spec: `docs/bugs/2026-04-25-status-argocd-requires-port-forward.md`.
- **acg-down GCP _cluster_provider_call missing** — COMPLETE (`b8b72a67`). `bin/acg-down` k3s-gcp branch called `destroy_cluster` which routes through `_cluster_provider_call` (defined in `provider.sh`, never sourced). Fixed by calling `_provider_k3s_gcp_destroy_cluster` directly. Spec: `docs/bugs/2026-04-25-acg-down-gcp-cluster-provider-call-missing.md`.
- **acg-down GCP_PROJECT not set** — COMPLETE (`ca18e581`). `GCP_PROJECT` only exported in-memory by `gcp_get_credentials`; lost in new shell. Fixed by auto-detecting from `~/.local/share/k3d-manager/gcp-service-account.json` in `bin/acg-down`.
- **sync-apps missing Hub cluster preflight** — COMPLETE (`7fc1a6f4`). `bin/acg-sync-apps` gave cryptic kubectl error when Hub context missing. Added pre-flight check with clear message. Spec: `docs/bugs/2026-04-25-sync-apps-missing-hub-cluster-context.md`.
- **GCP instance creation not idempotent** — COMPLETE (`7582e290`). `_gcp_create_instance` failed on re-run if instance already existed. Added `instances describe` existence check matching `_gcp_ensure_firewall` pattern. Spec: `docs/bugs/2026-04-25-gcp-create-instance-not-idempotent.md`.
- **acg-up GCP skips Hub cluster** — COMPLETE (`f8f9d93b`). Early exit after Step 2 for k3s-gcp skipped Hub k3d cluster creation (Steps 3.5/3.6/4 are provider-agnostic). Fixed: only SSH tunnel (Step 3) gated behind non-GCP; Hub cluster + Vault + ArgoCD now created for GCP too. Steps 5–12 still AWS-only. Spec: `docs/bugs/2026-04-25-acg-up-gcp-skips-hub-cluster.md`.
- **status AWS Credentials section shown for GCP** — COMPLETE. `bin/acg-status` always ran `aws sts get-caller-identity` regardless of provider. Gated behind `CLUSTER_PROVIDER != k3s-gcp`; Makefile now passes `CLUSTER_PROVIDER` to the script. Spec: `docs/bugs/2026-04-25-status-shows-aws-creds-for-gcp.md`.
- **GCP OAuth fix (attempt 2)** — COMPLETE (`51afead` lib-acg, `df143452` k3d-manager). `--no-launch-browser` causes `EOFError` (gcloud waits for stdin verification code when run backgrounded). Fix: inject fake `open`/`xdg-open` into PATH so gcloud's browser-open call routes to CDP Chrome; localhost-redirect flow needs no code entry. Spec: `docs/bugs/2026-04-25-gcp-oauth-eof-stdin-crash.md`.
- **ACG repo extraction P4b bug** — COMPLETE (`c54de858`). Replaced source-only `acg.sh` / `gcp.sh` stubs with grep-compatible wrapper functions so the dispatcher can discover `acg_*` and `gcp_*` entry points.
- **ACG repo extraction P4** — COMPLETE (`99b2e143`). Wired the `wilddog64/lib-acg` subtree into `scripts/lib/acg/`, replaced `scripts/plugins/acg.sh` and `scripts/plugins/gcp.sh` with stubs, and updated `scripts/plugins/gemini.sh` to source CDP helpers from the subtree.
- **ACG repo extraction P3** — COMPLETE (`f1c577c`). Migrated acg/gcp/playwright files from k3d-manager to `wilddog64/lib-acg` and pushed `feat/phase3-migration`.
- **ACG repo extraction P1** — COMPLETE (`20df717c`). Renamed `antigravity.sh` → `gemini.sh`; all `antigravity_*` → `gemini_*`.
- **ACG repo extraction P2** — COMPLETE (`b253b9b`). `wilddog64/lib-acg` created; skeleton + lib-foundation subtree committed and pushed; branch protection set.
- **GCP E2E smoke test** — BLOCKED. `k3s-gcp` provisioning logic is in place; full `make up` end-to-end on a live GCP sandbox has not been verified. Blocked by CDP startup on Linux.
- **GCP single-node vs AWS 3-node** — OPEN. GCP provider creates 1 node; AWS creates 3 (server + 2 agents). Consistency gap, no stress testing done yet. Spec: `docs/bugs/2026-04-25-gcp-single-node-vs-aws-three-node.md`.
- **Whitespace enforcement** — OPEN. `_agent_lint` needs trailing-whitespace detection for `.js`/`.sh` files.
- **Orchestration Fragility** — OPEN (`docs/bugs/2026-04-23-infra-orchestration-fragility.md`). Hub orchestration does not explicitly sequence ArgoCD install + bootstrap + app-cluster registration.
- **Dual-cluster Status UX** — OPEN (`docs/bugs/2026-04-23-make-up-dual-cluster-status-and-orbstack-gap.md`). `make up/status` do not clearly separate Hub health from app-cluster health.
- **Vault Resilience Gap** — OPEN. Vault can still drift after Mac sleep; `docs/bugs/2026-04-23-vault-keychain-sync-mismatch.md` tracks the remaining gap.
- **Repo Retention Cleanup** — OPEN (`docs/issues/2026-04-23-repo-retention-cleanup-for-scratch-and-docs.md`). `scratch/` and historical docs should be reviewed for purge.
