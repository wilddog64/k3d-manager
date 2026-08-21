# Active Context — k3d-manager

> Compressed 2026-08-20 before v1.26.0 planning. Historical detail is preserved in
> `memory-bank/archive/activeContext-2026-08-19.md`, `CHANGELOG.md`, `docs/retro/`, `docs/issues/`,
> and git history.

## Current focus

- **v1.25.0 is released.** PR #116 merged as `d48e465f`; tag and GitHub release `v1.25.0` are live.
- Main protection is restored to one required approval with administrators enforced.
- **Current milestone: v1.26.0** — sandbox registration lifecycle cleanup, E2E promotion-gate
  integration, and (scope decision 2026-08-20 "both, fleet first") the **count-agnostic fleet node
  lifecycle** refactor. Sequence: fleet first, then foundation-managed vCluster CLI → M2 remote E2E
  runner. Plan docs at 4/5 (fleet spec `docs/plans/v1.26.0-fleet-node-lifecycle.md` just added) —
  watch the cap.
- **✅ GATE DONE 2026-08-21 — Phase B HANDED TO CODEX.** lib-foundation fleet Phase A released as
  `v0.4.12` (PR #43 squash-merged → main `c4f3211`; Copilot review addressed `32ce9c9` — portable
  `mktemp -t acg-cluster.XXXXXX`+`|| return 1`, count-agnostic `acg_provision --help`, guard regex
  `Agent[12]([^0-9]|$)`, both threads GraphQL-resolved; stamp `c1df1be` direct fast-forward to main;
  tag `v0.4.12` + GitHub release live). **Subtree-pulled into k3d-manager** `scripts/lib/foundation`
  on `k3d-manager-v1.26.0` (merge `e60dff69`, squash `2c083258`, `0b574b13..c1df1bed`, pushed +
  origin-verified `dab1cd89`). lib-foundation next branch `feat/v0.4.13` + retro `c4ab19dc`.
  **Phase B is now UNBLOCKED for Codex** — assignment `docs/plans/v1.26.0-fleet-node-lifecycle-codex-task.md`
  (GATE-DONE marker stamped into the doc). Codex does B1–B5 impl + Rung-0 offline only
  (render/BATS/shellcheck/`bash -n`/`_agent_audit`), commits on `k3d-manager-v1.26.0`, must NOT touch
  the live sandbox. Numeric-ordering + mktemp + help carry-forwards all shipped in Phase A; B1 is a
  confirmed no-op (do NOT regen `scripts/etc/acg-cluster.yaml` from upstream — preserves SSM `!If`
  fix `fef71219`/`40f1d19a`). **Live acceptance is Claude's:** `ACG_AGENT_COUNT=4` via `make fleet-up`
  (= 5 nodes, the ACG cap; node-join only, NOT `make up`) — serialized per the live-sandbox rule.
- **Lifecycle cleanup foundation landed** in `f90c8e0d` on `k3d-manager-v1.26.0`: registration metadata,
  expiry/API-grace guarded `make cleanup-stale-clusters` (dry-run default), provider safety, and JSONL audit.
- v1.27.0 remains planned for image signing/attestation and adaptive checkout load testing;
  v1.28.0 remains planned for parallel multi-cloud provisioning and zero-downtime rollouts.
- **Phase B fleet lifecycle implemented and pushed 2026-08-21** as `b0fe320a` on
  `k3d-manager-v1.26.0`: k3s-aws now derives agent hosts/total nodes from `ACG_AGENT_COUNT`,
  shopping-cart agent joins fan out with per-node readiness, failure collection, and idempotent
  skips for both SSH and SSM paths, and `fleet-render|fleet-validate|fleet-plan|fleet-up` targets
  provide the offline-to-live rung sequence. `scripts/etc/acg-cluster.yaml` was intentionally
  unchanged. Rung-0 evidence: focused BATS 39/39, bash syntax clean, shellcheck showed only the
  pre-existing shopping-cart informational findings (no new findings), and `_agent_audit` passed.
  Live `fleet-up`/AWS validation remains Claude-owned.

## Open follow-ups

- **Dependabot alert #6 (js-yaml) remediated + staged.** Fixed as lib-foundation **v0.4.11**
  (PR #42 `b92f494`, tag/release live), subtree-pulled into `k3d-manager-v1.26.0` (`1bf1d2ce`,
  vendored lockfile now `3.15.1`). Alert still reads `open` only because Dependabot scans the default
  branch (main = v1.25.0) — it auto-closes when v1.26.0 ships to main. Dev-only transitive dep, low
  effective risk.

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
- **Hub preservation fix landed:** `make down CLEANUP_STALE=1` now implies `--keep-hub`, and
  `bin/cluster-down --keep-hub` preserves the Hub-dependent access layer; the prior post-teardown
  ordering deleted `k3d-k3d-cluster` before cleanup and took down ArgoCD/Grafana.
- **Hostinger-only services recovered (2026-08-20):** rebuilt the deleted local Hub without AWS,
  bootstrapped ArgoCD/observability, re-registered the surviving `ubuntu-hostinger` cluster, and
  restored Cloudflare/port-forward access. Final public checks: ArgoCD HTTP 200 and Grafana HTTP 302;
  Grafana local health HTTP 200. Current Grafana/ArgoCD credentials were regenerated; use
  `make show-service-passwords`. Hostinger frontend rollout remains a separate degraded issue.
- **SSM bootstrap fallback fixed** in `40f1d19a`: when `_ssm_bootstrap_k3s` fails during readiness,
  the provider disables SSM and retries `deploy_app_cluster` over SSH; it still fails if both
  transports fail. Evidence and regression coverage are recorded in
  `docs/issues/2026-08-20-k3s-aws-ssm-fallback-provisioning.md`.
- Fallback observability was clarified in `2424f55f`: fresh runs log SSM selection, the explicit
  `Switching transport: SSM -> SSH` transition, and SSH retry success (`k3d-manager-v1.26.0`).
- **Kubeconfig TLS SAN bug fixed** in `3603b60c`: local SSH/SSM kubeconfigs now retain the loopback
  API endpoint for tunneled kubectl traffic instead of rewriting it to the EC2 public IP. Evidence
  and regression coverage are recorded in
  `docs/issues/2026-08-20-k3s-aws-kubeconfig-public-ip-tls-san.md`.

## Operating decisions

- `make status` follows the active provider and offers concise, full, and JSON modes; Slack uses the
  same summary contract.
- CVE remediation current state excludes terminal `superseded`/`deployment_advanced` events; history keeps
  the audit trail. Verifier cadence and resource bounds are intentionally conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore credentials, and
  an EXIT-trap result artifact before teardown.
- Do not deploy source-only changes until their release branch/PR gates and live verification are explicit.

- **SSM Vault bridge gap fixed (2026-08-20):** when the laptop Vault reverse bridge is required
  (`HUB_VAULT_USE_BRIDGE=1`, the default), k3s-aws now selects SSH before provisioning and overrides
  explicit SSM with a warning. SSM remains available for non-bridge Vault profiles. Evidence is in
  `docs/issues/2026-08-20-ssm-vault-bridge-missing.md`.
- Live recovery verified on the existing sandbox: installing the missing bridge and forcing ESO
  reconcile returned `Ready=True/Valid` and 13/13 `SecretSynced`; remaining `make status` failures
  are separate edge/application issues.
- Cloudflare Error 1033/ArgoCD 502 diagnosed and fixed: the tunnel had stopped, and its ArgoCD
  origin used IPv6-prone `localhost:8080`; `scripts/etc/cloudflared/config.yml` now pins
  `127.0.0.1:8080`. Edge reload verified Grafana HTTP 302 and ArgoCD HTTP 200.
- **Stale unknown-Application cleanup fixed** in `2f4de4fd`: generated Applications did not inherit
  `k3d-manager/managed=true`, so cleanup could remove an expired AWS registration Secret while
  leaving its 19 generated Applications `Unknown`. Cleanup now matches the managed registration's
  cluster name, cluster label, or API server destination. Focused cleanup/lifecycle BATS passed;
  the full BATS run has unrelated webhook, vcluster, Slack relay, and ArgoCD deploy-key failures
  recorded in
  `docs/issues/2026-08-20-stale-cleanup-unknown-applications.md`.
- **ACG credential-route recovery fixed:** the persistent CDP session was authenticated, but the
  credential extractor could land on `https://s2.pluralsight.com/404.html` after the current
  `hands-on` route navigation. It now retries the legacy Cloud Sandboxes route; focused Playwright
  verification is 7 suites/22 tests green. The live credential gate remains unverified because the
  managed CDP browser exits during startup on port 9222. Details: `docs/issues/2026-08-20-acg-credential-s2-404.md`.
- **ACG CDP listener recovery fixed** upstream in `f6bb7bb`/`c7f7b37` and subtree-synced: a failed
  IPv4 probe now detects and reclaims IPv4/IPv6 listeners before relaunch, with explicit probe-status
  handling under `set -e`. Focused CDP BATS is 5/5 green. The live AWS credential gate now passed
  after reclaiming competing Chrome listeners and using the built-in sandbox restart fallback; evidence
  is recorded in `docs/issues/2026-08-20-acg-credential-live-retry.md`. The CDP BATS suite now isolates
  HOME and listener probes and passes 5/5 in one invocation.

## Canonical pointers

- Roadmap: `docs/roadmap.md`
- v1.26.0 plans: `docs/plans/`
- Active bugs/incidents: `docs/bugs/` and `docs/issues/`
- Release history: `CHANGELOG.md` and `docs/retro/`
