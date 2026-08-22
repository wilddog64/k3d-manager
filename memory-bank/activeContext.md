# Active Context — k3d-manager

> Compressed 2026-08-21 (v1.26.0 committed work complete). Settled fixes collapsed to
> pointers; detail lives in `memory-bank/archive/`, `CHANGELOG.md`, `docs/retro/`,
> `docs/issues/`, `docs/bugs/`, and git history.

## Current focus

- **v1.27.0 foundation-managed vCluster CLI Part B DELIVERED + VERIFIED + PUSHED** — HEAD
  `142fd06b` on `origin/k3d-manager-v1.27.0` (Codex; its own note cited `6c2dd94d` which was
  amended away and is not in history). Rewires `vcluster.sh` to `foundation_ensure_vcluster_cli`
  (module-scoped `_VCLUSTER_BIN`, guards non-zero + empty path), removes the consumer installer,
  updates help/docs, reworks BATS to stub the contract. **Claude re-ran gates independently:**
  BATS 36/36, shellcheck clean, `bash -n` clean, both disappearance greps empty, subtree
  untouched. **LIVE `make e2e` gate PASSED for the CLI contract:** real download + SHA-verify +
  atomic install of vcluster `0.32.1` (managed path, not PATH Homebrew), plugin created the
  throwaway vCluster + substrate via the managed binary, teardown clean; artifact/ConfigMap/exporter
  all carry commit `9b3a5754`. The Playwright app Job failed (`running-playwright`, pre-existing
  app-test failure — NOT the CLI change). **Plan #1 (Parts A+B) functionally COMPLETE.** No PR yet
  (v1.27.0-release-time step). Part A shipped as lib-foundation `v0.4.13`.
  - ✅ **Finding 1a FIXED + LIVE-VERIFIED** (`5cd67228`): added a `num()` helper coercing
    empty/None/non-numeric → `0` (timestamps keep integer display), routed every numeric gauge
    emission through it so no single malformed value can zero out the whole scrape. Redeployed
    via `kubectl apply` + `rollout restart`; live-confirmed `up{exporter}=1` (new pod, 3711
    samples), `e2e_last_run_duration_seconds … 0`, `trivy_vulnerability_inventory`=3706 series
    back — both E2E and CVE dashboards receiving data again.
    `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.

- **v1.26.0 RELEASED** — PR #117 `1bbe5439` merged to main, tag/release published. Branch protection restored (`enforce_admins=true`, 1 required approval). Shipped 3/5 scopes (fleet node lifecycle count-agnostic, E2E promotion gate + observability, managed registration cleanup). Retrospective: `docs/retro/2026-08-21-v1.26.0-retrospective.md`.

- **v1.27.0 active branch** (`k3d-manager-v1.27.0`, branched from merge commit). **Scope = 4 plan docs (4/5, under cap):**
  1. `docs/plans/v1.27.0-foundation-managed-vcluster-cli.md` — load-split **prerequisite**. **Part A DONE:** lib-foundation `v0.4.13` released (PR #44 `0a3e4043`, tag/release live), subtree-pulled into `scripts/lib/foundation` — `foundation_ensure_vcluster_cli` vendored + verified. **Part B UNBLOCKED (next up):** rewire `scripts/plugins/vcluster.sh` to call `foundation_ensure_vcluster_cli "$VCLUSTER_VERSION"`, drop the local installer/Homebrew paths.
  2. `docs/plans/v1.27.0-m2-remote-e2e-runner.md` — the actual E2E load-split off the M4 laptop; depends on #1 (now met). **STARTED.**
     - Increment 1 DONE (`5c863dcc`): producer-side runner-provenance contract — E2E summary + result-event ConfigMap carry a `runner` field (default `local-m4`, `E2E_RUNNER` override), `k3dm.k3d.io/e2e-runner` label, prune keyed per (service,tier,runner). Backward-compatible; BATS 18/18 + 10/10.
     - Increment 2 DONE (`6d2ce551`): consumer side — exporter reads `runner` (legacy→`local-m4`), adds it to metric dims + `e2e_run_info` + emitted label body; Grafana e2e dashboard gains a `runner` template var (multi/includeAll/All default), every panel filters `runner=~"$runner"`; e2e alert summaries include runner. RBAC unchanged. BATS 11/11 (+1). ⚠️ **LIVE redeploy of these platform-ops manifests DEFERRED to the plan-#2 live-accept gate** (when real `runner=m2` data exists) — live exporter is still the Finding 1a hotfix (`5cd67228`); source is ahead by the runner label. Redeploy exporter+dashboard+rule via `argocd.sh` at acceptance.
     - Increment 3 DONE (new plugin `scripts/plugins/e2e_remote.sh`): M2 bootstrap/preflight — public `e2e_runner_preflight`/`e2e_runner_bootstrap`/`e2e_runner_status`. Pure BATS-testable gate core (`_e2e_remote_eval_gates`) + SSH probe; gates docker-up/lock-free/CPU-idle≥35% (2 samples)/mem≥25%/disk≥40GiB → structured `status=` (available|busy|docker_down|capacity_*|unreachable). Bootstrap: reachability → start OrbStack only if stopped (bounded wait) → reconcile a **dedicated** `k3d-e2e-runner` cluster (refuses hub name `k3d-cluster`) → verify vCluster CLI via foundation contract. Safe SSH opts (BatchMode, no StrictHostKeyChecking=no). BATS 17/17, shellcheck clean, `bash -n` clean. **LIVE-VERIFIED against real M2** (`k3d-manager e2e_runner_preflight` → `status=available`, cpu 70/72%, mem 46%, disk 153GiB).
     - **M2 live resource re-check (2026-08-22, user-requested):** M2 = `m2jump`→`m2-air.local` (hostname `Mac`, user cliang), 8 cores/16 GiB, macOS 26.5.1. Host gates pass (CPU idle ~60-73%, mem 45-46% free, disk 153 GiB). **Caveats found:** (a) real container budget is the **OrbStack Linux VM cap = 7.818 GiB**, not 16 GiB — and a pre-existing `k3d-k3d-cluster` (server+3 agents) already eats ~1.8 GiB of it + ~6 GiB host swap in use → ~6 GiB free in the VM for the ephemeral E2E vCluster (workable but tight; consider tearing down M2's stray hub-shaped cluster or raising the VM mem cap before acceptance). (b) `/opt/homebrew/bin` (k3d, vcluster) is **not** on M2's non-interactive SSH PATH → remote cmds 127 without a PATH prefix; fixed via `E2E_M2_REMOTE_PATH=/opt/homebrew/bin:/usr/local/bin` injected by `_e2e_remote_ssh`. (c) An earlier probe caught OrbStack mid-`Stopped`/VM-start-timeout; it is **Running** now — the preflight's docker gate is exactly the right guard for that transient.
     - Increment 4 DONE (`e2e_remote.sh` + Makefile): `make e2e-remote RUNNER=m2 [DIGEST=sha256:…]` → `e2e_runner_dispatch`. Validates RUNNER against an allowlist (`E2E_RUNNER_ALLOWLIST`, default `m2`; value reused verbatim as provenance, never free text) + DIGEST against `^([repo]@)?sha256:<64hex>$` (rejects injection), gates on `e2e_runner_preflight` (busy/capacity/unreachable → abort, **no local fallback**), SSHes the remote `e2e_verify_vcluster <digest>` with `E2E_RUNNER=m2`/runner KUBECONFIG/remote report dir, streams output via `tee` to a local transcript (`~/.k3dm/e2e/dispatch/m2-<ts>.log`), returns the remote exit code unchanged (`PIPESTATUS[0]`). `make e2e` unchanged. BATS 26/26, shellcheck clean, `bash -n` clean; Makefile guard verified (no RUNNER → usage+exit 2). Not live-dispatched (would consume M2 — reserved for the inc-6 acceptance).
     - Increment 5 DONE (`e2e_remote.sh`): restricted M4-side result publisher — public `e2e_result_publish` (SSH forced command) + `e2e_result_publisher_install`. `e2e_result_publish` reads ONE JSON doc on stdin (bounded by `E2E_PUBLISH_MAX_BYTES`=64KB), strict-validates the exact E2E schema via `_e2e_publish_build` (exact allowed-key set → rejects namespace/kubeconfig/labels/annotations injection; required keys; bounded lengths + safe charsets; runner must be a **remote** allowlist member, local-m4 rejected; digest `[repo@]sha256:<64hex>` or null; exit_code 0..255; result pass|fail), then `_kubectl --context k3d-k3d-cluster -n platform-ops apply -f` a **deterministic-name** ConfigMap (`e2e-result-<runner>-<sha256_12(run_id)>`) → **idempotent per run id** (SSH retries can't dup). Hub context + namespace assigned INTERNALLY (never from payload); KUBECONFIG pinned so an inherited/sandbox context can't redirect the write; retention pruning also pinned to the hub context. Redacted audit log (run_id/runner/result/outcome only — no digest/payload). `e2e_result_publisher_install <pub>` writes an idempotent `command="…e2e_result_publish",restrict,no-pty,no-*-forwarding` authorized_keys entry (marker `e2e-m2-publisher`), refuses non-keys. Static disappearance test confirms no scp/rsync/VAULT_TOKEN/cloudflare/StrictHostKeyChecking=no and the M4 publish-kubeconfig never crosses SSH. Also fixed an inc-4 latent bug: `e2e_remote.sh` now self-defines `E2E_REPORT_DIR`/`E2E_RESULT_EVENT_*` defaults (lazy-load sources only the matched plugin, so it can't rely on e2e.sh under `set -u`). BATS 40/40, shellcheck clean, `bash -n` clean; e2e.bats(18)+e2e_observability.bats(11) still green (no regression). Publisher not live-installed (needs the dedicated M2 key — inc-6 acceptance).
     - **Remaining increments:** (6) failure/ops behavior (unreachable/publication_pending replay, M4 status runner health) + 2-run live acceptance (includes the deferred live redeploy of the runner-labelled exporter/dashboard/rule via `argocd.sh`).
  3. `docs/plans/v1.27.0-image-signing-cve-loop-closure.md` — cosign sign+attest, Kyverno Audit→Enforce (multi-repo, heavy).
  4. `docs/plans/v1.27.0-adaptive-checkout-load-testing.md` — API-level checkout load + telemetry.
  Plans #1 and #2 (both promoted from v1.26.0 deferred, 2026-08-21, "keep all four") are the dependency-ordered chain that moves E2E off the laptop — the response to Prometheus+Grafana over-stressing the M4.

- **Deferred findings from v1.26.0** (filed as tracked issues):
  - Finding 1a — ✅ FIXED + live-verified `5cd67228` (was BLOCKING, not cosmetic). `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.
  - Finding 2b — dispatcher `--confirm` strip on `deploy_app_cluster` (OPEN). `docs/issues/2026-08-21-dispatcher-strips-confirm-deploy-app-cluster.md`.

- **v1.25.0 released** (PR #116 `d48e465f`, tag/release live).
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
- **Load-split promoted into v1.27.0** (2026-08-21): the two v1.26.0-deferred plans
  (foundation-managed vCluster CLI → M2 remote E2E runner) are renamed to `v1.27.0-*` and
  are the leading dependency-ordered work. v1.27.0 now holds 4 plan docs (4/5, under cap).
  v1.28.0 planned: parallel multi-cloud provisioning + zero-downtime rollouts.

## Open follow-ups

- **2026-08-22 service-credentials incident** (`docs/issues/2026-08-22-service-credentials-na-multi-root-cause.md`):
  `make show-service-passwords` all-N/A + no login had THREE independent causes.
  (1) ✅ FIXED: `com.k3d-manager.vault-port-forward` plist was missing from
  `~/Library/LaunchAgents/` (only the `vault-failover` watchdog remained, which does
  NOT own :18200) → nothing on 127.0.0.1:18200 → every Vault-sourced cred N/A.
  `make install-vault-port-forward` restored it (Grafana/Alertmanager resolve; ArgoCD
  works via `argocd admin initial-password -n cicd`). (2) Vault KV lost its display-mirror
  paths (only `ldap/`+`observability/` remain); ArgoCD/Prometheus/Alertmanager are NOT
  ESO-managed so services are unaffected — display-only. ArgoCD re-seed one-liner handed to
  user. (3) **Keycloak never deployed on the hub** (no pod/app/keycloak-Vault-paths) → the
  only genuine login blocker (admin + frontend SSO); spec at
  `docs/bugs/2026-08-22-keycloak-not-deployed-on-hub-sso-down.md`. NOTE: hub Prometheus is
  UNAUTHENTICATED (empty `spec.web`, no edge basic-auth; prometheus.3ai-talk.org→:19090→200
  open) — `observability_rotate_prometheus_basic_auth` targets the ACG app cluster, NOT the
  hub, so it was deliberately NOT run. Also Makefile show-service-passwords reads wrong
  keycloak secret name (`keycloak-secrets` vs deploy's `keycloak-admin-secret`).

- **Dependabot alert #6 (js-yaml)** — remediated upstream as lib-foundation `v0.4.11`,
  subtree-pulled (`1bf1d2ce`, vendored lockfile `3.15.1`). Still reads `open` only because
  Dependabot scans the default branch (main = v1.25.0); **auto-closes when v1.26.0 → main.**
  Dev-only transitive dep, low effective risk.
- **Un-fixed findings** (filed as tracked issues, deferred out of v1.26.0):
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
