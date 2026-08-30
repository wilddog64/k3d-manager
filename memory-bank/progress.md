# Progress — k3d-manager

> Compressed 2026-08-21. Settled fix entries collapsed to pointers; detail is in
> `memory-bank/archive/progress-2026-08-19.md`, `docs/issues/`, release notes, and git.

## Releases

| Version | State |
|---|---|
| v1.26.0 | RELEASED — PR #117 `1bbe5439`, tag v1.26.0 + GitHub release published, branch protection restored (enforce_admins=true, 1 required approval). Shipped 3/5 scopes. |
| v1.25.0 | RELEASED — PR #116 `d48e465f`, tag/release published, protection restored |
| v1.24.1 | RELEASED — PR #115, tag and GitHub release published |
| v1.24.0 | RELEASED — PR #113, tag and GitHub release published |
| v1.23.0 and earlier | RELEASED — see `CHANGELOG.md` |

## v1.26.0 queue

- [x] **Fleet node lifecycle (count-agnostic)** — Phase A shipped as lib-foundation `v0.4.12`
  (PR #43 `c4f3211`, Copilot addressed `32ce9c9`, tag/release live; subtree-pulled into
  `scripts/lib/foundation` `e60dff69`/`2c083258`). Phase B implemented `b0fe320a`
  (`ACG_AGENT_COUNT`-driven hosts/nodes, parallel+idempotent SSH/SSM joins with per-node
  readiness, `make fleet-render|validate|plan|up` rungs; `scripts/etc/acg-cluster.yaml`
  unchanged). **Live-verified** at `ACG_AGENT_COUNT=4` (5 nodes = ACG cap): two live-only
  defects found + fixed + re-verified — `_k3s_agent_is_ready` false-negative (private-IP
  exact-match resolver in `shopping_cart.sh`) and `fleet-plan` invalid `--no-execute`/missing
  params (rewritten to `create-change-set --change-set-type CREATE` on a throwaway stack).
  Suite 17/17; teardown clean (0 EC2, stack gone, ArgoCD == baseline). Commits `46bfdf1c` +
  `35e9ecf2`, pushed + origin-verified. Findings:
  `docs/bugs/2026-08-21-fleet-phaseb-live-verification-findings.md`. **DONE.**
- [x] **E2E promotion-gate integration with durable success/failure artifacts** — live GREEN
  2026-08-21. `e2e_verify_vcluster` on the hub; the Playwright suite failed and the harness
  captured it faithfully: durable artifact `~/.k3dm/e2e/1787338912-32712.json`, result-event
  ConfigMap in `platform-ops`, exporter `e2e_run_info`/`e2e_last_run_pass=0`
  (fires `E2EVerificationFailing`)/`e2e_last_run_timestamp_seconds`. Full chain proven. Minor
  Finding 1a (empty duration metric) filed, not fixed.
  Evidence: `docs/bugs/2026-08-21-lifecycle-e2e-live-acceptance-findings.md`.
- [x] **Verify unknown/out-of-sync cleanup without mutating unrelated live Applications** —
  live GREEN 2026-08-21. Faithful full-ACG run on expired sandbox `604492140645`: 10 appset
  apps + 23 survivors + hostinger baseline; post-cleanup 23 survivors EXACT match, hostinger
  untouched. Found + fixed BLOCKING Finding 2a (`cleanup-stale-clusters` hung — now deletes
  Secret first + non-blocking `--wait=false`; BATS asserts order+wait 2/2; re-verify 3s, 0
  orphans). Commit `0274fdde`, pushed. Medium Finding 2b (dispatcher strips `--confirm`) filed.
- [x] Finding 2b RESOLVED (`3a6dddb0`, 2026-08-29, v1.27.0) — dispatcher guard publishes
  `K3DM_DEPLOY_CONFIRMED`; `deploy_app_cluster` honors it (additive). BATS
  `deploy_app_cluster_confirm.bats` 5/5. Spec
  `docs/bugs/2026-08-29-dispatcher-confirm-flag-deploy-app-cluster.md`.
- [x] Lifecycle cleanup foundation — registration metadata + dry-run/confirm
  `cleanup-stale-clusters`, provider/grace/retain guards, generated-Application-only deletion,
  JSONL audit (`f90c8e0d`).
- [ ] Keep all new work within the five-plan milestone limit (at 5/5 — split before a 6th).
- [x] 2026-08-20 provisioning/recovery batch (all pushed on `k3d-manager-v1.26.0`, each with a
  `docs/issues/2026-08-20-*.md` record + BATS/shellcheck evidence): k3s-aws SSM→SSH fallback
  (`fef71219`/`40f1d19a`/`2424f55f`), kubeconfig TLS SAN loopback (`3603b60c`), SSM Vault-bridge
  selects SSH, data-layer CoreDNS + guarded `make down CLEANUP_STALE=1` (`316f26d2`/`20a13862`/
  `f24c0c96`, implies `--keep-hub`), hostinger-only hub rebuild, stale unknown-Application match
  fix (`2f4de4fd`), ACG credential s2-404 + CDP-listener recovery (`f6bb7bb`/`c7f7b37`),
  cloudflared IPv4-loopback pin (`929ebed7`).
- [x] Dependabot alert #6 (js-yaml `3.15.0`, CVE-2026-59870, dev-only transitive) — fixed
  upstream as lib-foundation `v0.4.11` (PR #42 `b92f494`), subtree-pulled (`1bf1d2ce`, lockfile
  `3.15.1`). Reads `open` only because Dependabot scans main; auto-closes when v1.26.0 → main.

## v1.27.0 queue

- [~] **Hub CPU overcommit fix (2026-08-27)** — Step 1 (resource governance) IMPLEMENTED +
  live-applied; Step 2 (load-shed) config IMPLEMENTED, ROLLOUT PENDING (reapply `observability`
  appset @ `k3d-manager-v1.27.0`). Specs: `docs/bugs/2026-08-27-hub-cpu-overcommit-resource-
  governance.md`, `docs/bugs/2026-08-27-hub-load-shed-observability-footprint.md`. Step 2 edits:
  `lokiCanary.enabled: false` + prom scrape/eval 30s→60s, retention 7d→3d/8GB. Detail in
  activeContext. Blocker for full argocd redeploy: chart-drift (live 10.4.0 vs pin 7.8.1).

- [x] **keycloak-0 restart-loop FIXED + CoreDNS collateral FIXED (2026-08-27)** —
  `docs/bugs/2026-08-27-keycloak-restart-loop-tight-probes.md`. Same CPU-starvation-vs-1s-probes
  root cause. keycloak: values.yaml.tmpl now sets startupProbe (430s grace, covers the ~326s
  Quarkus `start-dev` cold start) + loosened liveness/readiness + 1000m/1Gi; live-patched onto
  the sts → keycloak-0 **1/1, 0 restarts**. CoreDNS was crashlooping (155 restarts, 0/1) from the
  identical disease → live-patched loosened liveness → **1/1 stable, DNS restored**. ⚠ CoreDNS
  patch NOT in git (k3s-managed, may revert) — FOLLOW-UP: persist via k3s manifest override or
  land Step 2. Fresh evidence Step 2 is no longer optional.

- [x] **E2E transient-resource cleanup (2026-08-27)** — `6b20cced` pushed. Teardown now cleans
  orphaned kubeconfig/proxy state and removes transient logs; JSON summaries remain as audit data.
  Focused E2E tests and ShellCheck passed. Full suite has a pre-existing hang after the initial
  tests; follow-up is to observe m4 load and use m2 for E2E if saturation persists.

- [~] **M2 E2E live acceptance (2026-08-25):** bootstrap/preflight passed; intentional
  invalid-digest run published a failed artifact. The required passing retry
  `1787708603-5833` completed but failed 45/102 tests because the current E2E image/client expects
  flat API responses and numeric prices while deployed APIs return `{data: ...}` envelopes and
  string prices. The result published exactly once to `platform-ops`; stale vCluster cleanup was
  needed before retry. Acceptance remains blocked pending an aligned E2E image and rerun.
  Evidence: `docs/issues/2026-08-25-m2-e2e-acceptance-contract-mismatch.md`.

- [ ] **E2E observability follow-up:** M2 result ConfigMaps publish correctly, but the live
  Prometheus deployment currently has no `e2e_run_info` series and the `Recent runs` Grafana
  panel shows duplicate exporter/application service columns plus blank legacy totals. Bugs:
  `docs/issues/2026-08-25-e2e-grafana-table-raw-labels.md` and the contract-mismatch issue above.
  Dashboard source fix `cfe925fc` is pushed; it uses `exported_service` as the canonical service
  filter, hides exporter `service`, and renames table fields. E2E client fix `0c2505b` is pushed
  on `shopping-cart-e2e-tests:feat/e2e-image-multiarch`; full repo `tsc` remains red only on
  pre-existing unrelated test strictness/type errors.

- [~] **Dependabot CI/merge automation — IMPLEMENTATION-READY (`aa3bcc50`, 2026-08-29).**
  `docs/plans/v1.27.0-dependabot-automation.md` now carries the concrete reusable
  `workflow_call` workflow (infra) + thin per-repo caller + rollout + validation, grounded
  in the product-catalog baseline. Routes via branch+PR (sc spec-not-direct, gated); land in
  infra → pin callers → validate on one repo → roll to the rest. PR #51's skipped job is
  correct (human-authored, not dependabot[bot]).
- [x] **Redacted leaked (rotated) Slack signing secret + landed worker-setup spec**
  (`84e2917d`, 2026-08-29) — closed the plaintext-in-tree leak in the 2026-06-04 slack issue
  doc (secret rotated 2026-06-23, dead), filed the worker-setup paste-swap/OAuth-fallback bug
  spec. Landed the unmerged `security/redact-leaked-signing-secret` branch's content onto
  v1.27.0; branch prune (local+remote) pending (classifier-blocked; user runs
  `git branch -D` + `git push origin --delete`). Repo is public — dead secret remains in git
  history (rotated → low risk, no history rewrite). Worker-setup hardening NOT implemented
  (still unconditional `export CLOUDFLARE_API_TOKEN`); spec now filed for it.

- [ ] **CVE remediation event panels empty (2026-08-24) — ROOT-CAUSED 2026-08-25.**
  NOT a durability bug (Codex RC wrong). Durable source (event ConfigMaps) exists; 0 series
  is correct because 0 events exist. Real RC: Keychain `platform-ops-app-rebuild/k3dm` absent
  → secret never synced → `app-cve-scan` pod wedged in `CreateContainerConfigError` → requester
  never runs. Fix = user stores scoped PAT + re-run `argocd_sync_app_rebuild_secret` + delete
  wedged job `cve-auto-1787541034`; then hardening (fail-loud + bounded backoff) + dashboard
  no-data annotation. Corrected diagnosis in `docs/issues/2026-08-24-cve-remediation-panels-empty.md`.

- [x] **CVE panel ② ("Shopping-cart Unique CVEs") POPULATED + Prometheus-verified + DURABLE
  (2026-08-24)** — 75 actionable `trivy_vulnerability_inventory{image_repository=~"wilddog64/
  shopping-cart-.*"}` series, native operator-generated (self-refreshing 24h TTL). Three commits:
  scan-job CPU request `50m→10m` (`8bfcbcc9`) + `trivy.slow`/`timeout 15m0s` (`49477017`) +
  **native private-image scanning via `operator.privateRegistryScanSecretsNames` (`aac9cb27`)** in
  `trivy-operator-acg-values.yaml`. Real root cause: workloads carry NO imagePullSecret anywhere
  (node-level containerd cred, invisible to operator) — so operator-upgrade is a dead end; the
  named-secret-per-namespace config is the fix. Live-verified; manual-CR stopgap (352 all-sev) was
  deleted in favor of native (75 actionable). Bug doc:
  `docs/bugs/2026-08-24-trivy-operator-skips-private-images-sa-imagepullsecret.md`.
  **Close-out (2026-08-24):** `acg-trivy-operator` ArgoCD-synced (3 OutOfSync res converged; ref
  contains `aac9cb27` so private-registry env survived; Synced/Healthy, panel ② held at 75) +
  `allow-cve-scan-egress` netpol durable-home spec'd + pushed to shopping-cart-payment
  (`feat/trivy-scan-egress-netpol` `3ca0dca`, PR gated).

- [x] **Hostinger CVE inventory manifest authoring** — commit `84817d88`: added the
  Hostinger-only read-only SA/ClusterRole/Binding ApplicationSet, Vault-backed ESO
  `app-cluster-kubeconfig` ExternalSecret, platform-ops ApplicationSet wiring, and minimal
  exporter warning. Focused provider suite 54/54; full curated-suite failures are recorded in
  `docs/issues/2026-08-22-manifest-authoring-test-failures.md`. No live mutations performed;
  pushed to `k3d-manager-v1.27.0`. PR: none per user instruction.

- [x] Investigated CVE dashboard empty tables (2026-08-22): platform data is present in Prometheus and
  Grafana's datasource API; shopping-cart is empty because hub-only exporter scope excludes the remote
  Hostinger cluster, and remediation event metrics have no current records. Issue evidence:
  `docs/issues/2026-08-22-cve-dashboard-empty-tables.md`. Remote inventory aggregation and durable
  remediation-event retention remain follow-up work.

- [~] **hostinger CPU right-sizing (2026-08-24)** — node `srv1754834` request-bound (98% CPU
  requests / ~20% actual). Durable overlay fix committed `6851b5b0`: payment cpu 200m→50m +
  maxSurge=0 on basket/order/frontend (deadlock class). Builds verified. **Inert until the
  `services-git` appset is reapplied at v1.27.0** (frozen at v1.26.0; `services/` byte-identical so
  only this fix moves). Live patch won't stick (selfHeal). **Status 2026-08-24:** (a) services-git
  reapply rendered+diff-verified (apply classifier-blocked → user `!` cmd); (b) ✅ rabbitmq 200m→50m
  MERGED (PR #93 `59ed6342`, enforce_admins restored, trim live on ref=main); (c) istiod pilot cpu
  100m→50m `1dbe68dc` (maxSurge=100% is a non-overridable istio chart default; request trim shrinks the
  surge pod; reapply rendered+diff-verified → user `!` cmd).

Scope = 4 plan docs (4/5, under cap). Dependency-ordered load-split leads; decision
2026-08-21 "keep all four".

- [x] **Foundation-managed vCluster CLI** (`docs/plans/v1.27.0-foundation-managed-vcluster-cli.md`)
  — **COMPLETE.** Part A = lib-foundation `v0.4.13` (Codex `b2adb8f2` → PR #44 `0a3e4043`; Copilot
  caught a real `curl -o` after-`--` bug, fixed + BATS-tightened; subtree-pulled into
  `scripts/lib/foundation`, curl fix intact). Part B = HEAD `142fd06b` on `origin/k3d-manager-v1.27.0`
  (Codex; its `6c2dd94d` note was amended away): removes the consumer installer, adds module-scoped
  `_VCLUSTER_BIN`, rewires `_vcluster_check_prerequisites` to
  `foundation_ensure_vcluster_cli "$VCLUSTER_VERSION"` (guards non-zero+empty), routes all 6 lifecycle
  invocations through it, updates help/docs, reworks BATS to stub the contract. Claude re-ran gates
  (BATS 36/36, shellcheck/`bash -n` clean, disappearance greps empty, subtree untouched) + **live
  `make e2e` CLI-contract gate PASSED** (real download+SHA+atomic install of vcluster `0.32.1` managed
  path, substrate rolled out inside the throwaway vCluster; artifact/ConfigMap/exporter carry
  `9b3a5754`). Playwright app Job failed pre-existing (not the CLI change). PR = release-time step.
  - ⚠️ Finding 1a (empty `e2e_last_run_duration_seconds` failing the whole scrape) — ✅ FIXED
    `5cd67228` (`num()` coercion). `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.
- [~] **M2 remote E2E runner** (`docs/plans/v1.27.0-m2-remote-e2e-runner.md`) — SSH-dispatch
  ephemeral E2E to m2-air, restricted M4-side publisher → hub ConfigMap → Grafana. The actual
  E2E load-split off the M4 laptop. **Depends on the foundation vCluster CLI.**
  Increments 1–6 DONE (inc 6 = failure behavior + operations, `b5fff9c4`, 68/68 BATS green).
  **Publish-back source-pin durability DONE 2026-08-24:** commit `0cf69e28` adds optional
  `E2E_PUBLISH_FROM` handling while preserving the unpinned authorized_keys line, and forces
  `AddressFamily=inet` for publish-back SSH. Focused BATS `68/68`, `bash -n`, ShellCheck, and
  explicit default-path proof passed. No live SSH or authorized_keys access; no PR per instruction.
  **Remaining: 2-run live acceptance gate (1 fail + 1 pass via `make e2e-remote RUNNER=m2`)
  + live redeploy of the inc-2 runner-labelled exporter/dashboard/rule.** Image-arch blocker
  CLEARED 2026-08-24: multiarch PR **#7 MERGED** (`90c13994`, shopping-cart-e2e-tests) →
  `:latest` rebuilt multiarch, VERIFIED amd64+arm64 (`docker manifest inspect`, run
  `32725667211`). Publish-back CONFIGURED 2026-08-24: restricted key `~/.ssh/e2e-m4-publisher`
  on M2 + M4 forced-command `authorized_keys` entry + `E2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local`
  in gitignored `.envrc` (`source_up`); M2→M4 smoke test auths + forced command fires + bad payload
  rejected (no ConfigMap). Only remaining gate = hostinger node CPU exhaustion (see activeContext).
- [ ] **Image signing / CVE-loop closure** (`docs/plans/v1.27.0-image-signing-cve-loop-closure.md`)
  — cosign sign+attest, Kyverno Audit→Enforce, promoter verify gate. Multi-repo, heavy.
- [x] **Image-signing Part 0 — `signing.sh` plugin** (Slice A) — DONE, Claude-verified `e1ef0037`
  on `origin/k3d-manager-v1.27.0`. Lazy signing plugin (seed/rotate/status), pub-only ESO template,
  read-only Vault policy, structural BATS 6/6; shellcheck clean. Codex generated (session
  `01a0363c`); Claude committed (Codex sandbox `.git` read-only) after trimming an over-privileged
  `_signing_configure_writer` (kyverno-bound create/update role — parent-plan line 270 / OWASP A01).
- [x] **Image-signing Stage B — live Stage-0 seed** — DONE + live-verified 2026-08-24 (`7d335b1a`).
  cosign 3.1.3 seeded Vault `secret/cosign/signing` + Keychain backup; `kyverno` ns; read-only
  `cosign-verify` policy; ESO `cosign-public-key` SecretSynced=True projecting **cosign.pub only**.
  Fixed 3 live-found signing.sh bugs: missing `_vault_login` (`6f3c6dd3`); early-return skipped
  idempotent applies; ESO 403 → `_signing_grant_eso_read` auto-discovers the store's Vault role
  (`eso-ldap-directory`) and merges `cosign-verify` (`7d335b1a`). BATS 6/6.
- [x] **Image-signing Stage C** — PRs merged AND signing verified working post-merge (blocker resolved).
  CI cosign **sign-by-digest** (attestation deferred). Spec
  `7779e4d6`. Code on `feat/cosign-sign-attest`, Claude-verified on origin (Codex session `01a0365f`):
  infra reusable `build-push-deploy.yml` (workflow_call COSIGN secrets, job-env COSIGN_KEY, `id: push`,
  cosign-installer@v3.7.0, sign `${image-name}@${push.digest}` BEFORE promote), frontend direct + 4
  backend callers passing COSIGN_KEY/PASSWORD through. Gated `if: env.COSIGN_KEY != ''`. **✅ ALL 6 PRs
  MERGED (gh-verified 2026-08-28):** infra #94 `1fa7ab0`, frontend #99 `000bdcc0`, basket #39 `6f5a57c9`,
  order #72 `cb4403db`, product-catalog #51 `c42a5ccd`, payment #63 `fa396eef`. Backend callers pin the
  signing-enabled reusable workflow `@1fa7ab0` (pin-bump commits order `da8fcc2e` / product-catalog
  `00665840` / payment `be796c6d`; basket via `14f5b1257`). Workflow-scope blocker resolved (`gh auth
  refresh -s workflow`); order+payment `main-protection` rulesets verified `active` post-merge.
  **⚠ SIGNING BLOCKER (2026-08-28):** the `Sign image by digest` step FAILS on every caller's post-merge
  main build → images pushed **unsigned**. RC1 (basket/order/product-catalog/payment): `COSIGN_KEY` secret
  is the **hex encoding** of the PEM (seeded via `security -w`, which hex-encodes multi-line values) →
  cosign `invalid pem block`; fix = re-seed from true PEM via file. RC2 (frontend): `publish` job lacks
  job-level `env.COSIGN_KEY` → `Install cosign` skipped → `cosign: command not found`; fix = add job-level
  env. Spec `docs/bugs/2026-08-28-stage-c-cosign-signing-fails-post-merge.md`.
  **✅ RESOLVED 2026-08-28 (user go):** RC1 re-seeded `COSIGN_KEY` in all 5 callers from true PEM via file
  (key+password verified in cosign locally first). RC2 frontend PR #101 (`fix/cosign-publish-job-env`,
  `d47e675c`) merged squash `85265e7b`. All 5 main builds re-triggered → `Sign image by digest` = success;
  **`cosign verify --key <derived pub>` PASSES on all 5** (GHCR `sha256-<digest>.sig` present): basket
  `4a96cf41…`, order `ca2d398b…`, product-catalog `3db7b8da…`, payment `3b5f478c…`, frontend `ca25a636…`.
  ⚠ product-catalog run still red on a SEPARATE pre-existing step "Fail when image promotion did not
  complete" (GitOps promotion, not signing) — tracked apart, does not block D.
- [~] **Image-signing Stage D** — Kyverno install + ClusterPolicy Audit→Enforce + promoter
  `cosign verify` gate. **AUDIT SLICE IMPLEMENTED 2026-08-28 (user go):** `signing.sh` gains
  `_signing_install_kyverno` (pinned chart 3.9.0, A08), `_signing_render_policy` /
  `_signing_apply_cluster_policy` (injects `cosign.pub` from the in-cluster ESO Secret into the policy),
  and `deploy_image_signing [--audit|--enforce]` (dispatcher auto-resolves; `deploy_*` arg-guard applies).
  New manifest `scripts/etc/signing/cluster-policy-verify-images.yaml.tmpl` — `verifyImages` ClusterPolicy,
  **signature-only** (attestation deferred in C), scoped to `ghcr.io/wilddog64/*` in
  **`shopping-cart-apps`/`shopping-cart-payment`** ONLY (real ns per `_namespace_for`, NOT per-service
  names the plan assumed), `failureAction: Audit`, webhook `failurePolicy: Ignore`. 12 BATS green
  (`scripts/tests/plugins/signing.bats`); render→YAML-parse verified; shellcheck -S warning clean.
  **NOT DONE (gated follow-up, split at Audit→Enforce seam):** live install runs against the APP cluster
  (ACG/hostinger), not the hub — Audit PolicyReports must show zero would-be-blocks before Enforce;
  `--enforce` gated behind `SIGNING_ALLOW_ENFORCE=1`. Promoter `cosign verify` gate in `app-cve-scan.sh`
  (needs cosign+pub in the platform-ops CronJob image) + `cosign attest` in CI = next slice. Howto
  `docs/howto/image-signing.md`; functions.md updated.
  **✅ AUDIT LIVE on hostinger 2026-08-29 (user go):** `deploy_image_signing --app-cluster` added
  (`ec746ade`, spec `docs/bugs/2026-08-29-signing-app-cluster-mode.md`, 16 BATS) — skips hub Vault
  (`signing_init`), installs Kyverno first (creates ns), applies pub ExternalSecret, `_signing_wait_pub_secret`,
  then policy; `SIGNING_KYVERNO_HELM_SET` shrinks replicas/requests for the tight node. Kyverno 1.19
  field-name fix `ignoreTlog`/`ignoreSCT` (`bbbacfe0`; `ignore:true` was strict-decode-rejected). Live:
  hostinger has its OWN Vault (bridged) — seeded cosign.pub (public only) + granted `eso-app-cluster` read
  (extended `app-cluster-reader`). Kyverno 4/4 Running, `cosign-public-key` SecretSynced, `verify-first-party-images`
  ClusterPolicy Ready (Audit). **⚠ AUDIT FINDING → would-be-block under Enforce:** Kyverno gets 401
  UNAUTHORIZED pulling private `ghcr.io/wilddog64/*` (registry auth, NOT signature; sigs known-good per C).
  `docs/issues/2026-08-29-kyverno-verifyimages-ghcr-registry-auth.md`. **REGISTRY CREDS WIRED but STILL
  401:** ghcr `ExternalSecret` in kyverno ns + `existingImagePullSecrets[0]=ghcr-pull-secret` (flag confirmed
  on admission ctrl); credential VALID (curl→ghcr token endpoint 200) but Kyverno's cosign verifier sends no
  auth (Kyverno 1.19 ignores `--imagePullSecrets` for the cosign path). **NEXT (before Enforce):** resolve
  Kyverno keychain issue (version bump / mount dockerconfig as DefaultKeychain) → re-audit clean → gated
  `--enforce`. Then codify app-Vault seed/grant + kyverno-ns ghcr ES into signing.sh.
- [ ] **Adaptive checkout load testing** (`docs/plans/v1.27.0-adaptive-checkout-load-testing.md`)
  — API-level checkout load + Grafana/Prometheus telemetry + small browser cohort.
  - [~] Slice F (generator + dashboard + live run) — **BLUEPRINT DONE 2026-08-29**
    (`docs/bugs/2026-08-29-loadtest-slice-f-generator.md`): checkout=`POST /api/orders` (synthetic items OK,
    payment downstream Stripe test), generator on laptop via port-forward, metrics via pushgateway/remote-write,
    auth=password grant `client_id=order-service` against PUBLIC keycloak issuer, users from OpenLDAP. NEXT:
    fetch client secret + LDAP user → one authed 201 → build k6 + wire Slice E stubs + dashboard + live run.
  - [x] Part 0 controller (Slice E) — commit `17be2e69` pushed to
    `origin/k3d-manager-v1.27.0`: pure stage-ladder + stop-condition-hysteresis decision logic,
    immutable jq summaries, opt-in guard, and BATS 9/9. Syntax, warning-level ShellCheck, and
    Bash `_agent_audit` passed. No cluster/Prometheus/k6/Stripe (that is Slice F, live). PR URL:
    none (task prohibits PR creation).
- Both load-split plans were promoted from v1.26.0-deferred (renamed `v1.26.0-*` →
  `v1.27.0-*`, headers/cross-refs updated) on 2026-08-21.

## Verification record

- **2026-08-27 scrape interval:** `977d9e11` pushed to `k3d-manager-v1.27.0` (remote tip also
  includes concurrent CVE pin commits). `kube-prometheus-stack-values.yaml` parses cleanly and
  changes only federation from 30s to 60s; exporter remains 60s. Live reapply/measurement pending.

- **2026-08-27 status credential fix:** `f07adea8` pushed on `k3d-manager-v1.27.0`; Keycloak smoke
  checks now discover the deployed admin Secret without requiring env credentials. Webhook BATS
  55/55 and `py_compile` passed. Aggregate health verification remains pending because the live
  webhook sweep exceeds the bounded shell check under current load.

- **2026-08-27 hub outage follow-up:** agent-0 and server restarts did not recover the Kubernetes
  API; Kine/API timeouts persisted under high container CPU. See
  `docs/issues/2026-08-27-hub-control-plane-still-unavailable.md`; OrbStack runtime recovery is
  required before further service verification.

- **2026-08-26 Hostinger outage recovery:** restarted exited `k3d-k3d-cluster-agent-0` (exit 143);
  all hub nodes returned Ready and Prometheus was recreated/replayed. Commit `44de06f7` pushed to
  `origin/k3d-manager-v1.27.0` fixes Keycloak service-port 8080, IPv4-pins tunnel/health probes,
  and corrects the Hostinger Keycloak status URL. Focused BATS 68/68, shellcheck, and
  `_agent_audit` passed. Public ArgoCD/Keycloak repeated probes reached 200; intermittent wrapper
  resets remain documented in the incident issue.

- **2026-08-26 Hostinger capacity verification:** `srv1754834` is a single 2-vCPU / 7.75-GiB node
  with 1610m CPU requests (80%), 4880Mi memory requests (61%), and live usage of 404m CPU (20%) /
  5496Mi node memory (69%). It can host Keycloak+PostgreSQL only as a tight steady-state fit, not
  with safe failure/rollout margin. Recommended capacity before migration: 4 vCPU / 16 GiB, or a
  second worker node.

- **2026-08-26 k3d agent watchdog:** fixed the bounded watchdog to start stopped agent containers
  instead of skipping them (`15c7d072`, pushed); installed/reloaded via `make install-node-health-watch`.
  BATS 2/2, ShellCheck, and `_agent_audit` passed.

- **2026-08-26 port-forward flapping follow-up:** hardened the shared ArgoCD/Keycloak forwarder
  with IPv4 binding, three-failure health hysteresis, and a 2-second restart delay (`a5dc3967`). Regenerated
  launchd wrappers; local ArgoCD and Keycloak endpoints returned HTTP 200. Public DNS verification
  was unavailable from the agent shell. Details: `docs/issues/2026-08-26-hostinger-keycloak-port-forward-service-port.md`.

- v1.25.0 release validation: E2E BATS 16/16; webhook BATS 54/54; syntax/shellcheck gates
  passed; Copilot findings resolved before merge.
- Node-health watchdog and E2E diagnostics hardening shipped in the released branch.
- Prometheus/Grafana recovery, status retry, remediation-table cleanup, and Slack status/thread
  fixes are shipped; remaining live follow-ups are in `activeContext.md`.

## Process

- **2026-08-27 M2 E2E migration wiring:** committed and pushed `0f16f0de` (`fix(e2e): forward
  immutable image tag to remote runner`) so `make e2e-remote RUNNER=m2` cannot silently use stale
  `latest` when `E2E_IMAGE_TAG` is supplied. The source image build completed successfully as run
  `33073207387` from `0c2505bb`; remote live acceptance is pending. M4 disk check: root 58% used /
  196 GB free, OrbStack 26% / 184 GB free; Docker API inventory was unavailable because the socket
  did not respond within the bounded check.
- **2026-08-27 M2 acceptance:** run `1787838531-2562` used image
  `sha-0c2505bbdc09b4ad12e5ea251ce9a8eeb7975e00` and completed with 26 passed, 31 failed, and 45
  skipped. Product-catalog passed; basket/order contract assertions and payment tests failed. The
  result was not accepted; evidence is in `docs/issues/2026-08-27-m2-e2e-acceptance-after-immutable-image.md`.
- **2026-08-27 Keycloak smoke fallback:** pushed `931839ab` (`fix(keycloak): support password-only
  admin secret in smoke check`) on `k3d-manager-v1.27.0`; focused `keycloak.bats` completed 12/12
  and ShellCheck reported no findings.

- Every implementation updates this file and `activeContext.md` with the real commit/PR SHA.
- Unexpected live failures get a dated `docs/issues/YYYY-MM-DD-*.md` record with verbatim
  evidence.
- **2026-08-26 hub outage:** recorded agent-0/Kine control-plane failure and IPv4 tunnel-origin
  remediation in `docs/issues/2026-08-26-hub-control-plane-and-edge-forward-outage.md`; service
  recovery remains pending final public `make status` verification.
- **2026-08-26 edge forward hardening:** pushed `ea91431d` with 5-second probes and six-failure
  hysteresis; Prometheus/Grafana recovered, while ArgoCD/Keycloak remain pending API stabilization.
- Historical specs/issues are archived only when superseded or unreferenced; files are never
  deleted.
- **2026-08-28 hub last-mile close-out** (`k3d-manager-v1.27.0`): [x] governance durability verified
  (no drift; Step 2 governance live in `monitoring`); [x] Vault auto-unseal watchdog deployed +
  two bugs fixed (image derivation + `activeDeadlineSeconds` 50→150), validated live (job SUCCEEDED
  ~12s, `vault already unsealed`); [x] frontend-login false-red fixed (`kc_token_is_stub` skip guard),
  `make status` FAIL→WARN with everything else green; [x] loki re-shed declined (server-0 at 95–130%,
  no pressure; selfHeal would revert). Specs: `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`,
  `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`.

- **2026-08-29 monitoring-pause Grafana keep-list — DONE + LIVE-VERIFIED (8506f5fe, pushed):** added
  pure whole-word keep-list predicate `_observability_workload_in_keep_list`, default
  `OBSERVABILITY_PAUSE_KEEP=kube-prometheus-stack-grafana` exemption in the pause sweep (resume
  unchanged), five pure BATS tests, and Makefile help text. Spec
  `docs/bugs/2026-08-29-pause-keep-grafana-up.md`. Coded by Codex, Claude-verified: BATS 5/5, `bash -n`
  clean, ShellCheck only pre-existing SC2016. **Live hub test:** `make monitoring-pause` → grafana
  stays 1/1 (health `database:ok`, loginable) while prometheus/alertmanager/loki/loki-gateway/ksm/
  operator → 0/0; `make monitoring-resume` → all back, `make status` HEALTHY. Caveat by design: paged
  panels show "No data" while paused (UI reachable ≠ live data).

- **2026-08-29 layered `monitoring-resume` (LAYER=1 lite / LAYER=2 full) — DONE + LIVE-VERIFIED
  (1bdbe3c6, pushed):** `make monitoring-resume LAYER=1` = Grafana + Prometheus only (live dashboards,
  everything else 0); `LAYER=2` or no arg = full stack (existing body unchanged). Added
  `_observability_normalize_layer` (1→1, else→2, forgiving) + `_observability_resume_layer1` (keeps
  ArgoCD `automated:null`, explicit replica drive via the keep-list predicate,
  `OBSERVABILITY_LAYER1_UP` default = grafana + prometheus STS, idempotent from any start), Makefile
  `$(LAYER)` passthrough + help, 5 pure BATS normalize cases. Spec
  `docs/bugs/2026-08-29-layered-monitoring-resume.md`. Coded by Codex, Claude-verified: BATS 10/10,
  `bash -n` clean, ShellCheck only pre-existing SC2016, diff==spec, scope==observability.sh + new BATS +
  Makefile. **Live hub:** L2→`LAYER=1` = grafana 1/1 + prometheus 1/1, rest 0/0, Prometheus `up` query
  + Grafana `database:ok` proven live; `LAYER=2` = all 7 workloads 1/1, `make status` HEALTHY (one stale
  `Unknown` prometheus pod deleted during the ramp — known CPU-starvation cascade, not a feature bug).

- **2026-08-29 Tier-1 E2E orders.spec fix — DONE + LIVE-VALIDATED, full-gate rerun confirming
  (aa2f2190, pushed):** root-caused the orders.spec wholesale failure to a missing DB schema, NOT a
  test-contract bug. Deployed order image `sha-56033880` = the **Go** rewrite (commit `5603388`) with
  no runtime migration; substrate created the `orders` database but not its tables → HTTP 500 (42P01).
  Fix = `20-orders-schema.sql` in `scripts/etc/e2e/postgres.yaml` initdb, DDL matched to the deployed
  commit (order_items **without** `total_price` — the HEAD/testdata column would 500 with 23502).
  Live-validated: POST → 201 full contract, GET list → 200. Payment specs remain Tier-2/ACG scope.
  Spec `docs/bugs/2026-08-29-e2e-order-schema-missing.md`; durable service self-migrate follow-up in
  `docs/issues/2026-08-29-order-service-no-startup-migration.md`.

- **2026-08-29 Tier-1 residual test/service fixes — HANDED OFF TO CODEX (both repos):** after the
  substrate fix greened 45/12/45, user chose to fix e2e tests + basket (payment → Tier-2). Two
  cross-repo fixes dispatched to Codex per spec+Codex discipline: (1) `shopping-cart-e2e-tests`
  orders.spec:149/163 `CONFIRMED`→`PAID`/legal chain `PENDING→PAID→PROCESSING→SHIPPED` (branch
  `fix/e2e-order-status-enum` off `feat/e2e-image-multiarch` — deployed `0c2505b` NOT in main);
  (2) `shopping-cart-basket` `internal/model/cart.go:151` `binding:"required,min=0"`→`"min=0"`
  (branch `fix/basket-update-quantity-zero` off `origin/main`). Codex: branch+commit+push only —
  NO PR, NO main, NO live cluster. Claude then rebuilds images + re-runs Tier-1. Specs:
  `docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md`,
  `docs/issues/2026-08-29-basket-update-quantity-zero-required.md`.

- **2026-08-29 Tier-1 rerun with both fixed images — GREEN on everything Tier-1 covers.**
  Codex fixes verified (e2e `9202b194` off `feat/e2e-image-multiarch`, envelope fix preserved;
  basket `8614773e` off main, `go build`/`go test` re-run clean). e2e image built via CI
  workflow_dispatch on the branch (run `33285863490` success → `ghcr.io/...e2e-tests:sha-9202b194`,
  multiarch verified); basket built locally + `k3d image import`ed as `sha-8614773e` (IfNotPresent).
  Tier-1 rerun (`E2E_IMAGE_TAG=sha-9202b194 e2e_verify_vcluster`; harness killed the foreground
  task mid-suite so read the Playwright pod logs live before teardown): **48 passed / 9 failed /
  45 skipped** (was 45/12/45). ALL 9 failures are `payments.spec.ts` (27 ✘ = 9 tests × 3 tries),
  ZERO non-payment failures — both order-status tests + cart qty-0 now green. Residual 9 = payment,
  structural → Tier-2/ACG. Cleanup: kustomization reverted (basket newTag stays `f70d5801` —
  `8614773e` is a local-only build, NOT in GHCR), vcluster deleted. **GATED next: PR + merge both
  fix branches (user go), then bump substrate basket newTag + e2e image to the merged SHAs.**
