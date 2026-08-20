# Active Context — k3d-manager

> Compressed 2026-08-20 before v1.26.0 planning. Historical detail is preserved in
> `memory-bank/archive/activeContext-2026-08-19.md`, `CHANGELOG.md`, `docs/retro/`, `docs/issues/`,
> and git history.

## Current focus

- **v1.25.0 is released.** PR #116 merged as `d48e465f`; tag and GitHub release `v1.25.0` are live.
- Main protection is restored to one required approval with administrators enforced.
- **Current milestone: v1.26.0** — sandbox registration lifecycle cleanup and E2E promotion-gate integration.
- **Lifecycle cleanup foundation landed** in `f90c8e0d` on `k3d-manager-v1.26.0`: registration metadata,
  expiry/API-grace guarded `make cleanup-stale-clusters` (dry-run default), provider safety, and JSONL audit.
- v1.27.0 remains planned for image signing/attestation and adaptive checkout load testing;
  v1.28.0 remains planned for parallel multi-cloud provisioning and zero-downtime rollouts.

## Open follow-ups

- Validate the v1.26.0 sandbox deregistration/unknown-resource cleanup flow on a real expired sandbox; source-only
  implementation is pushed, and no live cleanup has been run.
- Complete the E2E promotion-gate live acceptance and retain a result artifact for every run.
- Replace the interim in-cluster CVE promoter git-writer token with a fine-grained contents-write-only PAT.
- Reconcile stale local port-forward/LaunchAgent state when public Grafana or status probes fail.
- Keep the ArgoCD smoke credential-drift issue and k3s-aws SSM registration issue visible in `docs/issues/`
  and `docs/bugs/` until their live follow-ups are closed.
- **SSM fallback fixed** in `fef71219`: k3s-aws now falls back to SSH when SSM registration or tunnel setup
  fails, and fails only when both transports fail. Live account-level Default Host Management Role setup
  remains optional infrastructure follow-up.
- **Lifecycle cleanup + data-layer DNS fix** landed in `316f26d2`: `make help` documents the guarded
  stale-cleanup targets, `make down CLEANUP_STALE=1` performs explicit post-teardown cleanup, and
  `bin/cluster-up` restores the Hub `host.k3d.internal` CoreDNS alias before ArgoCD registration. The
  regression and root-cause record are in `docs/issues/2026-08-20-make-up-data-layer-argocd-host-dns.md`.
- The cleanup invocation is now also shown in the help Examples section (`20a13862`, pushed on
  `k3d-manager-v1.26.0`).
- Unified cleanup is available as `make cleanup-stale-resources` (`f24c0c96`, pushed on
  `k3d-manager-v1.26.0`); `make down CLEANUP_STALE=1` now calls this wrapper, which runs the
  managed-registration cleanup for every provider and the local sandbox cleanup for k3s-aws.
- **SSM bootstrap fallback fixed** in `40f1d19a`: when `_ssm_bootstrap_k3s` fails during readiness,
  the provider disables SSM and retries `deploy_app_cluster` over SSH; it still fails if both
  transports fail. Evidence and regression coverage are recorded in
  `docs/issues/2026-08-20-k3s-aws-ssm-fallback-provisioning.md`.

## Operating decisions

- `make status` follows the active provider and offers concise, full, and JSON modes; Slack uses the
  same summary contract.
- CVE remediation current state excludes terminal `superseded`/`deployment_advanced` events; history keeps
  the audit trail. Verifier cadence and resource bounds are intentionally conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore credentials, and
  an EXIT-trap result artifact before teardown.
- Do not deploy source-only changes until their release branch/PR gates and live verification are explicit.

## Canonical pointers

- Roadmap: `docs/roadmap.md`
- v1.26.0 plans: `docs/plans/`
- Active bugs/incidents: `docs/bugs/` and `docs/issues/`
- Release history: `CHANGELOG.md` and `docs/retro/`
