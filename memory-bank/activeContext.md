# Active Context — k3d-manager

> Compressed 2026-08-21 (v1.26.0 committed work complete). Settled fixes collapsed to
> pointers; detail lives in `memory-bank/archive/`, `CHANGELOG.md`, `docs/retro/`,
> `docs/issues/`, `docs/bugs/`, and git history.

## Current focus

- **v1.26.0 RELEASE PR OPEN — #117** (`k3d-manager-v1.26.0` → `main`, head `525d69d0`).
  CI green (lint, CodeQL×3, GitGuardian, detect; stage2 skips on PR); Claude scope check PASS
  (354 files all trace to v1.26.0 milestone work). **Copilot review addressed + thread resolved**
  — its one comment (no test coverage for the managed `register_app_cluster` fail-closed guard +
  labels/annotations) fixed in `525d69d0` with 2 focused `provider_contract.bats` cases (54/54).
  PENDING before merge: the user's explicit merge go. **`enforce_admins` DISABLED on `main`
  2026-08-21 for the user's admin-override merge (was enabled, 1 required approval) — MUST be
  restored in `/post-merge` Step 2 via bodyless `POST …/enforce_admins`.** Ships 3/5 scopes (fleet A+B, E2E gate, stale-cleanup); the
  foundation-vcluster-CLI and M2-runner scopes remain specs. Merge auto-closes Dependabot #6.
  **Do NOT auto-merge.** Post-merge: run `/post-merge` (tag `v1.26.0` from CHANGELOG, restore
  protection, next branch, retro).
- **v1.25.0 released** (PR #116 `d48e465f`, tag/release live). Main protection restored to
  one required approval, administrators enforced.
- **Milestone v1.26.0 — committed work is DONE and pushed on `k3d-manager-v1.26.0`:**
  - **Fleet node lifecycle (count-agnostic)** — Phase A shipped as lib-foundation `v0.4.12`
    (PR #43, subtree-pulled `e60dff69`/`2c083258`); Phase B implemented `b0fe320a` and
    live-verified at `ACG_AGENT_COUNT=4` (5 nodes = ACG cap). Two live-only defects found +
    fixed (`_k3s_agent_is_ready` private-IP match; `fleet-plan` change-set) — `46bfdf1c`,
    memory-bank followup `35e9ecf2`. Suite 17/17, teardown clean. **DONE.**
  - **E2E promotion-gate + durable artifacts** — live acceptance GREEN 2026-08-21: run →
    `~/.k3dm/e2e/*.json` artifact → result-event ConfigMap → exporter `e2e_*` gauges →
    dashboard/alert. **DONE.**
  - **Stale managed-registration cleanup** — live acceptance GREEN 2026-08-21 on a real
    expired sandbox; 23 unrelated survivors exact-match, hostinger untouched. Found + fixed
    BLOCKING Finding 2a (`cleanup-stale-clusters` hung — Secret-first + `--wait=false` fix,
    `0274fdde`). **DONE.**
  - Live-acceptance findings: `docs/bugs/2026-08-21-lifecycle-e2e-live-acceptance-findings.md`
    and `docs/bugs/2026-08-21-fleet-phaseb-live-verification-findings.md`.
- **Next in v1.26.0 sequence** (scope decision 2026-08-20 "both, fleet first" — fleet is
  done): foundation-managed vCluster CLI → M2 remote E2E runner. Plan docs at **5/5** — the
  cap is hit; split before adding a 6th scope.
- v1.27.0 planned: image signing/attestation + adaptive checkout load testing.
  v1.28.0 planned: parallel multi-cloud provisioning + zero-downtime rollouts.

## Open follow-ups

- **Dependabot alert #6 (js-yaml)** — remediated upstream as lib-foundation `v0.4.11`,
  subtree-pulled (`1bf1d2ce`, vendored lockfile `3.15.1`). Still reads `open` only because
  Dependabot scans the default branch (main = v1.25.0); **auto-closes when v1.26.0 → main.**
  Dev-only transitive dep, low effective risk.
- **Un-fixed findings** (filed as tracked issues, deferred out of v1.26.0):
  - Finding 1a — exporter emits empty `e2e_last_run_duration_seconds` when duration is null
    (should default `0`). Cosmetic. `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.
  - Finding 2b — dispatcher `deploy_*` guard strips `--confirm` from `deploy_app_cluster`;
    use a lib-sourcing wrapper. Shared-guard blast radius.
    `docs/issues/2026-08-21-dispatcher-strips-confirm-deploy-app-cluster.md`.
- Replace the interim in-cluster CVE promoter git-writer token with a fine-grained
  contents-write-only PAT.
- Reconcile stale local port-forward/LaunchAgent state when public Grafana or status probes
  fail (see `reference_single_service_502_zombie_port_forward` in auto-memory).
- Keep the ArgoCD smoke credential-drift and k3s-aws SSM registration issues visible in
  `docs/issues/`/`docs/bugs/` until their live follow-ups close.
- 2026-08-20 provisioning/recovery batch (all landed + pushed, recorded in `docs/issues/`):
  k3s-aws SSM→SSH fallback (`fef71219`/`40f1d19a`/`2424f55f`), kubeconfig TLS SAN loopback
  fix (`3603b60c`), SSM Vault-bridge selects SSH, data-layer CoreDNS alias + guarded
  `make down CLEANUP_STALE=1` (`316f26d2`/`f24c0c96`, implies `--keep-hub`), hostinger-only
  hub rebuild, cloudflared IPv4-loopback pin. Account-level SSM Default Host Management Role
  remains an optional infra follow-up.

## Operating decisions

- `make status` follows the active provider (concise/full/JSON modes); Slack reuses the same
  summary contract.
- CVE remediation current-state excludes terminal `superseded`/`deployment_advanced` events;
  history keeps the audit trail. Verifier cadence/bounds stay conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore
  credentials, and an EXIT-trap result artifact written before teardown.
- Do not deploy source-only changes until their release-branch/PR gates and live verification
  are explicit.
- When the laptop Vault reverse bridge is required (`HUB_VAULT_USE_BRIDGE=1`, default),
  k3s-aws selects SSH and overrides explicit SSM with a warning; SSM stays available for
  non-bridge Vault profiles.

## Canonical pointers

- Roadmap: `docs/roadmap.md`
- v1.26.0 plans: `docs/plans/`
- Active bugs/incidents: `docs/bugs/` and `docs/issues/`
- Release history: `CHANGELOG.md` and `docs/retro/`
