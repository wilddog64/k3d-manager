# Active Context — k3d-manager

> **Compressed 2026-08-11.** Live focus + carried-forward blockers only. Shipped detail lives in
> `CHANGELOG.md` (v1.24.0 section), `docs/plans/v1.24.0-*`, `docs/bugs/v1.24.0-*`, `docs/retro/`,
> `docs/issues/`, and git history (`git log --follow memory-bank/`).

## Current focus — v1.24.1 RELEASED; v1.25.0 = workstream G (open for development)

**DRY_RUN Phase 2 COMPLETE (2026-08-14):** commit `c8b6a1aa` (`fix(lifecycle): honor DRY_RUN per-op across make up/down for all providers`) is pushed to `origin/k3d-manager-v1.25.0`. Per-operation guards now cover `bin/cluster-up`, `bin/cluster-down`, and all five provider deploy/destroy paths; shellcheck is clean, the relevant lifecycle/provider BATS suite passes 47/47, and dry `make up/down` emits intent without follow-on deployment. Phase 3 remains separate (k3s-aws `make down` deregistration wiring).

**DRY_RUN Phase 2b COMPLETE (2026-08-14):** commit `d2263cc2` is pushed to `origin/k3d-manager-v1.25.0`. The canonical `DRY_RUN` flag and bridged `K3DM_DEPLOY_DRY_RUN` alias now drive `_run_command`, both lifecycle bins, Vault/Jenkins, and dispatcher dry-run gates; cluster-up stops successfully at the Step 4 seam with a plan summary, and cluster-down emits per-operation teardown intent. Stubbed lifecycle BATS (21/21), provider BATS (38/38), and shellcheck passed. Phase 3/4 remain queued.

**DRY_RUN Phase 3 COMPLETE (2026-08-14):** commit `469a3427` is pushed to `origin/k3d-manager-v1.25.0`. `make down` now deregisters the k3s-aws sandbox from hub ArgoCD before teardown, and the local-provider path sources the dry-run bridge before common launchd cleanup. Stubbed cluster-down BATS (12/12) and shellcheck passed; Phase 4 remains queued.

**DRY_RUN Phase 4 COMPLETE + Claude-verified (2026-08-14):** commit `7a34856c` (feature) + `aca42562` (memory-bank, separate) pushed to `origin/k3d-manager-v1.25.0`. Slack `cluster-up`/`cluster-down` now support DRY_RUN preview via env-injection into `_posix_spawn_job`. Independently verified: scope = allow-list only (`bin/cluster-down` NOT in commit), py_compile OK, webhook.bats 54/54 with a genuinely BEHAVIORAL test (SourceFileLoader + spies on `_posix_spawn_job`/`_record_acg_state`/`_run_post_provision_check`/`_push_metrics`), cluster_down.bats 12/12, and Part B mutation check independently reproduced pass→fail→pass. **DRY_RUN Phases 1–4 all shipped; the thread is closed.**

**Tier 2 sandbox harness — ARCHITECTURE LOCKED, NOT handoff-ready (2026-08-14, user chose "design fully first").** D1 RESOLVED → **disposable in-sandbox ArgoCD** (the app-cluster stack — istio-ambient/eso/data-git/services-git — is ApplicationSet-driven keyed on `k3d-manager/role: app-cluster`; install ArgoCD inside the sandbox, label its `in-cluster` secret, apply the same appsets against `kubernetes.default.svc`; kubectl-kustomize alt rejected). Grounding recorded in `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` ("Deploy architecture (resolved)"). **Blocked on a Claude live dry-run** to pin THREE undesigned deploy paths before Codex can get copy-paste code: GAP 1 = in-sandbox ArgoCD install is unsupported (`deploy_argocd_bootstrap` short-circuits on `CLUSTER_ROLE=app`, argocd.sh:969); GAP 2 = Keycloak/identity deploy is not a reusable fn (`services-git` excludes `services/shopping-cart-identity`); GAP 3 = no app-cluster ingress-exposure helper for the Playwright Job. **Next action = Claude live dry-run on a sandbox → pins GAP 1–3 AND moves G past 2/4 (the live Stripe run is Claude's per rules), then write exact `e2e_verify_sandbox`+BATS → Codex handoff.** Tier 2 also creates the shared `scripts/plugins/e2e.sh` scaffolding (`E2E_REPORT_DIR`/`_e2e_write_summary`) carved so Tier 1 layers `e2e_verify_vcluster` in later.

**Tier 2 live dry-run STARTED 2026-08-14 (user: "do 1 first then 2").** Fresh ACG AWS sandbox up via `acg_restart` (creds valid, `arn:…:user/cloud_user`, TTL ~232m). Two blockers + one major design finding surfaced, all BEFORE reaching the Stripe E2E:
> - **BUG (filed) — k3s-aws provisioning cannot install k3s.** `deploy_cluster --provider k3s-aws` stands up the 3 EC2 nodes then dies: `env: 'deploy_app_cluster': No such file or directory`. Root cause `scripts/lib/providers/k3s-aws.sh:178` — `env VAR=val deploy_app_cluster` can't invoke a shell function (`deploy_app_cluster` is one, shopping_cart.sh:1109); drop `env`. Hits both SSM+SSH modes on every fresh provision. Spec: `docs/bugs/v1.25.0-bugfix-k3s-aws-env-cannot-call-deploy-app-cluster.md`. Worked around live (SSH to nodes confirmed reachable).
> - **BUG (filed) — observability DRY_RUN `base64: invalid input`.** The `Reading Alertmanager credentials from Vault` block reads vault-root via `_kubectl … | base64 --decode`; under DRY_RUN `_run_command` prints a `[dry-run] …` banner to stdout that gets piped into `base64 --decode` → `invalid input` + false "Alertmanager Vault secret not found". 5 sites in `observability.sh` (38/200/400/555/579). Fix = plain `kubectl` for the read (precedent cluster-up:409). Spec: `docs/bugs/v1.25.0-bugfix-observability-dryrun-base64-invalid-input.md`.
> - **DESIGN FINDING — Tier 2 splits into 2A vs 2B (reshapes the spec).** Grounding full `bin/cluster-up`: identity (Keycloak+LDAP) is HUB-hosted (`destination: kubernetes.default.svc` = hub), reached from the app cluster via ssh-reverse-tunnel + iptables DNAT + CoreDNS, with the OIDC issuer being the **Cloudflare public** `keycloak.3ai-talk.org`; per-service issuer is baked into each `shopping-cart-*/k8s/base` repo. So D1 "in-sandbox ArgoCD + same 4 appsets" covers apps/data/mesh/secrets but **NOT identity/OIDC**. Two shapes: **2A** fully self-contained (re-home identity + local issuer + per-service cross-repo overrides — weeks-scale bespoke) vs **2B** self-contained apps + shared hub identity via existing tunnel/Cloudflare issuer (still never `register_app_cluster` → no orphan; ~80/20, unblocks G now). Full detail in scratchpad `tier2-dryrun-findings.md`. **Awaiting user 2A-vs-2B decision.**

**Scope split executed 2026-08-13 (user decision).** The branch formerly named `k3d-manager-v1.25.0`
held only status/observability work (zero G implementation), so it was **renamed to
`k3d-manager-v1.24.1`** and was cut as a point release; `v1.25.0` is reserved for **workstream G**.

### v1.24.1 (point release) — RELEASED
Content (implemented + live-verified): status-output contract (concise/JSON `make status` + `SERVICE=`
focus, `7ed82b89` + status fixes), Slack `/cluster-status` concise-summary wiring (`5b9442cf`),
CVE-dashboard/exporter cleanup (`a119fdde`, `d471d075`). Dependabot auto-merge observability = scoped
spec only (not implemented; doc renumbered to v1.24.1).
- **Done 2026-08-13:** branch renamed `v1.25.0`→`v1.24.1` (old remote deleted); dashboards appset
  (`grafana-dashboards-hub`/`-acg`) repointed to `k3d-manager-v1.24.1`, `hub-grafana-dashboards`
  Synced/Healthy; plan/bug docs renumbered `v1.25.0-*`→`v1.24.1-*` (kept `v1.25.0-e2e-*` as G);
  CHANGELOG `[1.24.1]`, README releases table (3-most-recent, de-duplicated) + Issue Logs (5 newest) +
  `docs/releases.md`.
- **Released 2026-08-13:** PR #115 merged to main (e7a32bb9), tag v1.24.1 created and pushed, GitHub
  release published. `enforce_admins` branch protection restored. Retrospective filed
  (`docs/retro/2026-08-13-v1.24.1-retrospective.md`). Three Copilot findings addressed (Makefile
  shell-injection quoting + roadmap/plan-header doc sweep). **Partial hub repoint complete**
  (dashboards appset repointed to v1.24.1, Synced/Healthy). **Full repoint deferred** to v1.25.0
  release-ops (`observability` + `observability-acg` + `services-git` still track v1.23.0; safe to defer
  until v1.25.0 ships, do NOT delete v1.23.0 branch yet).

### v1.25.0 = workstream G (branch created, ready for development, BLOCKED cross-repo)
Stripe/Go live acceptance (stuck 2/4) + E2E verification harness (Tier 1 vCluster blocking + Tier 2 ACG
sandbox periodic) + e2e observability. Plan docs `v1.25.0-e2e-*`. **Branch created 2026-08-13** from
merged main (`e7a32bb9`, inherits v1.24.1, no back-merge; avoids divergent `vulnerability-inventory-exporter.yaml`
— v1.24.1 touched it via `a119fdde`, e2e-observability plan #2 edits it again). Critical path: build the
harness (buildable now, not blocked) → run the Stripe E2E on Tier 2 to move G past 2/4. Roadmap order:
v1.24.1 → v1.25.0-G → v1.26 → v1.27 → v1.28.

### E2E harness Tier 1 — IMPL spec written 2026-08-14 (Claude), ready for Codex handoff
Impl-grade spec: `docs/plans/v1.25.0-e2e-harness-tier1-impl.md` (plan #3 for v1.25.0; within ≤5 cap).
**Locked decisions (user, 2026-08-14):** (1) execution = spec→Codex handoff; (2) runner placement =
in-cluster Playwright **Job** (ClusterIP DNS, not host port-forward); (3) test delivery = build+publish a
dedicated e2e image to GHCR (`ghcr.io/wilddog64/shopping-cart-e2e-tests`), Job pulls pinned digest;
(4) standing rule — every major tech gets a learning guide → this release ships
`docs/guides/vcluster-e2e-harness.md` (memory `feedback_guide_per_major_tech`).
**Key discovery:** existing `shopping_cart_reconcile_*` are hardcoded to the live app cluster
(`--context ubuntu-k3s`, ESO/Vault/Postgres) — NOT reusable for a throwaway vCluster. The real Tier 1 core
is a **self-contained substrate bundle** `scripts/etc/e2e/` (3 services + minimal postgres/redis + seed, no
ESO/Vault/ArgoCD, `OAUTH2_ENABLED=false`), derived from the e2e repo's `docker-compose.yml` (the
service+datastore contract) + each service's `k8s/base`. Actual Playwright project is `flows` (not `flow`);
JSON report → `test-results/results.json`. Scope = Tier 1 only (Part 1 e2e-image+workflow_call + Part 2
`e2e_verify_vcluster`); Tier 2 `e2e_verify_sandbox` + exporter/dashboard deferred (plan #2 / v1.26.0).
**Strategic note (unresolved, for user):** for unblocking **G's Stripe acceptance** specifically, Tier 2
(ACG sandbox full-stack via existing bring-up) may be the SHORTER path — it runs the Stripe E2E and reuses
the normal stack, whereas Tier 1 requires inventing the minimal bundle. Tier 1 mainly serves the v1.26.0
per-candidate gate. Not yet decided whether to build Tier 1 first (current plan) or jump to Tier 2 for G.
Not yet handed off to Codex.

### ACG cleanup + Tier 2 self-contained — specs written 2026-08-14 (Claude); user chose "start with ACG"
- **G unblock finding:** the order schema blocker (`order_items.total_price NOT NULL`) is ALREADY resolved on
  `origin/main` (`cb58e8b`, PR #67 — squash-merge, so `0e3feb9` reads as not-ancestor: false-negative per
  `reference_squash_merge_branch_cleanup_safety`) and the order image promoted (`df35ea8`). G's remaining work
  = **rerun** the Stripe live E2E on a real substrate (Tier 2), not a code fix.
- **Root cause of ArgoCD "unknown resources" after sandbox death:** `_provider_k3s_aws_destroy_cluster`
  (k3s-aws.sh) is the ONLY app-cluster provider with no hub-deregister step (OCI + hostinger both have
  `_<p>_deregister_cluster`). It tears down CFN + tunnel but never deletes the hub `cluster-ubuntu-k3s` Secret
  / generated Apps → they go `Sync: Unknown`. **Registration is opt-in** (`deploy_app_cluster` does NOT
  auto-register; prints "Then run: register_app_cluster").
- **Two specs written (user greenlit both):**
  (a) `docs/bugs/v1.25.0-bugfix-k3s-aws-hub-deregister.md` — add `_k3s_aws_deregister_cluster` (delete
      `cluster-ubuntu-k3s` + generated `destination.name==ubuntu-k3s` Apps, finalizers stripped) and call it in
      `destroy_cluster` before `acg_teardown`. Graceful-teardown safety net only; TTL-expiry watchdog stays
      v1.26.0. Implemented and pushed as `d6217640`; shellcheck and provider BATS gates passed.
  (b) `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` (plan #4) — `e2e_verify_sandbox` runs the full stack +
      Stripe live E2E in-sandbox with `OAUTH2_ENABLED=true`, **INVARIANT: never calls `register_app_cluster`**
      (self-contained island → nothing to orphan on TTL expiry). This is the shortest path to G past 2/4.
- **v1.25.0 plan-doc count = 4** (observability-path-a, verification-harness, tier1-impl, tier2-sandbox); within
  ≤5 cap. Neither harness spec handed off yet.
- **Dependabot check (payment PR #53):** benign auto-close (superseded); bcprov 1.85→1.85.2 now in open group
  PR #62 (main still 1.85). #62 is MERGEABLE but BLOCKED by a **Checkstyle & SpotBugs failure** (NOT the
  PACKAGES_TOKEN/401 issue). Payment has ~10 stacked dependabot PRs; #60 (built-in GITHUB_TOKEN) unblocks the
  PAT-rotation ones. Not yet actioned.

This branch (now `k3d-manager-v1.24.1`) is based on merged `main` (`fd281c85`). Its queued scope now contains three
implementation-grade plans: `docs/plans/v1.25.0-e2e-verification-harness.md`,
`docs/plans/v1.25.0-e2e-observability-path-a.md`, and
`docs/plans/v1.25.0-dependabot-automerge-observability.md` (event-driven Dependabot auto-merge
monitoring with Grafana/Alertmanager visibility), plus
`docs/plans/v1.25.0-status-output-contract.md` (concise color-coded `make status` with failed-service
health/HTTP codes, `SERVICE=<name>` focused diagnostics, full and JSON modes). Implementation is not started.
The status refactor is now implemented on this branch and live-verified healthy after the
webhook login credential/KUBECONFIG fix (`fix(status): use current Vault credentials for login smoke`).
**Status source verified 2026-08-12:** `bin/k3dm-webhook-setup` restored the existing 64-byte
Keychain token, refreshed the GitHub secret, and reinstalled the LaunchAgent; health endpoint HTTP 200.
Concise status now works. It reports separate Keycloak, ArgoCD, and Grafana login 401 failures plus
expected ESO/data-layer warnings; see `docs/issues/2026-08-12-webhook-token-restored-status-verification.md`.
Follow-up fixed provider selection from the active-provider file and classified optional Pushgateway
refusal as a warning; remaining login 401s are genuine service credential issues. See
`docs/issues/2026-08-12-status-provider-and-optional-pushgateway.md`.
The login checks are now green after reading hub-scoped Keycloak credentials and current ArgoCD/Grafana
values from Vault; the LaunchAgent renderer now substitutes the real HOME in KUBECONFIG. See
`docs/issues/2026-08-12-status-login-credentials-and-launchagent-kubeconfig.md`.
`make status-json` now follows the active provider as well as `make status`; the live JSON result is
`overall=healthy`, provider `k3s-hostinger`. See `docs/issues/2026-08-13-status-json-default-provider.md`.
Stale Istio `ubuntu-k3s` Applications were diagnosed as deletion-tombstoned objects targeting retired
`host.k3d.internal`; their finalizers were removed and ArgoCD deleted them. Hostinger Istio remains
Synced/Healthy. See `docs/issues/2026-08-13-stale-istio-ubuntu-k3s-applications.md`.
The CVE remediation dashboard cleanup is implemented: exporter events now expose `current=true` and
mark superseded failed events; Grafana separates Current Remediation Status from Remediation History.
Historical ConfigMaps remain intact. See the updated `docs/issues/2026-08-12-cve-remediation-failed-history-investigation.md`.
The mistaken `docs/argocd-login-smoke-diagnosis` branch was closed/deleted and is not part of v1.25.0.

### Branch-hygiene reconciliation — 2026-08-13 (Claude)

Post-v1.23.0-release work had been committed onto the **released, dead-end `k3d-manager-v1.23.0`
branch** and was stranded (v1.23.0 was squash-merged as `7253ece4`, so those commits never reach a
forward branch). Reconciled onto `v1.25.0`:

- **Orphaned future plans rescued + renumbered** (`4cdd7abf`): resolved a v1.26.0 collision (image-signing
  vs new sandbox-cleanup). **User decision: sandbox-registration=v1.26.0, image-signing=v1.27.0,
  zero-downtime=v1.28.0.** `docs/plans/v1.26.0-sandbox-registration-lifecycle-cleanup.md` moved as-is;
  `v1.26.0-image-signing-cve-loop-closure.md` → `v1.27.0-…`; `v1.27.0-platform-zero-downtime-rollouts.md`
  → `v1.28.0-…`; internal refs + `docs/roadmap.md` "Queued milestones" reconciled.
- **Live CVE dashboard + exporter forward-ported** (`a119fdde`): the concise-header dashboard cleanup and
  exporter `deployment_advanced`/`display_reason` logic existed only on v1.23.0 (which the hub
  `hub-grafana-dashboards` ApplicationSet **currently tracks**). Both files were a strict superset of the
  v1.25.0 versions; carried onto v1.25.0. YAML-parse + embedded-python checks clean.

**Dashboards repointed live 2026-08-13 (Claude):** `grafana-dashboards-hub` + `grafana-dashboards-acg`
appsets reapplied with `K3D_MANAGER_BRANCH=k3d-manager-v1.25.0`; live `hub-grafana-dashboards`
Application now `targetRevision=k3d-manager-v1.25.0`, **Synced/Healthy** (forward-port is byte-identical
to live → no drift). Repointed to v1.25.0 (not v1.24.0) because v1.24.0's dashboard is the older verbose
version — pointing there would revert the live cleanup.
**⚠️ STILL on `k3d-manager-v1.23.0`:** `observability`, `observability-acg`, `services-git` (the exporter
is synced by `observability`, not the dashboards appset). They keep serving the correct (identical)
content, so nothing reverts — but **do NOT delete the v1.23.0 branch until these are repointed too.**
That is a release-grade full-hub repoint (services-git pulls service-manifest deltas), best done when
v1.25.0 is cut; confirm with `argocd_check_values_branch`. **Process:** forward work goes on `v1.25.0`,
never a released branch.

### Slack `/cluster-status` concise-summary wiring — IMPLEMENTED 2026-08-13 (Claude)

Spec `docs/bugs/v1.25.0-bugfix-slack-cluster-status-summary-wiring.md` (`2094398e`); fix `5b9442cf`
(`bin/k3dm-webhook`). `_run_hostinger_status` now runs `bin/cluster-status --json` (token passed via env
so no Keychain read; `NO_COLOR=1`), parses the last JSON line, and renders a concise Slack summary via new
`_format_status_summary_slack` — emoji severity (`:x:`/`:warning:`/`:white_check_mark:`/`:grey_question:`)
+ `N ok / N warn / N fail` counts + error/warning lines, **no ANSI**, raw-report fallback retained.
**Verified static:** py_compile clean; formatter unit-exercised (fail/healthy/unknown → correct emoji, no
ANSI); webhook.bats 53/53. **Scoped OUT:** `_run_cluster_status` (ACG path) — bespoke reachability report,
already emoji-based, not backed by `cluster-status --json` (documented non-goal in the spec).
**Live-verified 2026-08-13:** `make restart-webhook` done (health 401 = up+auth). End-to-end smoke with
real cluster data — `CLUSTER_PROVIDER=k3s-hostinger bin/cluster-status --json` → exit 0, 13 services
healthy; fed through the live `_format_status_summary_slack` →
`:white_check_mark: *Cluster status: HEALTHY* — \`k3s-hostinger\`  (13 ok / 0 warn / 0 fail)` (no ANSI).
Only an actual Slack `/cluster-status` trigger (user action) remains as final confirmation.

## Current focus — v1.24.0 CODE-COMPLETE + LIVE-VERIFIED; release complete

**v1.24.0 = platform hardening (D+E+F+#18).** All code committed + pushed to
`origin/k3d-manager-v1.24.0`, Claude-verified on origin. CHANGELOG + README + `docs/releases.md`
written. **Next: PR gate → merge → tag → reapply ApplicationSets (hub + ACG) → confirm
`argocd_check_values_branch`.**

| Slice | Commit(s) | State |
|---|---|---|
| D — webhook auth fail-closed + Slack allowlist enforcement | `3fddcf3e`; hostinger truncation `8eb8cc34` | live; py_compile + webhook.bats 53/53 |
| F — Istio ambient / hostinger CNI drift reconcile onto release branch | `357edf52` | shellcheck + YAML pass |
| E — Prometheus weak-default removal + ArgoCD/Prometheus rotators + 4 live-verify bugfixes | `e1256d0a`, `3db193cb`, `84232cc0` | LIVE-VERIFIED (see below) |
| #18 — CVE promoter persists to git | `3df62fbf` | dry-run verified live (see below) |
| agy headless analyze fix | `69e21e15` | live-smoked (real analysis text) |
| show-service-passwords ArgoCD reads Vault | `33e42905` | shown password logs in |

### Live-verify state (release-ops, done 2026-08-11)

- **E ArgoCD rotator DEPLOYED + verified live:** rotator manifest applied + Vault `argocd-rotation`
  policy/role created via `deploy_argocd_platform_ops`; one-shot Job rotated → `argocd-secret` mtime
  advanced, stored bcrypt clean/valid, new Vault password → ArgoCD `/api/v1/session` **LOGIN SUCCESS**
  (wrong pw rejected as control). Prometheus host-side launchd agent installed + rotate regenerated a
  strong bcrypt on `ubuntu-hostinger`. **The live ArgoCD admin password is now the ROTATED value**
  (old bcrypt `$2y$10$AgfGS5Vm…390Uqy.` retained as manual restore net; new plaintext in Vault
  `secret/argocd/admin`). ⚠️ **Restore-on-failure path is code-present (trap) but not fault-injected**
  (avoided breaking the live credential).
- **#18 promoter git-persist DRY-RUN verified live:** exercised `_git_persist_promotion`'s exact path
  non-destructively — clone release branch via `x-access-token:` URL (exit 0), real `set_image_digest.awk`
  on `services/shopping-cart-order/kustomization.yaml` (appended `images:` block correctly),
  promoter-author local commit, `git push --dry-run origin HEAD:k3d-manager-v1.24.0` → exit 0
  (**token authenticates WRITE**). Remote untouched.
  - ⚠️ **INTERIM TOKEN — MUST REPLACE before in-cluster promoter use.** Keychain
    `platform-ops-git-writer`/`k3dm` currently holds `gh auth token` (`repo` scope) — acceptable ONLY
    for the local dry-run (runs as the user). Before the promoter runs **in-cluster** (token lives in
    a cluster Secret), replace with a dedicated **fine-grained `contents:write`-only PAT** on
    `wilddog64/k3d-manager`, then re-run `argocd_sync_git_writer_secret platform-ops`. The full E deploy
    already brought the promoter code live with `GIT_WRITE_TOKEN` `optional:true` (safe live-patch fallback).

### Follow-up (non-blocking)

- Update auto-memory `reference_trivy_critical_upstream_image_noise` "still errors" note once a real
  `wilddog64/*` TrivyCritical analyze is observed posting real text via the `69e21e15` fix.
- **CVE remediation dashboard history (investigated 2026-08-12):** the displayed `ready_pod_digest_mismatch`
  rows are retained Aug 6/Aug 9 historical events. Payment has later `applied` events; current order/payment
  workloads are healthy. The flat panel does not collapse superseded failures. Follow-up issue:
  `docs/issues/2026-08-12-cve-remediation-failed-history-investigation.md`.

## Pending releases (forward scope)

- **v1.25.0 = Stripe/Go live acceptance + hostinger capacity (G, BLOCKED, cross-repo).** Merge
  order-repo `0e3feb9` schema fix (`order_items.total_price NOT NULL`) + promote image → rerun Stripe
  live E2E (2/4 now). **Live deadlock stopgapped 2026-08-10** (`docs/issues/2026-08-10-hostinger-rollout-deadlock-maxsurge-on-2cpu-node.md`):
  order/basket wedged mid-rollout — `maxSurge=1` needs 2× CPU on a 95%-full 2-CPU node → `FailedScheduling`;
  live-patched both to `maxSurge=0/maxUnavailable=1`, converged. **Durable fix = this workstream:** commit
  `maxSurge=0` into app git manifests (ArgoCD may selfHeal the live patch away) OR bump node CPU.
  **+ E2E verification harness (plan doc #1 `v1.25.0-e2e-verification-harness.md`):** enable the disabled
  e2e suite on ephemeral substrates — Tier 1 vCluster (per-candidate blocking, `OAUTH2_ENABLED=false`) +
  Tier 2 ACG sandbox (periodic full-stack, real ingress/OIDC, runs Stripe live E2E). Substrate-agnostic
  (needs basket/catalog/order URLs + oauth flag); new `scripts/plugins/e2e.sh`; `workflow_call` on
  `shopping-cart-e2e-tests`. Exit-code + JSON-summary contract seeds the v1.26.0 gate.
  **+ e2e observability (plan doc #2 `v1.25.0-e2e-observability-path-a.md`):** reuse the CVE exporter seam
  — harness writes a `k3dm.k3d.io/e2e-result=true` ConfigMap; extend `vulnerability-inventory-exporter.py`
      to emit `e2e_*` gauges; new `grafana-dashboard-e2e.yaml` + `E2EVerificationFailing/Stale` rules; deploy
      via `argocd.sh`. No new component, no Tempo (span tracing = separate forward theme).
      **+ Dependabot auto-merge observability (plan doc #3 `v1.25.0-dependabot-automerge-observability.md`):**
      signed GitHub PR/check/workflow events plus 15-minute read-only reconciliation feed bounded
      Prometheus metrics, Grafana panels, and owned Alertmanager Slack alerts. Monitor never merges or
      changes branch protection; implementation not started.
- **v1.26.0 = image signing + attestation — close the CVE loop (SCOPED, not started).** Spec
  `docs/plans/v1.26.0-image-signing-cve-loop-closure.md`. cosign sign + Trivy vuln/SBOM attest at build;
  `cosign verify` at promotion (promoter gate) AND admission (Kyverno, staged Audit→Enforce, app
  namespaces only, upstream/`tier:upstream` excluded). Key-based, private key in Vault + Keychain backup,
  pub via ESO (LOCKED, not keyless). Multi-repo: k3d-manager `signing.sh`/Kyverno/ClusterPolicy/promoter
  gate + shopping-cart `{order,payment,basket,frontend,product-catalog}` CI. CI key delivered as GH
  secrets seeded from Vault (runners can't reach Vault). Slots after v1.25.0. See
  [[project_image_signing_cve_loop]].

## Backlog / queued (not release-gated)

- **Secure Vault remote access (QUEUED — start after v1.24.0 release).** Expose the **Vault UI** via the
  existing laptop cloudflared as `vault.3ai-talk.org → http://localhost:18200`, gated by **Cloudflare
  Access** with **MFA = Google IdP** (TOTP). Two gates: Access (identity+MFA) then Vault login
  (userpass/OIDC — NOT root token). **Non-negotiable build order:** create the Access application +
  default-deny allow-only-me policy FIRST, THEN add cloudflared ingress + proxied DNS; verify an
  anonymous request redirects to Access before trusting. Enable a Vault audit device; root token
  laptop-only (break-glass). Vault today has NO public path (reverse-tunnel loopback only). Filing
  (decision pending): `docs/howto/secure-vault-remote-access-cloudflare-access.md`. No changes made yet.
  See [[project_secure_vault_remote_access]].
- **Jenkins DEPRECATED in docs — DONE 2026-08-10, code KEPT.** Built-in but unused (no live pods, opt-in
  `ENABLE_JENKINS=1` only, not in roadmap; real CI/CD = GHA+ArgoCD). Marked deprecated in current-state
  docs; historical docs untouched. Earlier code-retirement plan **cancelled**. See
  [[project_jenkins_deprecation]].
- Dashboard parts (b)+(c) — spec `v1.23.0-cve-dashboard-parts-bc-*` superseded by the Codex 1:1 dashboard;
  re-scope before executing. `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`
  carry; the observability.sh E per-hunk carry was **VACUOUS** (empty diff) → dropped.
- Shopping-cart Dependabot backlog (Go builder-image bumps, majors held) — `project_backlog.md`.
- rabbitmq-client-java NPE fix `36ed860` — JAR publish + pom update pending.

## Recently shipped (pointers only — detail in CHANGELOG + retro)

- **DRY_RUN Phase 4 COMPLETE (2026-08-14):** `7a34856c` pushed to `origin/k3d-manager-v1.25.0`.
  Slack `cluster-up`/`cluster-down` now parse provider and dry-run tokens in any order, inject
  `DRY_RUN=1` into the spawned make job, skip post-provision/metrics side effects for previews,
  and document the command syntax. Behavioral webhook BATS (54/54), cluster-down BATS (12/12),
  py_compile, agent lint/audit, and isolated smoke test passed. Mutation check was pass → fail
  after removing the `*)` bridge source → pass after restoration; `bin/cluster-down` remained
  unchanged. `make restart-webhook` intentionally deferred for Claude's live process.

- **PR #113 Copilot follow-up (2026-08-11):** six actionable review threads addressed and resolved in
  `be29b5a0` (credential exposure, portability, launchd PATH, and test dependency). CI is green; PR
  remains review-gated pending an approving reviewer.

- **v1.23.0** RELEASED — CVE observability + remediation lifecycle (B+C). PR #112 `7253ece4`, tagged;
  platform-ops deployed live (alert-noise split active), retro `docs/retro/2026-08-09-v1.23.0-retrospective.md`.
- **v1.22.0** RELEASED — OpenLDAP bitnami→Symas migration. PR #111 `1bbb74b0`, tagged.
- **v1.21.0** RELEASED — webhook security hardening. PR #110 `f68bdee1`, tagged.
- **v1.20.0** RELEASED — CVE auto-patch-loop hardening. PR #109 `9da73458`, tagged.
- Stripe checkout A–F all MERGED to main across the 5 shopping-cart repos (2026-08-02); payment side
  live on hostinger. Remaining live-acceptance work = v1.25.0 (workstream G).
