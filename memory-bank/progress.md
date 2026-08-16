# Progress — k3d-manager

> **Compressed 2026-08-11.** Shipped-release detail lives in `CHANGELOG.md` + `docs/retro/`; per-incident
> detail in `docs/issues/` / `docs/bugs/`. Pre-compression history is in git (`git log --follow memory-bank/`).

## Releases

| Version | Theme | State |
|---|---|---|
| v1.24.1 | status output contract + observability polish (point release) | RELEASED — PR #115 merged (e7a32bb9), tag v1.24.1 created + pushed, GitHub release published. Retrospective filed. Copilot findings fixed (Makefile quoting + roadmap sweep). Partial hub repoint (dashboards appset Synced/Healthy). Content: status modes (`7ed82b89`), Slack `/cluster-status` summary (`5b9442cf`), CVE-dashboard cleanup (`a119fdde`,`d471d075`) |
| v1.24.0 | platform hardening (D+E+F+#18) | RELEASED — PR #113 `fd281c85`, tagged v1.24.0 + GitHub release |
| v1.23.0 | CVE observability + remediation lifecycle (B+C) | RELEASED — PR #112 `7253ece4`, tagged; platform-ops deployed live, `enforce_admins` restored |
| v1.22.0 | OpenLDAP bitnami→Symas migration | RELEASED — PR #111 `1bbb74b0`, tagged |
| v1.21.0 | k3dm-webhook security hardening | RELEASED — PR #110 `f68bdee1`, tagged |
| v1.20.0 | CVE auto-patch-loop hardening | RELEASED — PR #109 `9da73458`, tagged |
| v1.18.0 | first-mile CVE gap closure | RELEASED — PR #108 `85742ef7`, tagged |

(v1.19.0 was a shopping-cart-only Dependabot milestone — no k3d-manager tag.)

## v1.24.1 shipped commits (2026-08-13)

| Work item | Commit(s) | Verify |
|---|---|---|
| Status output contract (concise/full/JSON modes + provider-aware + SERVICE focus) | `7ed82b89` | shellcheck, BATS (summary), live `make status-json overall=healthy` |
| Slack `/cluster-status` concise-summary wiring | `5b9442cf` | py_compile, webhook.bats 53/53, live emoji/count output verified |
| CVE remediation dashboard cleanup (current vs history split) | `a119fdde`, `d471d075` | YAML/JSON parse, exporter `current/superseded` flags, live reapply done |
| Copilot follow-up fixes (Makefile quoting + roadmap/plan-header sweep) | `68fe1b88` | Make dry-run, static doc refs verified |

**RELEASED 2026-08-13:** PR #115 (e7a32bb9) merged to main; v1.24.1 tag created + pushed; GitHub
release published; `enforce_admins` restored; retrospective filed (`docs/retro/2026-08-13-v1.24.1-retrospective.md`).

## v1.24.0 shipped commits (2026-08-11)

| Work item | Commit | Verify |
|---|---|---|
| Webhook auth fail-closed + Slack allowlist enforcement (D) | `3fddcf3e` | py_compile + webhook.bats; live 401/403 |
| Hostinger status report head/tail truncation (D) | `8eb8cc34` | webhook.bats 53/53 |
| Istio ambient / hostinger CNI drift reconcile (F) | `357edf52` | shellcheck + YAML |
| Prometheus weak basic-auth default removal (E) | `e1256d0a` | weak-hash grep empty, 13 observability BATS |
| Monthly ArgoCD + host-side Prometheus rotators (E) | `3db193cb` | argocd/observability BATS, shellcheck, plist |
| ArgoCD rotator bcrypt/sidecar + Prometheus launchd path (E bugfix, 4 live-verify defects) | `84232cc0` | argocd.bats 17/17, observability.bats 14/14 |
| Git-persisted CVE remediation promoter (#18) | `3df62fbf` | shellcheck/POSIX/YAML; dry-run verified live |
| agy headless analyze fix | `69e21e15` | webhook.bats 53/53; live real-analysis smoke |
| show-service-passwords ArgoCD reads Vault | `33e42905` | shown password logs in |

**LIVE-VERIFIED 2026-08-11:** E ArgoCD rotator deployed via `deploy_argocd_platform_ops` (Vault
`argocd-rotation` role created); one-shot Job → `argocd-secret` mtime advanced, clean bcrypt, new password
→ ArgoCD LOGIN SUCCESS; Prometheus host launchd installed + rotate regenerates strong cred. #18 promoter
git-persist dry-run end-to-end (clone → awk-pin → `push --dry-run` authenticates), remote untouched.
⚠️ Interim git-writer token (`gh auth token`, `repo` scope) must be replaced with a fine-grained
`contents:write`-only PAT before the promoter runs in-cluster — see `activeContext.md`.

**PR #113 review follow-up 2026-08-11:** Copilot's six actionable threads were fixed and resolved in
`be29b5a0`; local BATS/shellcheck/static parse gates passed and GitHub CI is green. PR is mergeable but
still requires an approving review.

## Pending releases (forward scope — detail in activeContext.md)

- [ ] **BUG spec (2026-08-14) — k3s-aws provisioning cannot install k3s.** `env: 'deploy_app_cluster':
      No such file or directory` at `k3s-aws.sh:178` (`env VAR=val` can't call a shell function). Fix =
      drop `env`. Blocks every fresh k3s-aws bring-up. Spec:
      `docs/bugs/v1.25.0-bugfix-k3s-aws-env-cannot-call-deploy-app-cluster.md`. **DONE** — `7a24d768`
      pushed; export-then-call matches `_dry_guard` direct argument handling; shellcheck and provider
      BATS 8/8 passed.
- [ ] **BUG spec (2026-08-14) — observability DRY_RUN `base64: invalid input`.** 5× `_kubectl get secret
      vault-root … | base64 --decode` in `observability.sh` pipe the `[dry-run]` preview banner into
      base64; fix = plain `kubectl` for the read. Spec:
      `docs/bugs/v1.25.0-bugfix-observability-dryrun-base64-invalid-input.md`. Not yet handed off.
- [ ] **Tier 2 live dry-run (2026-08-14) — 2A/2B decision pending.** Sandbox up; found identity is
      hub-hosted w/ Cloudflare issuer → D1 "same appsets" doesn't cover identity/OIDC. 2A (fully
      self-contained, weeks-scale cross-repo) vs 2B (shared hub identity, ~80/20, unblocks G, still no
      hub registration). Detail scratchpad `tier2-dryrun-findings.md`. Awaiting user pick.

- [x] **DRY_RUN Slack Phase 4 (2026-08-14):** `7a34856c` pushed to `origin/k3d-manager-v1.25.0`.
      Provider/dry-run token parsing, env injection, preview side-effect suppression, and help/docs
      are implemented. Webhook BATS 54/54, cluster-down BATS 12/12, py_compile, smoke, and mutation
      pass→fail→pass gates passed; `make restart-webhook` deferred to Claude for live pickup.

- [x] **Standalone cluster-down ArgoCD plugin path (2026-08-14):** `d02c8e92` pushed. Exported
      `PLUGINS_DIR` fixes lazy `argocd.sh` loading under `set -u`; bug report and regression test
      added. Cluster-down BATS 13/13 and shellcheck passed.

- [x] **Cluster-up Step 1 recursion (2026-08-14):** `d793a1d5` pushed. Removed the redundant
      post-plugin `_run_command` re-wrap that caused a near-100% CPU infinite recursion during
      AWS credential validation; bug report and regression test added. Cluster-up BATS 7/7 and
      shellcheck passed.

- [x] **v1.25.0 branch created** from merged main (e7a32bb9) with four queued plans: E2E verification,
      E2E observability, event-driven Dependabot auto-merge monitoring/Grafana visibility; no
      unrelated ArgoCD diagnosis branch content carried forward. Ready for development (workstream G).

- [ ] **v1.25.0** — Stripe/Go live acceptance + hostinger capacity (G, BLOCKED, cross-repo). Merge
      order-repo `0e3feb9` schema fix + promote image → rerun Stripe live E2E (2/4 now); hostinger capacity
      (durable `maxSurge=0` in git OR bump node CPU — issue `2026-08-10-hostinger-rollout-deadlock-*`).
      **+ E2E verification harness** (plan doc #1) + **e2e observability** (plan doc #2) — enable disabled
      e2e on ephemeral substrates (Tier 1 vCluster blocking + Tier 2 ACG sandbox periodic); exit-code +
      JSON-summary contract seeds the v1.26.0 gate.
      **+ Dependabot auto-merge observability** (plan doc #3) — signed GitHub event intake, bounded
      Prometheus state, Grafana panels, Alertmanager Slack alerts, and read-only reconciliation fallback.
      Plan committed on `v1.25.0`; implementation not started.
- [ ] **v1.25.0 E2E harness Tier 1 — IMPL spec written** (`docs/plans/v1.25.0-e2e-harness-tier1-impl.md`,
      2026-08-14). Decisions locked: in-cluster Playwright Job + build/publish dedicated e2e image +
      spec→Codex handoff + guide-per-tech (`docs/guides/vcluster-e2e-harness.md`). Core = self-contained
      `scripts/etc/e2e/` substrate bundle (no ESO/Vault/ArgoCD). NOT yet handed off. Strategic open Q: Tier 2
      may be shorter path to G's Stripe acceptance — Tier 1 mainly serves v1.26.0 gate.
- [ ] **v1.25.0 ACG cleanup bugfix — spec written** (`docs/bugs/v1.25.0-bugfix-k3s-aws-hub-deregister.md`,
      2026-08-14). k3s-aws `destroy_cluster` lacks a hub-deregister (only provider missing it) → expired
      sandbox leaves `cluster-ubuntu-k3s` + `Unknown` Apps. Add `_k3s_aws_deregister_cluster`; graceful-teardown
      safety net only (TTL-expiry watchdog = v1.26.0). **DONE** — `d6217640`, pushed to
      `origin/k3d-manager-v1.25.0`; DRY_RUN, targeted cleanup, finalizer removal, and idempotent BATS
      coverage passed with shellcheck and the 60-test provider suite.
- [ ] **v1.25.0 DRY_RUN cluster-lifecycle Phase 2 — REJECTED at verify (`c8b6a1aa`, on origin).** Partial impl.
      PASS: scope=7 files, commit msg verbatim, shellcheck clean ×7, k3s-aws deregister NOT double-guarded,
      OCI interactive `read` kept outside guard, hostinger `_uninstall_rc` preserved, `bin/cluster-down` fully
      covered. **FAIL (blocker): `bin/cluster-up` guards STOP at line 364** (last `_dry_guard`); the entire macOS
      access layer after it is UNGUARDED — argocd-browser (~509–591), keycloak-browser (~1200–1238), loopback
      alias (~1364–1410), frontend-browser (~1461–1478), named tunnel (~1717–1719): 17 `_run_command
      --interactive-sudo/--prefer-sudo` mutations. **Split-brain root cause:** the new guards read `DRY_RUN`
      (`_dry_run_active`, system.sh:1717) but `_run_command`'s pre-existing dry-run reads a DIFFERENT var
      `K3DM_DEPLOY_DRY_RUN` (system_overrides.sh:30; also vault.sh ×3, jenkins.sh, dispatcher k3d-manager:530).
      The two are unbridged → under `DRY_RUN=1 make up` those sudo ops (system-keychain `security add-trusted-cert`,
      `launchctl bootstrap system`, `ifconfig lo0 alias`) EXECUTE. DoD "touches nothing" gate is violated; Codex's
      "47/47 / no follow-on deployment" claim is the pre-existing suite — **NO new BATS added** (commit touched 0
      test files). Also `bin/cluster-down` coarse-wraps 22 mac ops in ONE `_info "would unload local launchd
      agents…"` (safe but plan is inaccurate vs spec 2a per-op). **Remediation = Phase 2b:** (1) bridge the two
      vars — `_dry_run_active` also true when `K3DM_DEPLOY_DRY_RUN=1`, and/or `_run_command` also honors `DRY_RUN`;
      (2) guard cluster-up lines >364; (3) split the coarse cluster-down block; (4) add the BATS. Phase 3/4 stay
      blocked. Do NOT proceed to release with Phase 2 as-is.
- [x] **v1.25.0 DRY_RUN Phase 2b — COMPLETE** (`d2263cc2`, pushed to `origin/k3d-manager-v1.25.0`, 2026-08-14),
      spec `docs/bugs/v1.25.0-bugfix-dry-run-phase2b-standardize-and-complete.md`. Owner decision honored:
      standardize on **`DRY_RUN`** canonical; `K3DM_DEPLOY_DRY_RUN` = bridged deprecated
      alias. make-up strategy = **guard-core + plan-and-exit** (owner-selected; a true dry-run has no cluster to
      configure). **Part A (keystone):** override `_dry_run_active` in `system_overrides.sh` to honor both vars +
      route `_run_command` through it; **source `system_overrides.sh` in BOTH bins** (they don't today — same
      divergence class as the Phase-1 active-sync bug, so `_run_command` had zero dry-awareness on the make path);
      migrate vault.sh×3 / jenkins.sh×1 / dispatcher `--dry-run` to `_dry_run_active`/`DRY_RUN`. **Part B:** cluster-up
      plan-and-exit right before the Step 4 Vault-pf seam (line 338). **Part C:** split cluster-down's coarse 22-op
      guard — `_run_command` ops auto-covered by Part A, direct launchctl/rm (pgw/am/am-auth/kc-pf/cf) get per-op
      guards. **Part D:** BATS. Commit msg `fix(lifecycle): standardize dry-run on DRY_RUN and complete make up/down
      guards`. Stubbed cluster-up/down BATS verify exit-0 preview/no mutations and itemized teardown; shellcheck
      and provider/lifecycle suites pass. Phase 3 (deregister) + Phase 4 (Slack) remain sequenced after 2b.
      **VERIFIED by Claude 2026-08-14:** SHA on origin; 9-file scope clean; A1/A2/A3/A4/B/C/D all present;
      shellcheck clean on all 6 shell files; **21/21 BATS pass** (8 dry_run + 6 cluster_up + 7 cluster_down);
      base `system.sh` untouched; no `K3DM_DEPLOY_DRY_RUN` stragglers. Smart catch: cluster-up does
      `unset -f __k3dm_base_run_command` + re-source after plugin loads (plugins re-load foundation system.sh and
      clobber the wrapper). **ONE confirmed follow-up defect (out of 2b DoD scope):** `bin/cluster-down` `*)` branch
      (line 100, the local/dev provider path — orbstack/k3d/k3s all route here via `make down`) never sources
      `system_overrides.sh`, so the common launchd block's `_run_command --prefer-sudo -- launchctl bootout`
      browser-listener ops (lines 179/204/230/246, guarded ONLY by the bridge) fire **real sudo under `DRY_RUN=1`**
      (spy-confirmed: `REAL launchctl CALLED` vs `[dry-run] sudo …` when override sourced). k3s-aws/gcp/az branches
      are correctly bridged. **Fix = one line** (`source system_overrides.sh` in the `*)` branch; no unset needed —
      it sources no plugins) → **fold into Phase 3** (already edits cluster-down).
- [x] **v1.25.0 DRY_RUN cluster-lifecycle bugfix — Phase 3 COMPLETE** (`469a3427`, pushed to
      `origin/k3d-manager-v1.25.0`, 2026-08-14). `make down` now deregisters k3s-aws from hub ArgoCD and
      bridges local-provider launchd teardown under DRY_RUN; cluster-down BATS 12/12 and shellcheck pass.
      **VERIFIED by Claude 2026-08-14:** both changes verbatim per spec (deregister block between `fi`/`;;` in
      k3s-aws branch; one-line `source system_overrides.sh` in `*)`, no unset); SHA on origin; code scope 2 files
      + CHANGELOG/memory-bank in follow-up `718a8f7b`; CHANGELOG refs fix SHA; shellcheck clean; 12/12 BATS.
      **Mutation-tested:** reverting Change 1 fails 3 deregister tests (primary Defect-1 fix properly guarded).
      ⚠️ **FINDING (test quality, not correctness — fix is real & correct):** the `*)` bridge test
      (`acg-down dry-run local provider bridges launchd bootouts`) is a **vacuous** regression guard — the full
      suite passes identically with Change 2 reverted, because the headless BATS context skips the sudo/tty-gated
      bootouts (cluster-down:212/254) and the `launchctl-mutation-called` sentinel doesn't track the
      unconditional `_run_command --prefer-sudo -- rm -f <plist>` leaks (198/223/224/262). A real guard must
      exercise a non-tty-gated `_run_command --prefer-sudo` op on `*)` under DRY_RUN=1 (e.g. assert an
      `rm -f <sentinel>` previews `[dry-run]` and leaves a real sentinel intact). **Recommended follow-up**, not
      a blocker; Defect 2 leak itself confirmed real via standalone spy (real `sudo launchctl bootout`/`rm` on
      interactive `DRY_RUN=1 make down` without the bridge). The broader foundation/Phase 2 history remains below
      for reference. **Spec:**
      `docs/bugs/v1.25.0-bugfix-dry-run-cluster-lifecycle.md`,
      2026-08-14). `DRY_RUN=1` today is honored ONLY in `_k3s_aws_deregister_cluster` → `DRY_RUN=1 make up/down`
      really provisions/destroys (footgun). Fix = foundation-first guard primitives (`_dry_run_active`,
      `_dry_guard`) + per-op guards across `bin/cluster-up`, `bin/cluster-down`, and all 5 provider deploy+destroy
      fns (D1 per-op, D2 all-providers, D3 foundation-first). Phased: **Phase 0 lib-foundation** (helper+BATS+release)
      → Phase 1 subtree-pull+sync → Phase 2 guards → **Phase 3** also fixes `make down` k3s-aws NOT calling
      `_k3s_aws_deregister_cluster` (bin/cluster-down bypasses the dispatcher).
      **Phase 0 + Phase 1 DONE:** lib-foundation PR #40 **MERGED** (`1327c86`), released **v0.4.9**
      (tag `5826946`, CHANGE.md stamped + retro `docs/retro/2026-08-14-v0.4.9-retrospective.md`, GH release
      live, main unprotected so no protection restore). **Subtree-pulled into k3d-manager** on
      `k3d-manager-v1.25.0`: merge `56ff8df1` (squash `9a31ac7a`, `14c79082..58269466`) — `_dry_run_active`
      /`_dry_guard` now live at `scripts/lib/foundation/scripts/lib/system.sh:1850`. Copilot findings folded in
      (location-independent bats `$SYSTEM_LIB` + non-racy `mktemp`, doc `f51b95d`).
      **Phase 1 ACTIVE-SYNC completed** (`f5057e73`): the subtree copy was present but `bin/cluster-up`/`cluster-down`
      source the top-level active `scripts/lib/system.sh` directly (diverges from subtree) — the two helpers were
      NOT runtime-callable on the make up/down path until synced into the active file (verified `CALLABLE` +
      dry/real behavior + shellcheck clean).
      **Phase 2 spec written + HANDED TO CODEX** (`docs/bugs/v1.25.0-bugfix-dry-run-phase2-per-op-guards.md`,
      2026-08-14): self-contained, verified line-anchors for 2a `bin/cluster-down` / 2b `bin/cluster-up` / 2c all 5
      providers; DoD has DRY_RUN-touches-nothing smoke + real-mode-still-mutates coverage gate + BATS. Commit msg
      `fix(lifecycle): honor DRY_RUN per-op across make up/down for all providers`.
      **Phase 3 COMPLETE** (`469a3427`, pushed to `origin/k3d-manager-v1.25.0`; spec
      `docs/bugs/v1.25.0-bugfix-dry-run-phase3-make-down-deregister.md`,
      2026-08-14): `bin/cluster-down` `k3s-aws)` branch (lines 48–64) tears down CloudFormation but never calls
      `_k3s_aws_deregister_cluster` (k3s-aws.sh:247, self-guards DRY_RUN, on dispatcher path at :333, merged
      `d6217640`) → `make down` leaves the sandbox registered in hub ArgoCD. Fix = add a dry-aware deregister
      block after the `acg_teardown` if/else, before `;;`. Commit msg
      `fix(lifecycle): deregister k3s-aws sandbox from hub on make down`. Stubbed real/dry k3s-aws and local
      provider BATS pass; shellcheck is clean. The `*)` bridge fix is included; Tier-2 e2e proceeds in parallel.
      **Phase 4 spec written + QUEUED** (`docs/bugs/v1.25.0-bugfix-dry-run-phase4-slack-cluster-commands.md`,
      2026-08-14): wire DRY_RUN into Slack `cluster-up`/`cluster-down`. `bin/k3dm-webhook:_run_cluster` always
      spawns real `make up/down`; fix = parse a `dry`/`dry-run` token (position-independent, alongside optional
      provider), thread `dry_run` into `_run_cluster`, inject `DRY_RUN=1` into the `_posix_spawn_job(env=…)`
      child (make passes env→`bin/cluster-*` recipe; NO edits to cluster-up/down/Makefile), skip
      `_record_acg_state`/`_run_post_provision_check`/`_push_metrics` in dry-run, 🧪-tag Slack msgs. Admin-only
      unchanged. Commit msg `feat(webhook): support DRY_RUN preview for Slack cluster-up/cluster-down`.
      **Phase 3b test-hardening FOLDED IN (2026-08-14):** the Phase 4 spec now has a **Part B (test-only)** —
      Change 7 replaces the vacuous `*)` bridge test in `scripts/tests/bin/cluster_down.bats` with a
      sentinel-survival guard: `CLUSTER_PROVIDER=orbstack DRY_RUN=1` + `KEYCLOAK_BROWSER_LISTENER_PLIST=<sentinel>`,
      assert the sentinel survives (the `_run_command --prefer-sudo -- rm -f` at cluster-down:198 is non-tty-gated,
      so the base `_run_command` really rm's it without the `*)` source). **Mutation-verified by Claude before
      writing the spec:** passes on current tree, fails `[ -e "${_sentinel}" ]` when Phase 3's `*)` source line is
      removed (bin/cluster-down restored clean). Part B is test-only, must NOT edit bin/cluster-down; DoD adds a
      pass→fail→pass mutation check. Both parts land in the one webhook commit.
      **Blocked on Phase 2 merge** (dry-run is a footgun until guards exist); not handed off.
      **Post-Phase-2 follow-up:** `docs/howto/makefile.md` is stale — documents renamed `bin/acg-*` binaries
      (now `bin/cluster-*`, v1.7.1), `make sudoers` (actual: `install-sudoers`), omits many targets, and has 0
      DRY_RUN coverage. Update it (DRY_RUN CLI row + `[dry-run]` Slack arg + `acg-*`→`cluster-*` rename) when
      Phase 2 lands.
- [x] **v1.25.0 E2E harness Tier 2 — CODIFIED, ready for Codex handoff** (2026-08-15). Live run drove the full
      path end-to-end (auth order $39.98 → live Stripe API); GAP 1/2/3 all CLOSED (identity = public Cloudflare
      issuer + internet egress, no DNAT; e2e Job via ClusterIP DNS). Copy-paste-exact `e2e_verify_sandbox`
      sequence + BATS contract folded into `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md` (kept plan count at
      4). Three substrate overrides (order URLs / payment gateway=stripe / JWK public issuer) stay in the harness
      (production-correct app defaults). **Config-gap bugfix filed** (real, substrate-independent):
      `docs/bugs/2026-08-15-namespace-labels-missing-for-payment-netpol.md` — two k3d-manager-only fixes so
      payment NetworkPolicies match (namespace app labels + `data-git` `managedNamespaceMetadata`). **DONE**
      in k3d-manager commit `8ea02b51`, pushed to `origin/k3d-manager-v1.25.0`; Kustomize and YAML parse
      gates passed. Remaining for G = app-level only (payment role-authority `aeb89e8`
      merge + e2e X-User-ID keying).
- [ ] **[superseded] v1.25.0 E2E harness Tier 2 — ARCHITECTURE LOCKED, blocked on Claude live dry-run** (2026-08-14,
      user chose "design fully first"; `docs/plans/v1.25.0-e2e-harness-tier2-sandbox.md`, plan #4).
      **D1 RESOLVED → disposable in-sandbox ArgoCD** (stack is appset-driven keyed on
      `k3d-manager/role: app-cluster`; install ArgoCD in-sandbox, label `in-cluster`, apply same appsets vs
      `kubernetes.default.svc`). INVARIANT never calls `register_app_cluster` (self-contained → no hub orphans).
      **NOT handoff-ready:** exact deploy code blocked on THREE undesigned paths needing a live dry-run —
      GAP1 in-sandbox ArgoCD install unsupported (`deploy_argocd_bootstrap` skips `CLUSTER_ROLE=app`,
      argocd.sh:969); GAP2 Keycloak/identity deploy not a reusable fn (`services-git` excludes
      `shopping-cart-identity`); GAP3 no app-cluster ingress-exposure helper. Next = Claude live dry-run
      pins GAP1–3 AND moves G past 2/4 (live Stripe run is Claude's), then Codex handoff. Order schema
      blocker already resolved on main (`cb58e8b` #67 + image `df35ea8`); remaining = rerun Stripe E2E.
      **+ Status output contract** (plan doc #4) — concise error-first output with red/yellow/green
      terminal semantics, failed-service health/HTTP codes, `SERVICE=<name>` focused diagnostics,
      `status-full`, `status-json`, and stable exit codes. Implementation is committed on the branch;
      live verification/deployment is pending.
- [x] Webhook status source repaired (2026-08-12): restored Keychain token with
      `bin/k3dm-webhook-setup`, refreshed GitHub secret, reinstalled LaunchAgent, and verified health
      HTTP 200. Remaining login 401s (Keycloak/ArgoCD/Grafana) are separate follow-up issues.
- [x] Status follow-up (2026-08-12): default `make status` now follows the active provider file and
      optional Pushgateway refusal is warning-level; focused status tests remain green.
- [x] Status login smoke repair (2026-08-12): webhook now uses hub-scoped Keycloak and Vault-managed
      ArgoCD/Grafana credentials; LaunchAgent KUBECONFIG renders correctly. Live `make status` is
      `Overall: HEALTHY`; issue `docs/issues/2026-08-12-status-login-credentials-and-launchagent-kubeconfig.md`.
- [x] Status JSON provider repair (2026-08-13): `make status-json` now follows the active-provider
      file instead of defaulting to `k3s-aws`; 5/5 summary BATS pass and live JSON is healthy.
- [x] Istio Unknown cleanup (2026-08-13): removed finalizers from four deletion-marked stale
      `ubuntu-k3s` Istio Applications targeting retired `host.k3d.internal`; ArgoCD removed them and
      Hostinger Istio remains Synced/Healthy. Issue: `docs/issues/2026-08-13-stale-istio-ubuntu-k3s-applications.md`.
- [x] CVE remediation dashboard cleanup (2026-08-13): exporter marks current events and superseded
      failures; dashboard adds Current Status and labels audit history. Static YAML/JSON and embedded
      exporter compilation pass; live reapply remains to be run after push.
- [ ] **v1.26.0** — image signing + attestation, closing the CVE loop (SCOPED, not started). Spec
      `docs/plans/v1.26.0-image-signing-cve-loop-closure.md`. cosign sign + attest at build; `cosign verify`
      at promotion + admission (Kyverno, staged Audit→Enforce). Key-in-Vault, pub via ESO. Multi-repo.
      Slots after v1.25.0. `project_image_signing_cve_loop`.

## Backlog (not release-gated)

- [x] **Jenkins DEPRECATED in docs (DONE 2026-08-10) — code KEPT.** Verified unused; earlier removal item
      cancelled. `project_jenkins_deprecation`.
- [ ] **Secure Vault remote access (QUEUED — after v1.24.0 release)** — expose Vault UI via laptop
      cloudflared `vault.3ai-talk.org` behind Cloudflare Access + MFA (Google IdP / TOTP);
      Access-app-before-ingress ordering; Vault audit device on; root token laptop-only. Filing
      `docs/howto/secure-vault-remote-access-cloudflare-access.md` (decision pending). No changes made yet.
      `project_secure_vault_remote_access`.
- [ ] Dashboard parts (b)+(c) — superseded by the Codex 1:1 dashboard; re-scope before executing.
- [ ] `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md` carry.
- [ ] Shopping-cart Dependabot backlog (Go builder-image bumps, majors held) — `project_backlog.md`.
- [ ] rabbitmq-client-java NPE fix `36ed860` — JAR publish + pom update pending.
- [x] CVE remediation failure investigation (2026-08-12) — dashboard rows are historical
      `ready_pod_digest_mismatch` events; later payment events applied and current workloads are healthy.
      Dashboard supersession/current-state query remains queued; see
      `docs/issues/2026-08-12-cve-remediation-failed-history-investigation.md`.

- [ ] **BUG (2026-08-14) — fresh k3s-aws SSM agent cannot register.** EC2 instance
      `i-015dbcd49b4f8eec6` was running/healthy with its SSM profile associated, but
      `describe-instance-information` returned no record. Console output reports failure to acquire
      EC2 credentials and missing account instance-management role configuration. This blocks the
      provider's 150-second SSM wait; flannel fallback is unrelated. Evidence and recommended
      preflight/host checks: `docs/bugs/2026-08-14-k3s-aws-ssm-agent-cannot-register.md`.

- [x] **PAYMENT GHCR PULL SECRET FIX (2026-08-15):** shopping-cart-payment commit `7cae043`
      pushed to `origin/fix/payment-ghcr-eso-pull-secret`. Added the Vault/ESO-owned GHCR
      ExternalSecret, attached `ghcr-pull-secret` to the payment ServiceAccount, and listed the
      ExternalSecret in the base Kustomization. `kubectl kustomize k8s/base` passed; only the
      pre-existing `commonLabels` deprecation warning was emitted.

- [x] **KEYCLOAK ROLE AUTHORITY MAPPING (2026-08-15):** shopping-cart-payment commit `aeb89e8`
      pushed to `origin/fix/keycloak-role-authority-mapping`. Added realm/client role conversion to
      Spring `ROLE_*` authorities, wired the JWT converter, and added three unit tests. Full Maven
      suite passed under Java 21: 133 tests, 0 failures/errors. After merge, verify the realm role
      assignment for the test principal.
