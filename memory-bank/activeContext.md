# Active Context — k3d-manager

> Compressed 2026-08-24 (CVE panel ② saga closed → collapsed to pointers). Settled fixes
> live as pointers; detail in `memory-bank/archive/`, `CHANGELOG.md`, `docs/retro/`,
> `docs/issues/`, `docs/bugs/`, git history, and auto-memory.

## Current focus

- **2026-09-04 v1.28.0 PLANNING — Claude weekly-quota lever + Hermes install decision.**
  Context: user on $20/mo flat rate hits Claude's weekly quota fast; under flat-rate the goal
  is routing work OFF Claude's constrained quota onto Codex/Gemini (other flat plans) + Haiku
  (cheaper Claude), NOT reducing total tokens. Two-part plan agreed: **(1)** workflow-defaults
  audit + tighten [started]; **(2)** Hermes as a Claude-last-resort ops router [deferred, scope
  doc gated].
  - **DECISION #1 (2026-09-04): keep Opus 4.8 as the global default** (`settings.json`
    `"model": "opus"` UNCHANGED). User wants Opus interactively for orchestration/judgment/verify;
    quota relief comes from subagent routing of mechanical lanes, not from flipping the default.
  - **DONE — `~/.claude/commands/create-pr.md` Phase 2 Opus→Sonnet.** Was labeled "Sonnet" but ran
    in the Opus main conversation → Copilot-fix read+edit burned Opus. Now a real **Sonnet
    subagent**; Opus only trust-but-verifies the returned fix rationales. (Config repo, not k3d-manager.)
  - **DONE — DECISION #2 (2026-09-04): `/bugfix` + `/handoff` spec-authoring → Sonnet subagent.**
    Both commands now draft the spec (read source + write exact old/new blocks) on a Sonnet
    subagent; Opus reviews the draft for exact-code-block precision before handoff. Edits in
    `~/.claude/commands/bugfix.md` (step 3) + `handoff.md` (steps 1–2). (Config repo, not k3d-manager.)
  - **Hermes install decision recorded** in `docs/architecture/hermes-phase1-monitoring-scope.md`
    §10: `_install_hermes_agent` in **lib-foundation** (subtree-first), installs Hermes **off-hub**
    (laptop tier, like `bin/k3dm-webhook`) — which also resolves the §9 hub-stability gate without
    waiting for the M5. Deferred to Hermes impl phase; no code yet. (Hermes theme = roadmap
    candidate v1.28.x, `docs/roadmap.md:156`.)
  - **DONE — Hermes Phase-1 first deliverable (§5) shipped: `bin/public-endpoint-probe`.**
    New self-contained, read-only script + `make status-public` target. Samples each public
    hostname (enumerated from `scripts/etc/cloudflared/config.yml` ingress) K×, host healthy only
    if ≥M/K return 2xx/3xx; discriminates **edge-down** (all fail → cloudflared split-brain) vs
    **single-service** (one fails → zombie port-forward) with exit codes 0/1/2/3; `--json` for
    Hermes to consume later. Spec `docs/plans/v1.28.0-hermes-status-probe.md` (drafted by Sonnet
    subagent, Opus-reviewed). shellcheck-clean; all 3 verdict paths + JSON validity verified via
    stubbed curl. Webhook untouched (§4 stays authoritative). This is the ONLY Hermes work this
    session — sensor set / correlator / Slack / guide stay deferred as a separate release story.
    Uses **1 of the 3 remaining v1.28.0 plan-doc slots** (now 3 v1.28.0 docs).
  - **DECISION 2026-09-04 — NO SPLIT. v1.28.0 = operational-resilience release, all 3 docs completed
    here.** User rejected pushing a scope to v1.29.0: the three are related and finish together.
    Through-line: operate the laptop hub + Cloudflare edge safely — (#3) update the platform without
    downtime, (#1, done) detect edge reachability failures honestly, (#2) provision multiple providers
    concurrently without local-state corruption. 3 of 5 plan-doc slots (cap not in the way). Remaining
    to complete: `v1.28.0-parallel-multi-cloud-provisioning` + `v1.28.0-platform-zero-downtime-rollouts`.

- **2026-09-03 v1.27.0 PR #118 MERGED & RELEASED** — https://github.com/wilddog64/k3d-manager/pull/118
  (base `main`, head `k3d-manager-v1.27.0`, merged SHA `62c9ff27`, tag/release v1.27.0 published
  2026-09-03). CI green (lint✓ detect✓ stage2 skipped-by-design). CodeQL FP fixed in code
  (`26e1a1ff`: precompiled `re.sub` regex barrier + dropped `kc_realm` interpolation; no token
  needed). Copilot review 4 inline comments all valid + fixed in `0b028b5f` + all 4 threads
  replied+resolved via GraphQL. **Post-merge steps COMPLETE:** retrospective doc `2e9b5ade`,
  tag v1.27.0 pushed, GitHub release published, `enforce_admins` restored to `true` (verified),
  next branch k3d-manager-v1.28.0 created. **ApplicationSets REAPPLIED 2026-09-03** pinned to
  `K3D_MANAGER_BRANCH=k3d-manager-v1.27.0` (NOT the checked-out v1.28.0 dev branch): `hub-platform-ops`
  (signing config) was already on v1.27.0; the only drift was `grafana-dashboards-hub` +
  `grafana-dashboards-acg` still on v1.26.0 — reapplied both appsets, apps flipped to v1.27.0.
  `argocd_check_values_branch k3d-manager-v1.27.0` GREEN (6/6 values refs). Only `rollout-demo-*`
  remain off-version (intentional HEAD-pin). Full post-merge close-out DONE.

- **2026-09-03 PRE-PR BATS GATE — branch was RED; 9 test-only fixes applied, branch now green-minus-env.**
  A single-threaded local `bats scripts/tests/ --recursive` on `k3d-manager-v1.27.0` found **13 failures**.
  Bucketed by running affected files on `main` (CI-green) vs branch, in isolation: **9 branch-related
  (all test-only — code is correct/intentional)** + **4 pre-existing local-macOS-env** (fail on `main` too,
  pass in CI → NOT PR-blocking; tracked in `docs/issues/2026-09-03-bats-preexisting-local-macos-env-failures.md`).
  Spec: `docs/bugs/2026-09-03-bats-red-branch-stale-guards-and-vcluster-harness.md`. The 9:
  stale guards from intentional milestone changes — LDAP chart migration to `openldap-stack-ha`
  (`:389→:1389`, `dc=shopping-cart,dc=local→dc=home,dc=org`) [53/54]; ghcr pull secret moved to a
  `frontend` ServiceAccount [720]; node-health threshold `3→5` [81]; argocd port-forward self-healing
  rework (`sleep 30→RESTART_DELAY=2`, `HEALTH_FAILURE_THRESHOLD 3→6`) [288/518]; plus vcluster harness
  bugs from `142fd06b` (`_vcluster_wait_ready` 60s stub timeout, `run`-subshell drops `_VCLUSTER_BIN`,
  bare-`vcluster` vs `$VCLUSTER_STUB` string) [850/851/854]. 6 affected files re-run → 104 ok / 0 not ok.
  Full-suite confirmation (expect 4 env-only failures) in progress. NOT committed yet. **PR still gated.**

- **2026-09-03 v1.27.0 CVE-loop CODE-COMPLETE — ADMIT latch SHIPPED (`5e5bd33b`, pushed).**
  Kyverno `verifyImages` now carries an `attestations:` block (`type:
  https://cosign.sigstore.dev/attestation/vuln/v1`) beside the signature `attestors:`, so a first-party
  image must carry a vuln attestation signed by our key. Renderer blocker fixed: `_signing_render_policy`
  got a `# __PUBLIC_KEY_ATTEST__` awk branch injecting at 26 spaces (fixed-22 signature branch untouched).
  signing.bats 20/20 (+3, yq-parsed), shellcheck clean. **Three-latch loop code-complete: BUILD ✅ /
  PROMOTE ✅ (`588aab3e`) / ADMIT ✅ (`5e5bd33b`).** All ship inert: PROMOTE default-off (`COSIGN_VERIFY=1`
  **and** `COSIGN_VERIFY_ATTESTATION=1`); ADMIT default `Audit`, Enforce gated behind
  `SIGNING_ALLOW_ENFORCE=1` + clean Audit dashboard (D2). **Remaining = live enablement only**, in order:
  exercise PROMOTE gate → ADMIT Audit dashboard clean → ADMIT `--enforce`. No PR yet (still on the
  milestone branch, per gate).

- **2026-09-02 hub outage:** Cloudflare Grafana 502 and ArgoCD OAuth redirect failures traced to
  k3s API/etcd readiness failure and severe server CPU saturation (~650–880%). Agents/server were
  restarted; API remained unstable. Evidence and recovery attempts: `docs/issues/2026-09-02-hub-control-plane-saturation-causing-public-502.md`.

- **2026-09-02 follow-up:** `shopping-cart-identity` remains degraded from Argo strategic-merge
  duplicate Keycloak ports; Grafana/Frontend public origins flap during recurring API saturation,
  and Grafana has a stale dashboard route. Evidence: `docs/issues/2026-09-02-argocd-identity-drift-and-dashboard-502.md`.

- **E2E Tier-1 gate → GREEN on everything it covers (2026-08-29).** Both Codex fixes verified,
  images built (e2e via CI `sha-9202b194`; basket local `k3d image import` `sha-8614773e`), Tier-1
  rerun = **48 pass / 9 fail / 45 skip** (was 45/12/45) — all 9 fails are `payments.spec` (Tier-2/ACG).
  Order-status + cart qty-0 now green. **PRs OPEN (2026-08-29, user go-ahead):**
  e2e-tests **#8** (`fix/e2e-order-status-enum`, base main), basket **#44**
  (`fix/basket-update-quantity-zero`, base main). CI: e2e GitGuardian pass; basket all green.
  **Copilot review requested+addressed (2026-08-29):** requested via GraphQL `requestReviews`
  (REST bot-login no-ops; bot node `BOT_kgDOCnlnWA`). Fixes via Codex (spec
  `docs/issues/2026-08-29-copilot-pr-findings-e2e-basket.md`): e2e `6cb808d` (add PROCESSING to
  Order union + Number() normalize create/update product); basket `65fdb96` (`Quantity *int`
  `required,min=0` + handler deref + gin binding test `{}`→400/`{qty:0}`→200). e2e #8 also merged
  main in (`bcc63da`) to drop already-merged multiarch workflow from the diff + fixed PR desc.
  Deferred: order-management.spec flow-status rewrite → `docs/issues/2026-08-29-e2e-order-management-flow-status-alignment.md`.
  **Copilot threads ALL RESOLVED (2026-08-29):** e2e #8 3/3, basket #44 1/1 — replied w/ fix
  rationale + `resolveReviewThread` on each (api-client normalize thread auto-resolved; the other
  three replied+resolved). **Basket pointer-fix (`65fdb96`) re-validated live on Tier-1** (rebuilt
  `sha-65fdb96` + `k3d image import`, temp substrate tag, e2e img `sha-9202b194`): run
  `1788057617-1177` = **48 pass / 9 fail / 45 skip** (all 9 = payment/Tier-2) — no regression;
  vCluster self-cleaned; substrate `kustomization.yaml` basket newTag **reverted** to CI
  `sha-f70d5801` (65fdb96 is local-import only, not in GHCR).
  **basket #44 MERGED (2026-08-30, user go — admin override, squash `4b42ecc7` on main).** Merge
  method: `gh pr merge --admin --squash` (mergeStateStatus was CLEAN; ruleset left intact — the
  bypass-actor PUT was classifier-blocked so admin-override merge used instead). Main Go CI building
  → GHCR image `sha-4b42ecc755d599e2d673ec0a22341c62e8363493`. **e2e #8 ALSO MERGED (2026-08-30,
  admin override, squash `7601aa14` on main).** **/post-merge done (Haiku subagent + Claude
  verify):** e2e-tests `enforce_admins` **RE-ENABLED** (verified `true`, reviews=1); basket ruleset
  untouched (no restore needed); both mains synced (e2e `7601aa14`, basket `4b42ecc7`);
  `docs/next-improvements` already exists in both. **SUBSTRATE BUMP DONE + VALIDATED (`e06abead`):**
  main publish CI green for both → GHCR images confirmed (basket `sha-4b42ecc7`, e2e `sha-7601aa14`
  which `latest` now also points to — same digest, so `E2E_IMAGE_TAG:-latest` default already tracks
  the merged e2e code, no `e2e.sh` change). `kustomization.yaml` basket newTag → `sha-4b42ecc7`;
  Tier-1 re-run against REAL GHCR images (basket pulled from GHCR, not local-import) = **48/9/45**
  (9 payment/Tier-2). **E2E Tier-1 order-status + cart-qty-0 loop FULLY CLOSED.**
  **Docker-space follow-up (2026-08-30):** Tier A+B cleanup done (14GB orphan vol + 18 dangling +
  10 superseded tags freed ~19GB inside Docker; OrbStack backend reclaims to host over time). New
  helper `e2e_prune_images` (`2e8799c2`, dry-run-default) prunes >N-day images NOT in the E2E
  working set — dispatch `./scripts/k3d-manager e2e_prune_images [--days N] [--apply]`; protects all
  substrate images + running containers + `E2E_IMAGE_PRUNE_KEEP`. See progress.md. No release
  tag/retro (service-repo fix PRs, no version bump). (History below.) Substrate fix DONE+verified (`aa2f2190`
  postgres initdb `orders`/`order_items` schema matched to deployed Go order `5603388`), gate
  26/31/45 → **45/12/45**. Residual 12 = 9 payment (structural → Tier-2/ACG) + 2 order-status
  e2e-test bugs + 1 basket-service bug. User decision: fix e2e tests AND basket, payment→Tier-2.
  **Handed off to Codex (both repos):** (a) `shopping-cart-e2e-tests` orders.spec `CONFIRMED`→
  `PAID`/legal chain (branch `fix/e2e-order-status-enum` off `feat/e2e-image-multiarch` — the
  deployed image `0c2505b` is NOT in main, must preserve envelope fix); (b) `shopping-cart-basket`
  `internal/model/cart.go:151` `binding:"required,min=0"`→`"min=0"` (branch off `origin/main`).
  Specs: `docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md`,
  `docs/issues/2026-08-29-basket-update-quantity-zero-required.md`. Next after Codex: rebuild both
  images, Claude re-runs Tier-1 (residual should drop to the 9 payment specs only). PR/merge GATED.

- **v1.27.0 active branch** (`k3d-manager-v1.27.0`, branched from v1.26.0 merge). **Scope = 4 plan
  docs (4/5, under cap)**, dependency-ordered load-split leads (decision 2026-08-21 "keep all four"):
  1. `v1.27.0-foundation-managed-vcluster-cli.md` — **COMPLETE.** Part A = lib-foundation `v0.4.13`
     (PR #44 `0a3e4043`, subtree-pulled). Part B = HEAD `142fd06b` rewires `vcluster.sh` to
     `foundation_ensure_vcluster_cli` (module-scoped `_VCLUSTER_BIN`, guards non-zero+empty). Claude
     re-ran gates (BATS 36/36, shellcheck/`bash -n` clean, disappearance greps empty, subtree
     untouched) + **live `make e2e` CLI-contract gate PASSED** (real download+SHA+atomic install of
     vcluster `0.32.1` managed path; substrate rolled out; artifact/ConfigMap/exporter carry
     `9b3a5754`). Playwright app Job failed pre-existing (not the CLI change). No PR yet (release-time).
  2. `v1.27.0-m2-remote-e2e-runner.md` — **Increments 1–6 DONE** (inc 6 `b5fff9c4`, BATS 68/68).
     Producer runner-provenance, consumer/exporter+Grafana `runner` dim, `e2e_remote.sh`
     preflight/bootstrap/dispatch/restricted-publisher/lock+ops, `make e2e-remote|e2e-runner-health|
     e2e-replay|e2e-runner-unlock`. **Remaining: 2-run live acceptance gate** (1 fail + 1 pass via
     `make e2e-remote RUNNER=m2`) + deferred live redeploy of the inc-2 runner-labelled
     exporter/dashboard/rule via `argocd.sh`. **Blocker (a) CLEARED 2026-08-24:** e2e-tests image
     multiarch — PR **#7 MERGED** (`90c13994`, shopping-cart-e2e-tests; protection lowered→merge→
     restored, enforce_admins back on); Publish E2E Image reran on main push → `:latest` rebuilt
     **multiarch, VERIFIED** `docker manifest inspect` = `linux/amd64` + `linux/arm64`
     (QEMU+`platforms`+`provenance:false`, run `32725667211` success).
     **Publish-back CONFIGURED 2026-08-24:** dedicated restricted key `~/.ssh/e2e-m4-publisher`
     generated on M2 (private stays on M2); M4 `authorized_keys` restricted forced-command entry
     (`command="…/k3d-manager e2e_result_publish",restrict,no-pty,no-forwarding`) installed via
     `e2e_result_publisher_install`; `E2E_M2_PUBLISH_BACK_HOST=cliang@m4-air.local` set in gitignored
     `k3d-manager/.envrc` (`source_up` preserves parent thinking-cap). Smoke-tested M2→M4: publisher
     key auths, forced command fires (no-pty confirmed), invalid payload rejected by schema (no
     ConfigMap written). Hub write target (`platform-ops`, ctx `k3d-k3d-cluster`) reachable.
     **Key ROTATED 2026-08-24:** old ed25519 `SwC+H3C7…` retired (M4 authorized_keys line removed →
     old key now `Permission denied`; old private overwritten on M2); new ed25519
     `SHA256:WwhGtx7C5KUt…` (comment `e2e-m2-publisher@m2-air-20260824`) installed at same canonical
     path `~/.ssh/e2e-m4-publisher` behind the identical forced-command restriction — no code/config
     change (path+host unchanged). Verified: neg-test old rejected, prod-path smoke passes. Still
     passphraseless BY DESIGN (unattended publish-back); real control is the `command="…
     e2e_result_publish",restrict,no-pty,no-*-forwarding` lock. M4
     `~/.ssh/authorized_keys.bak-rotate-20260824T225550Z` = rollback.
     **Policy DECIDED 2026-08-24: source-pin only, NO scheduled rotation** (per-deploy + time-based
     auto both declined — blast radius = one schema-validated ConfigMap write behind a forced command;
     frequent rotation adds silent-lockout risk for ~no gain). **`from="192.168.39.0/24"` pin APPLIED**
     to the live M4 line (M2=192.168.39.164, M4=192.168.39.169). Gotcha: mDNS resolves `m4-air.local`
     to IPv6 link-local too → default ssh went v6 → outside the v4 /24 → legit M2 rejected; fixed with
     M2 `~/.ssh/config` `Host m4-air.local\n AddressFamily inet`. Default publish path re-verified
     passing. **Both mitigations are OUT-OF-REPO** → durability spec
     `docs/issues/2026-08-24-e2e-publish-back-source-pin-durability.md` (bake `from=` into
     `e2e_result_publisher_install` via `E2E_PUBLISH_FROM` + `-o AddressFamily=inet` into
     `_e2e_publish_back_push`; a future reinstall/rotation currently DROPS the pin).
     **Durability implemented 2026-08-24:** commit `0cf69e28` makes the source pin optional
     (`E2E_PUBLISH_FROM`, empty preserves the legacy line) and forces IPv4 on publish-back;
     focused BATS `68/68`, `bash -n`, ShellCheck, and an explicit unpinned install proof passed.
     No live SSH or authorized_keys access was performed. PR = none per task instruction.
     **Still BLOCKED** on the 2-run live acceptance gate. M2 bootstrap/preflight passed and the
     intentional invalid-digest run published a failure. The required passing retry
     `1787708603-5833` completed but failed 45/102 tests: current E2E image/client expects flat
     responses and numeric prices while deployed APIs return `{data: ...}` envelopes and string
     prices. Result was published once to `platform-ops`; no M2 transport/publisher failure.
     Evidence: `docs/issues/2026-08-25-m2-e2e-acceptance-contract-mismatch.md`. **RERUN 2026-08-29 with the
     aligned image `sha-0c2505bbdc09b4ad12e5ea251ce9a8eeb7975e00` (Tier-1 vcluster, `E2E_IMAGE_TAG=…
     e2e_verify_vcluster`) STILL FAILS: 26 passed / 31 failed / 45 skipped (exit 1).** TWO issues: (1)
     CONFIRMED — payment-service is NOT in the Tier-1 substrate (`scripts/etc/e2e/` has no payment manifest)
     → 27 payments.spec + payment-dependent cross-service can't pass in vcluster; that's Tier-2/ACG's job.
     (2) orders.spec fails — root cause NOT confirmed; `orders is not iterable` (136×) is a cleanup SYMPTOM,
     and the client's `getOrdersByCustomer` DOES unwrap `{data}` (so the list-envelope hypothesis is
     unlikely); per-test errors lost on teardown (saved .log empty). **NEXT: rerun capturing Playwright
     reporter output to root-cause orders.spec, fix the real cause + rebuild image; decide payment coverage
     (add payment to Tier-1 substrate OR move payment acceptance to Tier-2).** Do NOT claim a list-unwrap fix
     without evidence. Stale vCluster cleanup was required before
     retry and should be treated as a follow-up idempotency bug. The Grafana E2E dashboard table
     also exposes duplicate raw service labels and blank legacy totals; this is documented in
     `docs/issues/2026-08-25-e2e-grafana-table-raw-labels.md`.
     **Dashboard fix committed `cfe925fc` and pushed:** service variables/queries now use
     `exported_service`, the exporter identity `service` is hidden, and table labels are renamed
     to concise names. **E2E client fix committed `0c2505b` and pushed** on
     `shopping-cart-e2e-tests:feat/e2e-image-multiarch`: response envelopes are unwrapped and
     product price/quantity values normalized to numbers. Full repo `tsc` still reports unrelated
     pre-existing strictness/type errors in test files; no new api-client errors remain.
     M2 runner fully provisioned + proven end-to-end (dispatch→SSH→
     OrbStack→k3d→vCluster→substrate→Playwright launch). See M2 bug docs under `docs/bugs/2026-08-22-*`.
  3. `v1.27.0-image-signing-cve-loop-closure.md` — cosign sign+attest, Kyverno Audit→Enforce, promoter
     verify gate. Multi-repo, heavy. **STARTED 2026-08-24 (sliced).** Full milestone decomposed into
     isolated shell/logic units (Codex, no cluster) vs live-rollout stages (Claude, live hub):
     A=`signing.sh` plugin (Part 0) → **✅ DONE + Claude-verified `e1ef0037`** (spec `0fb8c70e`; Codex
     session `01a0363c` generated, `.git` was read-only in its sandbox so Claude committed). Gates:
     bash -n / shellcheck clean / BATS 6/6. **Review trim before commit:** dropped Codex's
     `_signing_configure_writer` — it bound a create/read/update Vault role to the kyverno namespace
     (no consumer; seed goes via direct pod-exec, CI gets the key as GH secrets) and violated parent
     plan line 270 ("read-only … do NOT grant Kyverno broad Vault access", OWASP A01).
     B=live Stage-0 seed → **✅ DONE + live-verified 2026-08-24** (`7d335b1a`). cosign 3.1.3 (brew)
     seeded `secret/cosign/signing` (key/password/pub), Keychain backup, `kyverno` ns created,
     read-only `cosign-verify` policy, ESO `cosign-public-key` in kyverno = **SecretSynced True,
     cosign.pub ONLY** (private key withheld). **3 live-found signing.sh bugs fixed:** (i) no
     `_vault_login` before Vault ops → 403 (`6f3c6dd3`); (ii) signing_init returned early when key
     existed → never re-applied ESO/policy — now guards only key-gen, applies always run; (iii) ESO
     403 because no identity could read the path — added `_signing_grant_eso_read` (auto-discovers
     the ClusterSecretStore role `SIGNING_ESO_STORE`/`SIGNING_ESO_ROLE`, merges `cosign-verify` into
     it; store here uses role `eso-ldap-directory`, NOT eso-reader) (ii+iii `7d335b1a`). Note: ESO
     needs a controller restart after a role policy change (cached token freezes policies at issue).
     C=CI sign+attest across 5 shopping-cart repos [specs→Codex, branch now free]; D=Kyverno
     install+ClusterPolicy Audit→Enforce + promoter `cosign verify` gate [Claude live; kyverno ns +
     pub secret already staged]. Verify Codex SHA on origin per
     [[feedback_codex_verification_protocol]] before trusting.
  - **Stage D Kyverno 401 → RESOLVED 2026-08-30 (`8d8b2251`, pushed).** Live decision tree on hostinger:
    NOT a credential problem (kyverno-ns == app-ns `ghcr-pull-secret` byte-identical; same token passes the
    Deployment/autogen verify). Kyverno's cosign verifier resolves creds against the admitted object's
    `metadata.namespace`; a ReplicaSet Pod (`generateName`) has empty object ns at CREATE → 401, and the
    cosign path ignores `--imagePullSecrets` AND a mounted `DOCKER_CONFIG` (both tested, both failed).
    Fix = match workload controllers (Deployment/StatefulSet/DaemonSet/Job/CronJob) not `Pod` in the policy
    template; basket+order verify clean, 0 UNAUTHORIZED, BATS 17/17. `docs/bugs/2026-08-30-kyverno-verify-401-private-ghcr.md`.
  - **Stage D AUDIT NOW CLEAN — all 5 first-party PASS, 0 FAIL 2026-08-30 (`ce4374ff`+`d7375188`, pushed).** Closed
    all Enforce blockers: (a) re-pinned two unsigned deployed digests (product-catalog `53e668…`→`3db7b8da…`,
    payment `95f2680…`→`3b5f478c…`, both signed 2026-08-28 builds) — ArgoCD synced, both PASS; (b) re-applied the
    policy durably from the committed template via `deploy_image_signing --app-cluster --audit` (helm rev 5, values
    preserved via `SIGNING_KYVERNO_HELM_SET`; stray `ghcr-docker` volume removed); (c) **refined root cause** — frontend
    still 401'd at controller level b/c it ran as `default` SA (cred only on pod-template, which cosign ignores); the
    other 4 use a dedicated SA. Fix = dedicated `frontend` SA (`services/shopping-cart-frontend/`). So verify needs BOTH
    controller-match AND a dedicated non-default SA carrying the ghcr cred.
  - **Stage D ENFORCE FLIPPED — LIVE + verified 2026-08-30 (user go).** `SIGNING_ALLOW_ENFORCE=1 deploy_image_signing
    --enforce --app-cluster` (helm rev 6; live values preserved via `SIGNING_KYVERNO_HELM_SET`; all 4 controllers still
    1 replica). Rule `verifyImages[].failureAction=Enforce` (Kyverno 1.19 per-rule action; deprecated top-level
    `validationFailureAction` stays `Audit`, ignored). Blocking nothing: 5 app pods Running 1/1 0-restart, 5
    PolicyReports PASS=1 FAIL=0, zero PolicyViolation events. **Ran via `!` in-session** — the Claude Code classifier
    gates the enforce mutation, so the flip executes under the user's shell, not Claude's Bash. **Stage D DONE.**
  - **CVE-loop closure #1 — promoter cosign-verify gate ✅ CODE DONE 2026-08-31 (`98b0dc4a`).** Spec
    `docs/bugs/2026-08-31-promoter-cosign-verify-gate.md`. `app-cve-scan.sh` now runs `cosign verify --key <pub>
    --insecure-ignore-tlog=true` on a clean candidate digest **before** pinning it — unverifiable = **refused**
    (fail-closed, `App CVE Promotion Blocked (unsigned)` notify). Mirrors the Kyverno policy stance exactly. Pub key via
    new ESO `cosign-pub-externalsecret.yaml` (Hub Vault `cosign/signing` → `platform-ops/cosign-public-key`) mounted at
    `/cosign`; `COSIGN_VERSION=v2.4.1` (matches CI signer). BATS 12/12, shellcheck clean, howto updated.
    **LIVE-DEPLOY RUNBOOK ready 2026-08-31** — in `docs/howto/image-signing.md` (§Deploying the gate live): targeted
    apply of the ES + CronJob + script ConfigMap on the Hub (`k3d-k3d-cluster`), verify ESO `SecretSynced`, smoke via a
    manual `--from=cronjob/app-cve-scan` job grepping `SIGGATE`. Preflight confirmed: hub Vault `vault_key=present`,
    `vault-backend` CSS Ready, `platform-ops/cosign-public-key` not-yet-present (clean first deploy). **User runs it via `!`
    (deploy-path mutation, classifier-gated for Claude Bash).**
  - **HUB STABILITY / PUBLIC 502 — LIVE DIAGNOSIS 2026-09-02 (Claude-verified live).** Root cause = single-node
    hub CPU oversubscription driving a self-reinforcing control-plane storm. Live snapshot: `k3d-cluster-server-0`
    646% CPU, agent-1 578%, agent-0 322% (M4 Air ~8-10 cores → oversubscribed). Storm drivers (live):
    `svclb-istio-ingressgateway` **600 restarts** (klipper ServiceLB host-port fight), `coredns` 93 restarts +
    `node-exporter` 322 restarts (CPU-starvation SIGTERM kills — cf [[reference_one_second_probes_cpu_starvation_kill_loop]]),
    `argocd-application-controller-0` **901m CPU** (top) continuously reconciling the stuck `shopping-cart-identity`
    app + kube-prom CRD comparison timeouts, `prometheus-0` 698m, `postgres-keycloak` **CreateContainerConfigError**
    (Keycloak DB won't start → identity never Healthy → Argo retries forever = feedback loop). Chain:
    CPU-oversubscribe → pod restarts (coredns/svclb) → DNS+API churn → Argo reconcile storm → kine/sqlite slow →
    API timeouts → port-forward health-checks fail (grafana launchd last-exit -15 SIGTERM, keycloak -9 SIGKILL) →
    Cloudflare **502**. NOT a cloudflared split-brain — stray `com.cloudflare.cloudflared` connector is `.disabled`,
    only `com.k3d-manager.cloudflare-tunnel` live. Codex fixes VERIFIED: `e64111d7` CVE-exporter background-refresh
    thread (line 370 `Thread(...,daemon=True).start()` ✅ correct), `94682a78` status hub-agent surfacing + Makefile
    keycloak secret `keycloak-admin-secret`/`password` (live secret-name confirm pending), `0bca3e21` `Replace=true`
    on shopping-cart-identity app — CORRECT lever for the duplicate-`http`-port strategic-merge drift but blanket
    blast radius (also force-replaces Keycloak STS/PVC → cf `docs/issues/2026-09-02-secure-argocd-sync-and-pvc-blocker.md`);
    commit msg "secure credential piping" NOT reflected in the 1-line diff. Roadmap Hermes theme `41f2f68c` VERIFIED
    (well-scoped, 3-phase, no unrestricted creds, scope-doc-gated) — roadmap-ONLY, no code/repo; keep parked until hub
    stable + scope doc; this incident is its Phase-1 justification.
  - **HUB STABILITY — STAGE A EXECUTED 2026-09-02, 502s RESOLVED (Claude live).** Actions (ALL REVERSIBLE, must resume):
    (1) `make monitoring-pause` → suspended auto-sync on kube-prometheus-stack/hub-loki/trivy-operator (grafana kept);
    prometheus-0 scaled down (shed ~698m). My 240s timeout killed the make wrapper (Terminated:15) but the suspend
    landed. (2) `kubectl -n cicd patch application shopping-cart-identity {syncPolicy.automated:null}` — suspended the
    identity app's tight retry storm (the 901m app-controller driver). **RESULT: grafana.3ai-talk.org 302, argocd 200
    (were 502); agents near-idle.** ⚠️ RESIDUAL: `server-0` control-plane still ~713% CPU — single-node hub structurally
    over capacity (Stage C). **RESUME LEVERS when stable:** `make monitoring-resume` + re-add identity
    `syncPolicy.automated:{prune,selfHeal}`. **keycloak-secrets ROOT CAUSE PINNED:** NOT manifest/seal/auth —
    SecretStore `vault-kv-store` is Ready=True (auth OK), Vault unsealed+active; the ExternalSecret fails because the
    **Vault KV DATA is missing** at `secret/keycloak/admin` (props `admin_password`,`db_password`) + `secret/ldap/admin`
    (`admin_password`) — a Vault-seeding gap (cf [[reference_show_service_passwords_na_root_causes]]). keycloak-0 still
    Running on the legacy Bitnami `keycloak-postgresql` STS so SSO likely unaffected; the git-rendered `postgres-keycloak`
    Deployment is a half-done DB migration blocked on that seed. NEXT: seed Vault keycloak/ldap KV → force ES reconcile →
    resume identity auto-sync → verify Synced/Healthy; then Stage B (resource requests/priorityClasses, calm
    svclb-istio-ingressgateway 600-restart churn, sustained public probes in make status) + Stage C structural offload.
  - **CVE-loop closure #2b — RE-PIN 4 callers to attest SHA ✅ DONE + VERIFIED, 4 PRs OPEN (user-gated) 2026-08-31.** Codex
    (session `01a057f5`, task `bi5vx45pp`) bumped each caller's infra reusable-workflow pin
    `@1fa7ab0`→`@45def89e` on branch `feat/repin-infra-attest` (from each `origin/main`). **Claude-verified
    on origin** (branch SHA + `contents?ref=` bytes, not Codex's word): basket `a5fb8809`
    (`.github/workflows/go-ci.yml`), order `38d70585` (`ci.yml`), payment `28abe731` (`ci.yaml`),
    product-catalog `9dc3b59f` (`ci.yml`) — all: 1 file changed, new SHA=1/old SHA=0, exact msg
    `ci: re-pin infra reusable workflow to attest SHA 45def89e`. Spec
    `docs/plans/v1.27.0-image-signing-attest-repin-callers-codex-task.md` (`2dbfa354`).
    **4 PRs ✅ MERGED + VERIFIED (gh) 2026-09-01:** basket #45 `b84a534d`, order #74 `33e269b7`,
    payment #69 `a672ee42`, product-catalog #52 `0540db3d` (all base main ← `feat/repin-infra-attest`).
    Branch protection intact: all 4 use `main-protection` rulesets (still `active`) — nothing was lowered,
    nothing to restore. BUILD latch now emits vuln+SBOM attestations for all 4 reusable-workflow callers.
    **Frontend inline-attest spec WRITTEN 2026-08-31** —
    `docs/plans/v1.27.0-image-signing-frontend-inline-attest-codex-task.md`: adds 3 steps (trivy `cosign-vuln`
    + `spdx-json` predicates by digest → `cosign attest --type vuln`/`--type spdxjson`) inline into
    `shopping-cart-frontend/.github/workflows/ci.yml` `publish` job after `Sign image by digest`, trivy pin
    reused at `v0.36.0`, branch `feat/frontend-inline-attest`. NOT yet dispatched to Codex. Remaining
    follow-ups: verify side (promoter `app-cve-scan.sh` + Kyverno `verify-attestation --type vuln`); codify
    app-cluster Vault seed/grant + kyverno-ns ghcr ES into `signing.sh`.
  - **CVE-loop closure #2 — CI `cosign attest` (vuln+SBOM) ✅ CODE DONE + VERIFIED + MERGED 2026-08-31.** **PR #95**
    https://github.com/wilddog64/shopping-cart-infra/pull/95, merge SHA `45def89e151bc9d3506f7d641f46d045bc84029d` (base main). **CI all green** (GitGuardian, Kubeconform,
    Kustomize Build, YAML Lint). Codex session `01a05793`; Claude-verified on origin (SHA match, 1 file/33-ins, exact msg, descended
    from origin/main, yaml ok, order Sign→Generate-vuln→Generate-SBOM→Attest→promote, all guarded `if: env.COSIGN_KEY != ''`).
    **Copilot review N/A on infra repo** — REST `requested_reviewers` POST (both `Copilot` + `copilot-pull-request-reviewer[bot]`)
    returns 200 but silently drops the reviewer; only `copilot-swe-agent` is assignable, and PR #94 had zero Copilot reviews →
    Copilot code-review is not enabled on shopping-cart-infra (user's Copilot-required rule is payment-repo-specific). **USER-MERGED 2026-08-31** (user ran `gh pr merge 95`; self-merge via enforce_admins override). **ADMIN OVERRIDE RESTORED 2026-08-31:** `enforce_admins` restored to `true` (verified `gh api ... --jq '.enabled'`) on shopping-cart-infra main post-merge.
    Spec `docs/plans/v1.27.0-image-signing-attest-codex-task.md`. Adds 3 steps to shopping-cart-infra reusable
    `build-push-deploy.yml` (trivy `cosign-vuln` + `spdx-json` predicates → `cosign attest --type vuln` / `--type spdxjson`),
    guarded `if: env.COSIGN_KEY != ''`, reusing already-pinned trivy-action@v0.35.0 + cosign-installer@v3.7.0 (no new versions).
    Branch `feat/cosign-attest` **from origin/main** (the local `feat/cosign-sign-attest` is spent — sign step squash-merged as
    PR #94/`1fa7ab0`, callers pin that SHA). Codex must NOT touch callers or the verify side. Follow-ups: re-pin the 5 callers
    post-merge; then extend the promoter gate + Kyverno policy with `verify-attestation --type vuln`. Then codify app-cluster
    Vault seed/grant + kyverno-ns ghcr ES into `signing.sh`.
  - **Payment Java CVE remediation — spec written + ASSIGNED CODEX 2026-08-30.** Spec
    `docs/issues/2026-08-30-payment-cve-remediation.md`. Root cause: 7 fixable CRIT + 42 HIGH are ALL transitive from
    `spring-boot-starter-parent 3.2.0` (nothing pinned in pom). Fix = single BOM bump to latest 3.5.x + targeted
    `<tomcat.version>`/`<postgresql.version>` overrides (spring-security-web CRIT floor is 6.5.9 → forces the 3.5.x
    line). Codex branch `fix/payment-cve-spring-boot-bump`; gate `./mvnw clean verify` green + dependency:tree proof.
    Codex does NOT build/sign image or re-pin digest — CI signs on merge; trivy re-verify + digest re-pin are Claude's
    downstream steps. Verify Codex's SHA on origin before trusting.
    **RE-DISPATCH 2026-08-30 (v2):** first `codex exec` was launched from k3d-manager → its workspace-write sandbox
    was confined to k3d-manager, so the sibling payment repo was unwritable (`.git/index.lock: Operation not permitted`);
    Codex worked around it by cloning into `k3d-manager/scratch/` — killed + cleaned. Re-launched from INSIDE the payment
    repo (self-contained inlined-spec prompt, no k3d-manager touch) so the sandbox root IS the payment repo. Task
    `b8r8nmk0l`, session `01a05415`. Codex-v1 found: SecurityConfig already uses modern `SecurityFilterChain`
    (minimal/no code change expected); it proposed parent 3.5.16.
    **PAYMENT PAUSED — cross-repo blocker + user decision 2026-08-30.** Claude ran the mvn gate in a
    `maven:3.9-eclipse-temurin-21` container (no host JDK; DooD socket mounted for Testcontainers). ALL unit + web-slice tests
    PASS on 3.5.16; SecurityConfig needed ZERO code change. Two latent breakages the bump surfaced: (1) FIXED (uncommitted) —
    Flyway skew, pom hardcoded `flyway-database-postgresql 13.3.0` vs SB-managed `flyway-core 11.7.2` → `NoSuchMethodError
    getExact`; fix = pin to `${flyway.version}`. (2) BLOCKER — Spring Cloud `CompatibilityNotMetException` (Boot 3.5.16 needs
    the 3.2.x train); Spring Cloud is transitive via `com.shoppingcart:rabbitmq-client` (Vault), NOT in the payment pom; verifier
    fires even though `rabbitmq.vault.enabled` defaults false. **User chose Option C: fix rabbitmq-client-java first.** Payment
    branch left with 2 good uncommitted pom edits; resumes after the library republishes.
  - **rabbitmq-client-java Boot 3.5 upgrade — spec written 2026-08-30 (unblocks payment CVE).** Spec
    `docs/issues/2026-08-30-rabbitmq-client-spring-boot-3.5-upgrade.md`. Bump `<spring-boot.version>` 3.2.0→3.5.16 +
    `<spring-cloud.version>` 2023.0.0→2025.0.x in `~/src/gitrepo/personal/shopping-carts/rabbitmq-client-java` (multi-module,
    v1.0.1, uses `VaultTemplate`/`spring-cloud-starter-vault-config`). Version bump 1.0.1→1.0.2, republish to GH Packages (CI
    on merge), then payment repins `<rabbitmq-client.version>`. Branch `feat/spring-boot-3.5-upgrade`. Execute same as payment:
    edits via Codex (its sandbox has no JDK), Claude container-verifies. Testcontainers (RabbitMQ+Vault) → needs Docker.
    **✅ DONE + VERIFIED + PUSHED 2026-08-30 — `51fa46fa` on `origin/feat/spring-boot-3.5-upgrade`.** Codex made the pom-only
    edits (spring-boot 3.5.16, spring-cloud **2025.0.3**, version 1.0.1→1.0.2 across parent+3 modules) but its sandbox blocked
    `.git` writes (`.git/index.lock: Operation not permitted` even as workdir) → Claude created the branch + committed+pushed.
    Claude container-verified (maven:3.9-eclipse-temurin-21): clean compile of ALL Vault code + **73 unit tests pass, 0 fail,
    NO code changes**. NOTE: the library's live-Vault integration suite runs via a dedicated CI job (`-P integration-tests`
    with Vault+RabbitMQ *services*, not Testcontainers) — that runs on the PR, NOT on feature-branch push (CI push trigger is
    main/develop/fix-ci-stabilization only). NEXT (gated): PR on the library → CI incl. integration job → merge → CI republishes
    1.0.2 to GH Packages → payment repins `<rabbitmq-client.version>` 1.0.0-SNAPSHOT→1.0.2 + finishes (commit the 2 held pom edits).
    **✅ LIBRARY MERGED + PUBLISHED 2026-08-30 (user go = "do all 4"): PR #8 admin-squash-merged `a4a4640f` on main.**
    Post-merge CI ALL GREEN — Build+Test ✅, **Integration Tests ✅ (live Vault+RabbitMQ services — real regression bar, no behavior change)**,
    Publish ✅. **`1.0.2` confirmed in GH Packages** (`gh api .../packages/maven/com.shoppingcart.rabbitmq-client/versions` → 1.0.2/1.0.1/1.0.0-SNAPSHOT).
    enforce_admins toggled off→merge→**restored true**. Copilot reviewer N/A on this repo (`Could not resolve login 'copilot'`); required check `CI`
    is a phantom context (actual check = `Build and Test`). **PAYMENT RESUMED**: repinned `<rabbitmq-client.version>`→1.0.2 (uncommitted, joins the 2 held
    pom edits), full container verify re-running (should clear the Spring Cloud CompatibilityNotMetException now that 1.0.2 carries the 2025.0.3 train).
    **✅ PAYMENT VERIFIED + PR OPEN 2026-08-30.** Container `mvn clean verify` = **BUILD SUCCESS, 130 tests 0 fail/err/skip** (incl. Testcontainers
    Postgres integration; Spring context loads clean on Boot 3.5.16 — compat blocker gone). 3 pom edits committed `2bc05325` on
    `origin/fix/payment-cve-spring-boot-bump` (parent 3.5.16 + rabbitmq 1.0.2 + flyway `${flyway.version}`), zero code changes. **PR #68 OPEN**
    (`fix(deps): bump spring-boot-starter-parent 3.2.0 -> 3.5.16 …`). **#68 MERGED** `ecdb421f` 08-31T00:45Z (squash). Copilot addressed both nits:
    flyway `${flyway.version}` override DECLINED w/ justification on-thread (binding = BOM flyway-core 11.7.2, keeps modules aligned); missing lib
    `v1.0.2` tag/release — CREATED on `rabbitmq-client-java` @ `a4a4640f` (package was published but git tag absent). Merge treadmill note: each merge
    fires a `ci: update ... [skip ci]` image-pin auto-commit on main → next PR goes BEHIND under the up-to-date ruleset; needs re-update-branch +
    Copilot re-request (review is per-head). Copilot #68 threads: replied + **RESOLVED** both (missed on first pass — user caught it;
    lesson [[feedback_copilot_resolve_threads_not_just_reply]]: "addressed" = REPLY + RESOLVE, sweep `isResolved:false` as a pre-merge gate).
    **✅ STEP 4 DONE — CVE→SIGN→VERIFY LOOP CLOSED 2026-08-31.** Payment main sign run `33345512446` (sha `ecdb421f`) all 6 jobs green;
    `Build, Scan & Push` pushed+**cosign-signed** new digest `sha256:8f195e336cb702c347e1b78193e9ad96143a82716d3cecaec7713307c21daab1`
    (tlog index 2656526539). **cosign verify PASSES** against the kyverno-synced pub key (logIndex matches CI). **trivy re-verify (fixed-only
    CRIT/HIGH): 0 CRITICAL (was 7 fixable), HIGH 42→9.** Residual 9 HIGH are NOT pom-fixable here: 3 base-image OpenSSL (alpine `libcrypto3`/
    `libssl3`/`openssl` 3.5.7→3.5.8, needs base rebuild), 3 `com.rabbitmq:amqp-client` 5.25.0→5.33.x (library-transitive → next rabbitmq-client-java
    bump), 2 `httpcore5` 5.3.6→5.4.3, 1 `postgresql` 42.7.11→42.7.12 → follow-ups, not blockers. Substrate re-pinned
    `services/shopping-cart-payment/kustomization.yaml` digest `3b5f478c…`→`8f195e33…`. "Do all 4" chain COMPLETE.
    **Dependabot cleanup (payment repo, user go):** #67 (parent→4.1.1) CLOSED as superseded (4.x breaks the 2025.0.3 train + oversized).
    #66 (fetch-metadata 2.3.0→3.1.0) **MERGED**; #65 (setup-java 5→6) **MERGED** 08-31T00:25Z (each merge invalidates the next under the up-to-date
    ruleset). Copilot review on payment repo IS enabled (`copilot-pull-request-reviewer`); user REQUIRES it — request via raw-JSON `--input -`.
  - **Stage C merges ✅ ALL 6 MERGED (2026-08-25/26, user go given; merge SHAs gh-verified 2026-08-28):**
    infra #94 `1fa7ab005b57148468d0d23c6aa33fcc193baff5`, frontend #99 `000bdcc0945fcc62f38c366c843193da72b9e88a`,
    basket #39 `6f5a57c90e66d6a0be5eb0c1fd4ab43a86a5dfc7`, order #72 `cb4403db0a16eace10e0ff06c900849f8d483c03`,
    product-catalog #51 `c42a5ccdc860a01c2cdd328136bce1e2364ec486`, payment #63 `fa396eef56f18445d4b52e0da07e59fe44e08a76`.
    All 5 backend callers now pin the signing-enabled infra reusable workflow `build-push-deploy.yml@1fa7ab0`.
    Pin bumps (on `feat/cosign-sign-attest`): order `da8fcc2e` (was 47769da), product-catalog `00665840`
    (was 6163fdf), payment `be796c6d` (was 47769da) — clean +1/-1 diffs; basket already pinned via its own
    `14f5b1257` (two harmless net-zero newline commits `b55c11eb`+`e67290ab` on its post-merge branch → prune
    in /post-merge). **BLOCKER RESOLVED:** workflow-file writes needed the `workflow` OAuth scope; user ran
    `gh auth refresh -s workflow`. Gotcha memory'd: [[reference_gh_contents_put_trailing_newline]]. **Ruleset
    handling:** order+payment enforce via `main-protection` rulesets (not classic protection) — order merged
    via enforcement disabled→merge→**restored to `active`**; payment merged via branch-update (ruleset left
    intact); both **gh-verified `active` 2026-08-28**. **⚠ POST-MERGE SIGNING BLOCKER (found 2026-08-28,
    spec `docs/bugs/2026-08-28-stage-c-cosign-signing-fails-post-merge.md`):** the cosign SIGN step FAILS on
    every image-building caller's post-merge main build — images are pushed to GHCR **unsigned**. TWO root
    causes: **(RC1)** basket/order/product-catalog/payment fail `getting signer: reading key: invalid pem
    block` — the `COSIGN_KEY` GH secret is the **hex encoding** of the PEM, because seeding piped
    `security find-generic-password -w` (which hex-encodes any value containing newlines) straight into `gh
    secret set`. The key itself is VALID (Keychain hex → `xxd -r -p` = clean 11-line `ENCRYPTED SIGSTORE
    PRIVATE KEY` PEM). Fix = re-seed `COSIGN_KEY` from true PEM via a **file** (`gh secret set COSIGN_KEY
    --repo R < cosign.key`), never `--body "$(security -w)"`. **(RC2, frontend only)** frontend's direct
    `ci.yml` `publish` job has NO job-level `env.COSIGN_KEY` (it's on the `docker` job) → `Install cosign`
    (`if: env.COSIGN_KEY != ''`) skips while `Sign image` (own step-env) runs → `cosign: command not found`
    (exit 127). Fix = add job-level `env.COSIGN_KEY` to `publish`. infra #94 builds no app image (n/a).
    **FIX IN PROGRESS (user go given 2026-08-28):** ✅ **RC1 re-seeded** — recovered true PEM via Keychain
    `xxd -r -p`, verified key+password load in cosign locally (derived pub saved `/tmp/cosign-verify.pub`),
    `gh secret set COSIGN_KEY --repo R < file` across all 5 image callers (frontend/basket/order/
    product-catalog/payment); private key never in argv, temp files 0600 + removed. `COSIGN_PASSWORD` left
    as-is (45-byte single-line, no newline → `security -w` returned it verbatim, uncorrupted). ✅ **RC2 PR
    open** — frontend `fix/cosign-publish-job-env` commit `d47e675c` adds job-level `env.COSIGN_KEY` to
    `publish` (diff verified clean +2, no newline strip); **PR #101** (https://github.com/wilddog64/
    shopping-cart-frontend/pull/101), **MERGED 2026-08-28 (user go), squash `85265e7b`**. ✅ **BLOCKER
    RESOLVED 2026-08-28:** all 5 main builds re-triggered → `Sign image by digest` = success; **`cosign
    verify --key <derived pub>` PASSES on all 5** (GHCR `sha256-<digest>.sig` present): basket `4a96cf41…`,
    order `ca2d398b…`, product-catalog `3db7b8da…`, payment `3b5f478c…`, frontend `ca25a636…`. ⚠
    product-catalog run still red on a SEPARATE pre-existing step "Fail when image promotion did not
    complete" (GitOps promotion, NOT signing; its main was red pre-Stage-C) — tracked apart. ✅ **Stage D
    AUDIT SLICE IMPLEMENTED 2026-08-28 (user go):** `signing.sh` +`_signing_install_kyverno`/
    `_signing_render_policy`/`_signing_apply_cluster_policy`/`deploy_image_signing [--audit|--enforce]`; new
    `cluster-policy-verify-images.yaml.tmpl` (verifyImages, **sig-only**, `ghcr.io/wilddog64/*` in
    `shopping-cart-apps`/`shopping-cart-payment` ONLY, Audit, webhook failurePolicy Ignore); Kyverno chart
    pinned 3.9.0; 12 BATS green; howto+functions.md. ✅ **Stage D AUDIT LIVE on hostinger 2026-08-29** (user go): added
     `deploy_image_signing --app-cluster` (skips hub Vault; ESO CSS `vault-backend` on the app cluster) +
     Kyverno-install-first reorder + `_signing_wait_pub_secret` + `SIGNING_KYVERNO_HELM_SET` (`ec746ade`,
     spec `docs/bugs/2026-08-29-signing-app-cluster-mode.md`, 16 BATS). Kyverno 1.19 field-name fix
     `ignoreTlog`/`ignoreSCT` (`bbbacfe0`; template used pre-1.19 `ignore:true` → strict-decode reject).
     hostinger runs its OWN Vault (bridged, not a KV replica) — had to seed cosign.pub (public ONLY) + grant
     `eso-app-cluster` role read on the app-cluster Vault (extended `app-cluster-reader`). Kyverno 4/4 Running
     (1 replica, tiny requests, node fine), `cosign-public-key` SecretSynced, ClusterPolicy Ready (Audit).
     **⚠ AUDIT FINDING:** Kyverno can't verify private `ghcr.io/wilddog64/*` — **401 UNAUTHORIZED** (registry
     auth, NOT signature; sigs known-good per Stage C). `docs/issues/2026-08-29-kyverno-verifyimages-ghcr-registry-auth.md`.
     **REGISTRY CREDS WIRED but STILL 401 (2026-08-29):** created ghcr `ExternalSecret` in kyverno ns
     (Vault `github/pat`→dockerconfigjson), helm-set `existingImagePullSecrets[0]=ghcr-pull-secret` →
     admission ctrl runs `--imagePullSecrets=ghcr-pull-secret`. Credential is VALID (curl Basic→ghcr token
     endpoint = 200) but Kyverno's cosign verifier sends NO auth (401 at token endpoint, fresh/uncached) —
     Kyverno 1.19 cosign path ignores `--imagePullSecrets`. **DefaultKeychain mount ALSO FAILED** (patched
     admission ctrl: `DOCKER_CONFIG=/kyverno-docker` + dockerconfig mount → fresh order-service dry-run still
     401). BOTH documented mechanisms ignored → Kyverno 1.19.0 cosign verifier builds its own cred-less
     registry client (upstream/version issue, not config-fixable). **NEXT (before Enforce):** Kyverno chart
     version bump (or upstream issue) — SEPARATE task → re-audit clean → `SIGNING_ALLOW_ENFORCE=1 --enforce`;
     then promoter `cosign verify` gate + `cosign attest` in CI. Codify: app-Vault seed/grant + kyverno-ns
     ghcr ES into signing.sh. Full diag: `docs/issues/2026-08-29-kyverno-verifyimages-ghcr-registry-auth.md`.
     **[SUPERSEDED next-line:]** run `deploy_image_signing
    --audit` against the APP cluster (ACG/hostinger — NOT the hub; no app ns there), watch PolicyReports →
    zero would-be-blocks → `SIGNING_ALLOW_ENFORCE=1 --enforce`; then promoter `cosign verify` gate in
    `app-cve-scan.sh` (needs cosign+pub in platform-ops CronJob image) + `cosign attest` in CI. Also
    /post-merge housekeeping (sync mains, prune `feat/cosign-sign-attest` branches incl. basket net-zero).
  4. `v1.27.0-adaptive-checkout-load-testing.md` — API-level checkout load + telemetry. **STARTED
     2026-08-24 (sliced).** E=adaptive controller + stop-condition hysteresis + unit tests →
     **DONE** Codex commit `17be2e69`, pushed to `origin/k3d-manager-v1.27.0`; pure decision logic +
     BATS 9/9, no cluster/Prometheus/k6/Stripe. PR URL: none (task prohibits PR creation);
     F=k6/Go generator + Grafana dashboard + live capacity run [Claude live, Stripe test-mode].
     **Slice F BLUEPRINT (2026-08-29, `docs/bugs/2026-08-29-loadtest-slice-f-generator.md`):** discovered +
     verified the full build: checkout = `POST /api/orders` on order-service (ns shopping-cart-apps, ClusterIP
     :8081, NodePort 30081) with `{customerId,items[{productId,productName,quantity,unitPrice}],shippingAddress,
     currency}` — synthetic items OK (no real product IDs needed); payment downstream (queue→payment-svc,
     Stripe test). Generator runs on laptop via `kubectl port-forward` (off the measured node). Metrics:
     `prometheus-pushgateway` (monitoring :9091) deployed, or enable Prometheus `enableRemoteWriteReceiver` +
     k6 `experimental-prometheus-rw`. **AUTH:** 401 without Bearer; issuer `https://keycloak.3ai-talk.org/
     realms/shopping-cart` is PUBLIC (no in-cluster trick). Token recipe: password grant, `client_id=
     order-service` (confidential, directAccessGrants=true, secret=Vault-resolved `${ORDER_SERVICE_CLIENT_
     SECRET}`), users federated from OpenLDAP (realm has no local users; `alice/password` dev). **NEXT:** fetch
     order-service client secret + confirm LDAP user → prove one authed `POST /api/orders` 201 → build k6 +
     wire Slice E stubs (`_loadtest_fetch_metrics`, `loadtest_run`) + Grafana dashboard + staged live run.
     **✅ SLICE F DONE 2026-08-31 — live run executed, gate correctness fixed + verified.** Live run used
     the `k3dm-smoke` Keycloak public client (password grant; secret off argv). **Two gate bugs found + fixed:**
     (1) every `LOADTEST_PROMQL_*` default with a `{...}` label selector was corrupted by `${VAR:-default}`
     brace-termination — the first `}` closed the parameter expansion → invalid PromQL → Prometheus 400 →
     `_loadtest_prom_query`'s `curl -sf` fails → `0` fallback → `breaches=[]` even at 88% real HTTP-429 errors.
     BATS never caught it (stubbed `_loadtest_curl`, never hit a real parser). Fix = `_loadtest_promql_default`
     helper (single-quoted default via `printf -v`; every `}` stays literal), all 8 defaults converted, new
     pinned-string BATS regression test → 17/17. (2) operational, not code: a stale hub port-forward
     `svc/prometheus-operated 19090:9090 --context k3d-k3d-cluster` squatted :19090, so k6 remote-wrote to /
     gates queried the **hub** Prometheus (no receiver → POST /write 404, no k6 series) instead of hostinger —
     confirm run still `breaches=[]` until found; fix = kill squatter, bind hostinger pod to :19090, verify via
     `runtimeinfo.startTime` + POST /write→415. Also: checkout.js status-0 mistag fixed (`>=200 && <400`);
     `loadtest_run` now records real `actual_throughput` (`LOADTEST_PROMQL_THROUGHPUT`). **Gate verified E2E:**
     25→200 VU confirm = stage25 `hold[error_rate]` → stage200 `stop[error_rate]`; 15-VU green = `hold[]`
     `actual_throughput 10.64`. **Capacity finding:** checkout ceiling ~20–21 req/s (app rate limiter in
     order-service `httpx/middleware.go`, 429-sheds excess); hostinger node (2CPU/8Gi) never the constraint.
     Full detail in `docs/bugs/2026-08-29-loadtest-slice-f-generator.md` (Status 2026-08-31 session 2).
     Substantial v1.27.0 work now down to remaining signing deferrals + remote-e2e acceptance gate + release.
     Verify Codex output on origin per [[feedback_codex_verification_protocol]] before trusting;
     note the `codex exec` sandbox has `.git` read-only, so expect Codex to leave files uncommitted
     and Claude commits after review (as with Slice A).
  - Finding 1a — ✅ FIXED + live-verified `5cd67228` (`num()` coerces empty/None→0 so one malformed
    value can't zero the scrape; `up{exporter}=1`, both E2E + CVE dashboards receiving data).
    `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.
  - Finding 2b — dispatcher `--confirm` strip on `deploy_app_cluster` — ✅ RESOLVED 2026-08-29
    (`3a6dddb0`). Guard publishes `K3DM_DEPLOY_CONFIRMED`; `deploy_app_cluster` honors it
    (additive, no blast radius; 5 other `--confirm`-as-`$1` sites are subtree
    `_provider_*_destroy_cluster`, not guard-gated). BATS `deploy_app_cluster_confirm.bats`
    (5/5) proves `--confirm` reaches the confirmed path. Spec
    `docs/bugs/2026-08-29-dispatcher-confirm-flag-deploy-app-cluster.md`; issue closed.

- **Dependabot automation — IMPLEMENTATION-READY (2026-08-29, `aa3bcc50`):**
  `docs/plans/v1.27.0-dependabot-automation.md` now carries the concrete reusable
  `workflow_call` workflow for `shopping-cart-infra` (author-gated on `dependabot[bot]`,
  `permissions:{}` default, pinned `fetch-metadata`, labels, rebase-on-dirty, allowlisted
  `--auto` merge, Slack-on-failure) + the thin per-repo caller + rollout order + pre-merge
  actionlint validation. Grounded in the existing baseline
  `shopping-cart-product-catalog/.github/workflows/dependabot-automerge.yml` (7 sc repos;
  product-catalog + basket/order/frontend/payment/e2e). Copilot-request + transient-retry
  = best-effort follow-ons. **Routes via branch+PR per sc spec-not-direct + PR-gate — NOT a
  direct push;** land in infra first, pin callers to the merged SHA, validate on one repo's
  real Dependabot PR, then roll to the rest. Product-catalog PR #51's skipped job is correct
  (author `wilddog64`, not `dependabot[bot]`).

- **Slack-secret redaction + branch prune — DONE (2026-08-29):** plaintext signing secret
  redacted from `docs/issues/2026-06-04-slack-slash-commands-wrong-url.md` and landed on `main`
  via `84e2917d`. Stale branch `security/redact-leaked-signing-secret` (was `b81c3da0`) pruned
  local + origin 2026-08-29 (content already on main; secret was already rotated/dead). No open
  branch or leak remaining.

- **v1.26.0 RELEASED** — PR #117 `1bbe5439` merged, tag/release published, protection restored
  (`enforce_admins=true`, 1 approval). Shipped 3/5 scopes (fleet count-agnostic lifecycle, E2E
  promotion gate + observability, managed registration cleanup). Retro
  `docs/retro/2026-08-21-v1.26.0-retrospective.md`. v1.25.0 = PR #116 `d48e465f`.
- v1.28.0 planned: parallel multi-cloud provisioning + zero-downtime rollouts.

## Open follow-ups

- **2026-09-01 frontend Keycloak login:** Hostinger frontend bundle uses the `frontend` client in
  realm `shopping-cart`, but the Keycloak realm has no such client (`clientId=frontend` returned
  `[]`), producing the browser's “Client not found” page. Bug recorded in
  `docs/issues/2026-09-01-frontend-keycloak-client-not-found.md`; create/reconcile the public
  client with the production callback before retesting.

- **2026-08-27 hub CPU overcommit — Step 1 IMPLEMENTED + live-applied (`85518a88`→`2a38670c`):**
  `docs/bugs/2026-08-27-hub-cpu-overcommit-resource-governance.md`. Diagnosed the CPU stress the
  federation-scrape tweak (`977d9e11`) could not fix: single 10-CPU/12.6GB hub VM oversubscribed
  (`docker stats` ~1414% vs 1000%; agent-2 426%, load avg 70; `/livez` 1.4–5.3s). Root = zero
  resource governance → unbounded `argocd-application-controller`/`repo-server` (`resources: {}`)
  starve apiserver → 24s status patches → ~4s hot reconcile loop on 25 apps → probe-kill restart
  storm (repo-server 221, svclb 465, coredns 143, keycloak 57). Plus istiod + istio-ingressgateway
  HPAs pinned 5/5 @80%-of-tiny-request (scale-out death spiral). **Both istio HPAs are IstioOperator-
  owned (`scripts/etc/istio-operator.yaml.tmpl` via `_istioctl install` in `k3d.sh`), NOT the ambient
  appset** (that targets remote clusters). **Committed:** requests+limits on all 6 ArgoCD components
  (`values.yaml.tmpl`; controller mem limit 2Gi to avoid OOM — CPU is the constraint) + pilot/ingress
  `hpaSpec:{min=max=1}`+limits (`istio-operator.yaml.tmpl`). **Live-applied** (ArgoCD is Helm-managed,
  no self-Application; no live istio operator reconciler → patches durable): `kubectl patch hpa
  istiod|istio-ingressgateway maxReplicas=1` (5→1 each) + `kubectl patch` controller/repo-server
  resources. **Result:** total CPU ~1414%→~1144% (~2.7 CPU freed); `/livez` 5.3s→~0.4s; agent-2 load
  70→39↓; new repo-server pod 0 restarts; restart storm FROZEN. `kubectl top nodes` UNDERCOUNTS
  (showed agent-2 ~15%); trust `docker stats`. **Istio durable rollout DONE via real tool:**
  `istioctl install -f <rendered istio-operator.yaml.tmpl>` (v1.30.0) reconciled live from committed
  config — HPAs now durably `MINPODS=1 MAXPODS=1` (operator-owned, not just the hand HPA patch),
  istiod limits 500m/1Gi + gateway 500m/512Mi applied, both pods fresh/healthy at ~44% CPU.
  (`istioctl install` foreground-times-out at 2m on the loaded hub — benign, k8s finishes the roll;
  verify with `kubectl get deploy/hpa -n istio-system`.) **ArgoCD formal redeploy DEFERRED** — see
  chart-drift follow-up; fix stays live (patched) + committed. **Step 2 load-shed IMPLEMENTED
  (config committed 2026-08-27; awaiting observability appset reapply for live rollout)**
  (`docs/bugs/2026-08-27-hub-load-shed-observability-footprint.md`): `lokiCanary.enabled: false`
  in `loki-values.yaml` (chart `loki-18.2.0`, canary is a top-level key — no selfMonitoring
  sub-block); `kube-prometheus-stack-values.yaml` `scrapeInterval`+`evaluationInterval` 30s→60s
  (the big CPU lever), `retention` 7d→3d, `retentionSize` 20GB→8GB. Prometheus CPU limit was
  already 1500m and etcd/scheduler/CM/coredns/kube-proxy scrapes already disabled — so those
  parts of the spec were pre-existing. **ROLLOUT PENDING:** reapply the `observability` appset
  with `K3D_MANAGER_BRANCH=k3d-manager-v1.27.0` so `$values` tracks the release branch, then
  ArgoCD selfHeal picks up the new values (loki-canary DaemonSet should disappear; prom CPU drops).
  Monitoring loop still running — hub was oscillating hot (load ~35–50, livez bursting to 20s)
  after Step 1, exactly the demand Step 2 removes.

- **2026-08-27 keycloak-0 restart loop FIXED live + committed + CoreDNS collateral fixed live**
  (`docs/bugs/2026-08-27-keycloak-restart-loop-tight-probes.md`): root cause was the SAME hub
  CPU starvation making Bitnami's **1-second probes** fail. keycloak-0 (67 restarts) was killed
  by liveness `tcpSocket period=1s failureThreshold=3` (SIGTERM 143) — NOT OOM. Fix in
  `scripts/etc/keycloak/values.yaml.tmpl` (previously set no probes/resources): liveness
  `period 1→10s failureThreshold 3→5`, readiness `timeout 1→5s`, **NEW startupProbe** (30s +
  40×10s = 430s grace), resources `750m/768Mi → 1000m/1Gi`. The startupProbe is the critical
  piece — Bitnami `start-dev` re-runs Quarkus augmentation every boot: live logs measured
  `augmentation 172742ms` + `started in 154.023s` = **~326s cold start**, so the old ~170s
  liveness window killed it mid-boot forever. Applied LIVE via `kubectl patch statefulset/keycloak`
  (KEYCLOAK_HELM_CHART_VERSION is empty=latest, so a `helm upgrade`/`deploy_keycloak` would risk a
  chart bump off `keycloak-25.2.0` + Bitnami-deprecation pull failure — patch was the low-risk
  path; template edit makes it durable at next deploy). keycloak-0 now **1/1, 0 restarts**.
  ⚠ **Rolling the pod exposed CoreDNS in CrashLoopBackOff (155 restarts, deploy 0/1)** — same
  1s-probe-under-CPU-starvation disease (`plugin/health … took more than 1s: 1.93s` → liveness
  SIGTERM). DNS was cluster-wide down; only cached-connection pods survived. Live-patched
  `deploy/coredns` liveness `timeout 1→5s failureThreshold 3→5`, readiness `timeout 1→3s` →
  CoreDNS `1/1` stable, DNS restored. **⚠ CoreDNS patch NOT in git — k3s-managed**
  (`k3s.cattle.io` owner, on-node `coredns.yaml`); k3s addon controller may revert. FOLLOW-UP:
  persist via k3s manifest override/HelmChartConfig, or land Step 2 load-shed so 1s probes stop
  failing at the source. This is fresh evidence Step 2 is no longer optional.

- **2026-08-27 hub-wide CPU-starvation cascade INCIDENT (mitigated live).** The keycloak dig
  uncovered that 1s liveness/readiness probes were failing platform-wide under CPU starvation,
  crashlooping EVERY core component into a deadlock: coredns (DNS down), loki-canary (4 pods,
  200+ restarts each), argocd-repo-server (probe-killed 40× → ArgoCD couldn't render manifests →
  couldn't sync the Step 2 relief → deadlock), and **agent-0 node went NotReady** (kubelet
  starved). User ran the Step 2 appset reapply (`applicationset observability configured`, now
  `$values`=k3d-manager-v1.27.0), but ArgoCD sync stayed `Unknown` because repo-server was down
  and then because rendering the big kube-prometheus-stack chart timed out (`DeadlineExceeded`).
  Live mitigations (NOT all in git): (1) `kubectl patch deploy argocd-repo-server` → light
  `/healthz` probes + startupProbe + 10s timeout (broke the deadlock; repo-server 1/1 stable);
  (2) `kubectl delete ds loki-canary` + force-deleted its pods (biggest immediate CPU win);
  (3) `kubectl patch prometheus kube-prometheus-stack-prometheus` → scrape/eval 30s→60s,
  retention 7d→3d, retentionSize 8GB **directly on the CR** (bypasses the timed-out chart
  render; operator regenerates config; ArgoCD sync is stuck so won't revert; and v1.27.0 values
  ALSO say 60s so they AGREE when sync eventually lands). Result: all 4 nodes Ready again
  (agent-0 self-recovered), keycloak/coredns/repo-server/argocd-server stable (restart counters
  frozen), Prometheus cut to 60s + counter frozen, replaying TSDB toward 2/2. ⚠ Live-only debts
  to reconcile: repo-server probe patch (ArgoCD-self-managed → reverts to 1s on next argocd
  self-sync — OK once CPU is free), coredns patch (k3s-managed), metrics-server was briefly
  unavailable. Durable resolution = the committed v1.27.0 Step 2 config syncing once repo-server
  can render the chart under freed CPU. Prometheus prometheusSpec should also carry a startupProbe
  headroom review, but its probes are already sane (not a 1s victim).

- **2026-08-28 node-health-watch was bouncing agent-0 in a restart loop (mitigated live +
  durable fix committed).** Morning regression: agent-0 `NotReady`, coredns `0/1` (DNS
  endpoints empty), prometheus-0 `Pending`/`Unknown`. Root cause was NOT a new probe bug and
  NOT OOM (`RestartCount=0 OOMKilled=false ExitCode=0` = external restarter). The launchd
  watchdog `com.k3d-manager.node-health-watch` (`bin/k3dm-node-health-watch`,
  `K3DM_NODE_RECOVERY_ENABLED=1`) polls `/healthz` with a 5s timeout; under CPU pressure that
  times out on a **slow-but-`Ready`** node, 3 fails (~90s) → `docker restart agent-0`, 300s
  cooldown, repeat ~every 6 min (log: restart 04:11→recover 04:13→fail→restart 04:17 PDT). Each
  bounce takes DNS down (coredns is a single replica pinned to agent-0) and strands Prometheus
  (its local-path PVC is on agent-0) → net-harmful. This is the **node-level instance of the
  1s-probe disease** ([[reference_one_second_probes_cpu_starvation_kill_loop]]). Live mitigation:
  `launchctl bootout gui/$(id -u)/com.k3d-manager.node-health-watch` → restarts stopped, agent-0
  holds Ready on its own (self-recovers), coredns 1/1, DNS restored, Prometheus rescheduled and
  replaying TSDB. Durable fix committed: `bin/k3dm-node-health-watch` now triggers recovery only
  on the authoritative `_ready`=False verdict (a Ready-but-slow `/healthz` is advisory, no
  restart), healthz timeout 5s→15s (`K3DM_NODE_RECOVERY_HEALTHZ_TIMEOUT`), threshold 3→5. Spec
  `docs/bugs/2026-08-28-node-health-watch-restart-loop-slow-node.md`. ⚠ Watchdog is currently
  **unloaded** — reload it (`launchctl bootstrap`) only after the fixed script is the one on
  disk AND the hub CPU has calmed; follow-up fragility: coredns SPOF + prometheus PVC both
  hostage to agent-0.

- **2026-08-28 chronic hub CPU overcommit persists after the watchdog fix — `make status` blocked
  on a pegged control plane.** With the self-inflicted node bounces stopped, all 4 nodes hold Ready,
  but the hub is still CPU-overcommitted at the source. `docker stats --no-stream`: server-0
  **492%**, agent-1 344%, agent-2 270%, agent-0 226% (~1333% total). Inside server-0: `/bin/k3s
  server` (embedded apiserver+etcd+controller-manager+scheduler) at **71%** of the node with **load
  average 60**; co-located discretionary load = `trivy server` (29% VSZ), an istio ingress-gateway
  envoy, kube-state-metrics, access-log-exporter, node_exporter. Consequence: every `kubectl` LIST
  times out (single-namespace `get pods` fails at 30s; `top nodes` times out), and the webhook
  `/api/v1/health` aggregator times out at 90s → `make status` reports `Overall: UNKNOWN / status
  source: webhook unavailable`. The webhook process itself is healthy (listening :7443, 401 without
  a token) — restarting it will NOT help; the blocker is the pegged apiserver, not the webhook.
  Durable fix = the committed Step 1+Step 2 load-shed governance (recent commits on
  `k3d-manager-v1.27.0`), but it is **inert** until ArgoCD reapplies it, and ArgoCD can't
  render/sync while the control plane is drowning (chicken-and-egg). Prior live sheds (prom 60s
  scrape, loki-canary off) are live but insufficient. Decision pending: reduce discretionary
  control-plane churn live (candidate: `trivy-operator` scale-to-0 — reversible, non-user-facing)
  vs. force the committed governance to sync. Same disease family as
  [[reference_one_second_probes_cpu_starvation_kill_loop]].
  - **RESOLVED 2026-08-28 via cluster restart (user-authorized).** Live shed alone did NOT help:
    scaled `trivy-operator` (trivy-system) → 0 and `loki`/`loki-gateway` (monitoring) → 0, but
    server-0 kept *climbing* (492→707→867%, oscillating 540-845% over 90s) because the bottleneck
    is the apiserver's own list/watch/reconcile churn, and pod terminations add to it — shedding
    agent workloads doesn't relieve the control plane. `k3d cluster stop/start k3d-cluster` cleared
    the accumulated churn: server-0 settled 607→**50%**, all 4 nodes Ready throughout, **coredns
    stayed 1/1 on the way up** (looser probes + startupProbe held — no DNS outage). Post-restart:
    apiserver responsive, `make status` completes. Recovery lesson: for a churn-storm on the k3d
    control plane, a cluster restart is the effective lever, NOT workload shedding.
  - **Post-restart Vault was sealed** (expected — raft/shamir, threshold 1). Unsealed via cached
    shards: `./scripts/k3d-manager deploy_vault --re-unseal` (keys in Keychain `k3d-manager-vault-unseal`
    + in-cluster `vault-unseal` Secret, both present). vault-0 → 1/1. ⚠ The `vault_install_unseal_watchdog`
    is NOT deployed, so Vault will need a manual `deploy_vault --re-unseal` after every restart until
    the watchdog is installed.
  - **RESTORED 2026-08-28 (user-authorized):** `trivy-operator`, `loki`, `loki-gateway` back to 1
    (all Running/Ready). ⚠ **CPU tradeoff quantified:** with them shed server-0 sat at **50%**; with
    them restored server-0 settled at **~360%** (a 617% loki cold-start spike that decayed) — 7× the
    shed headroom and much closer to the pressure edge that caused the incident. Still functional
    (apiserver responsive, nodes Ready), but loki is the heavy one; re-shed loki if steady-state
    headroom feels tight on this M4 Air. Also re-enabled the `node-health-watch` watchdog
    (`launchctl bootstrap`, PID confirmed) now running the FIXED script (`2b2d5705`) — validated live:
    logged `agent-0 Ready but /healthz slow/unreachable (advisory, no restart)` and `NotReady (1/5)`
    then stopped (self-recovered before threshold 5) — did NOT bounce the node.
  - **`make status` final: all hub infra GREEN** (ArgoCD/Keycloak/Prometheus/Grafana 200, ESO 18/18,
    data 4/4, Keycloak+ArgoCD+Grafana login OK). Sole remaining red = **`Frontend login: HTTP 401 on
    /api/cart` — a smoke-harness artifact, NOT a hub fault**: `k3dm-smoke-user` Secret absent →
    Keycloak login falls back to the Helm admin Secret (master-realm `admin-cli` token) → that admin
    token correctly can't authenticate to the app frontend, and the graceful 401/403 skip guard
    (`bin/k3dm-webhook` ~1831) only fires for `kc_via_smoke_client`, not the admin-cli fallback, so a
    correct 401 is reported as a hard FAIL. Fix candidate: extend the skip guard to the admin-cli
    fallback, or seed a real `k3dm-smoke-user`. Matches the known status-login false-green limitation.
  - **2026-08-28 Frontend login → TRUE GREEN** (`✓ Frontend login: HTTP 200 on /api/cart`). Root cause
    was 3 factors, all live-fixed on the hub Keycloak: (1) no `shopping-cart` realm existed — created it
    mirroring `home` (LDAP federation) + a public direct-grant client `k3dm-smoke`; (2) issuer mismatch —
    tokens minted locally carried a `localhost`/`.local` `iss`, never basket-service's trusted
    `https://keycloak.3ai-talk.org/realms/shopping-cart`; fixed by pinning the realm
    `attributes.frontendUrl=https://keycloak.3ai-talk.org` so **every** locally-minted token carries the
    public `iss` (no Cloudflare round-trip, verified via `.well-known`); (3) cloned LDAP component bound
    with a **masked** `bindCredential` (`**********` from the admin API) → `LDAP error 49 Invalid
    Credentials` on every federated mint; fixed by PUTting the real `LDAP_ADMIN_PASSWORD` (Secret
    `openldap-admin`, bindDn `cn=ldap-admin,dc=home,dc=org`). Smoke **user** is an LDAP entry
    (`cn=k3dm-smoke,ou=users,dc=home,dc=org`) — READ_ONLY LDAP refuses local Keycloak user creation.
    Seeded Secret `identity/k3dm-smoke-user` (username/password/realm/client; pw via stdin, not argv).
    **Webhook code change:** removed `kc_token_is_stub=True` from the smoke-client branch (a real seeded
    smoke user must green on 200 / red on genuine 401; only admin-cli/master fallback stays a skip) +
    reads optional `realm` key from the Secret. Spec: `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`
    (durable-follow-up section). ⚠ Live realm/LDAP/client/user/Secret WERE ephemeral — **now codified**:
    **`keycloak_provision_shopping_cart_realm`** (`keycloak.sh`) idempotently creates the realm + pins
    `frontendUrl` (`KEYCLOAK_SMOKE_ISSUER_BASE_URL`, overridable), clones the LDAP provider from `home`
    and repairs the masked `bindCredential` from Secret `openldap-admin`, creates the `k3dm-smoke` client,
    adds the LDAP smoke user (bind pw via stdin→0600 pod file, generated user pw), and writes
    `identity/k3dm-smoke-user`. Live-verified idempotent: re-run → `iss=…/realms/shopping-cart` →
    `/api/cart` **200**. Reach admin API with `KEYCLOAK_BASE_URL=http://localhost:8880` (keycloak PF up).
    Older `keycloak_seed_smoke_user` retained but wrong for this deployment (see spec) — prefer the new fn.
  - **⚠ 2026-08-28 hub CPU crisis recurred mid-session** — while completing the above, `docker stats`
    showed server-0 **454–568%**, agents ~200–330% each (~1170–1550% total on the M4 Air), and
    `/readyz` flapped `etcd failed`/`etcd-readiness failed`. Symptoms: `:8880` keycloak PF dropping to
    `000`, coredns 4× restarts → keycloak `UnknownHostException: keycloak-postgresql`, keycloak DB pool
    500s. Steady hogs (`kubectl top`): argocd-application-controller 733m, prometheus 681m; plus a
    trivy scan burst (10+ scan pods). Same disease family as the chronic overcommit above — the Step 1/2
    governance is committed but **inert until ArgoCD syncs it**.
    - **CPU-reduction pass applied 2026-08-28** (durable in-repo + live): (1) `vault-unseal-watchdog`
      CronJob cadence **`* * * * *` → `*/5 * * * *`** (`scripts/etc/vault/unseal-watchdog.yaml.tmpl`) —
      cuts 1,440 pod-spawns/day of node churn 5×; (2) ArgoCD `timeout.reconciliation` **120s (chart
      default) → 180s** (`scripts/etc/argocd/values.yaml.tmpl` `configs.cm` + live `argocd-cm` patch) —
      relaxes the 727m application-controller's full-resync cadence; takes effect on next controller
      restart (NOT force-restarted — a restart triggers a full re-sync burst). Prometheus already
      conservative (60s scrape / 3d retention) — left as-is. Snapshot at time of pass: prometheus 754m,
      argocd-application-controller 727m, argocd-repo-server 386m, vault-0 368m, keycloak 162m.
    - **Monitoring pause/resume toggle — DONE + live-verified 2026-08-28** (the "biggest optional lever",
      now built): `observability_pause` / `observability_resume` (`scripts/plugins/observability.sh`) +
      `make monitoring-pause` / `make monitoring-resume`. Scales the whole hub observability stack
      (prometheus+grafana+loki+alertmanager+kube-state-metrics+trivy) to zero on demand — reclaims
      **~1.1 cores** (measured: prometheus 730m + grafana 273m + alertmanager 37m + ksm 18m); node-exporter
      DaemonSet (~15m) left running. **Keeps production-grade config fully intact** — pause only scales
      replicas + suspends auto-sync; resume reconciles the identical committed chart values (scrape 60s /
      retention 3d / all rules unchanged). Nothing deleted, PVCs untouched → history survives within 3d.
      **Two-controller mechanism** (both required, learned live): (1) selfHeal defeated by patching each
      app `spec.syncPolicy.automated=null`; (2) that patch made durable by committing
      `ignoreApplicationDifferences: [/spec/syncPolicy/automated]` to the `observability` ApplicationSet
      (the app-level `skip-reconcile` annotation is STRIPPED by appset re-templating within seconds — does
      NOT work); (3) prometheus/alertmanager are operator-reconciled CRs — scale via the CR, not the STS.
      Resume scales workloads back **explicitly** (operator→CRs→deploy/sts to 1), NOT via ArgoCD sync —
      sync goes `Unknown`/slow exactly under the CPU starvation this feature targets. Spec:
      `docs/bugs/2026-08-28-monitoring-pause-resume-toggle.md`. Config-tune levers (#1 scrape, #2 retention)
      confirmed already spent; trivy is event-driven not cron — so the toggle is the remaining real lever.
    - **`make status` made pause-aware (2026-08-28, `bin/k3dm-webhook`)** — with monitoring paused, status
      previously hard-FAILed on Prometheus/Grafana/Grafana-login 502s. Added `_monitoring_paused()` +
      downgrade pass: when the hub `kube-prometheus-stack` ArgoCD app exists AND `spec.syncPolicy.automated`
      is empty (the deliberate-pause signal, distinguishes pause from crash), those three become `⚪` warnings
      (`monitoring paused (make monitoring-resume)`) → `Overall: WARN`, exit 0. **Two gotchas fixed live:**
      (a) query the **hub/INFRA context** `k3d-k3d-cluster`, NOT `_provider_context()` (returns app cluster
      `ubuntu-k3s`, no such app); (b) **NO provider gate** — `make status` resolves to `k3s-hostinger`
      (Makefile `CLUSTER_PROVIDER=k3s-aws` origin=file → recipe forces hostinger), and the `*.3ai-talk.org`
      Prometheus/Grafana URLs front the hub via cloudflared, so paused-hub explains the 502 in every mode.
      Safety verified: apps with `automated` set → not-paused → real outages stay hard errors. `make
      restart-webhook` required after edits. Spec: `docs/bugs/2026-08-28-status-monitoring-paused-false-fail.md`.
    - **Live CPU proof (2026-08-28):** monitoring running → Keycloak `/realms/master` 1.6–6.3s (erratic) →
      login smoke read-timeout FAILs; after `monitoring-pause` → **9–26ms**, server-node CPU recovers from
      `<unknown>`. Concrete evidence the stack starves Keycloak + API server.
    - **RESUMED to Layer 1 2026-08-28** (decision: user wants Layer 1 = reduced-rate stack always on,
      loginable Grafana, `monitoring-pause`/`resume` as the on-demand escape hatch — pause is NOT the
      default). `make monitoring-resume` restored all workloads to 1; `make status` → **HEALTHY** (all
      green incl. Grafana HTTP 200 + Grafana login 200 + Keycloak token minted). Note: pause scales
      **Grafana too** → no login while paused (Grafana without Prometheus shows empty panels anyway);
      "always loginable" = live in Layer 1, don't pause.
    - **⚠️ Resume gotcha — laptop-sleep clock jump (2026-08-28):** during resume the M4 slept; the k3d
      Docker VM clock froze (~20:54Z) then jumped forward ~3h on wake. Forward jump made
      CrashLoopBackOff burst-fire all pending restarts (ksm/operator counters shot to 43/33) + Prometheus
      "out-of-order samples" + operator "context deadline exceeded". NOT a resume bug. Recovery: clocks
      re-sync on their own; **delete the stateless scarred pods** (ksm, operator — no PVC) so they restart
      with `restarts=0`. Verified clean (both came up 0 restarts, stable). See auto-memory
      `reference_laptop_sleep_clock_jump_crashloop`.

- **2026-08-27 ArgoCD chart-version drift (BLOCKS formal deploy_argocd redeploy):** live helm release
  `argocd` is chart **`argo-cd-10.4.0`** (app v3.5.1, revision 1, deployed 2026-08-20) but the repo
  pins `ARGOCD_CHART_VERSION=7.8.1` (`argocd.sh:53`). Running full `deploy_argocd` could unintentionally
  change the chart version → regression risk, so the Step-1 argocd resource limits were NOT applied via
  helm (only live `kubectl patch` on controller+repo-server + committed to `values.yaml.tmpl`). Helm
  release state has no resource values → a non-tmpl `helm upgrade --reuse-values` would strip them
  (normal `deploy_argocd` re-renders the tmpl → keeps them). **Reconcile the pin (7.8.1→10.4.0, or
  downgrade live) BEFORE any formal argocd redeploy.** Surgical durable option if needed sooner:
  `helm upgrade argocd argo/argo-cd --version 10.4.0 -n cicd --reuse-values -f <resources-only overlay>`.

- **2026-08-27 federation scrape tuning:** source commit `977d9e11` changes the hub `federate-acg`
  Prometheus scrape interval from 30s to 60s; the vulnerability exporter remains at 60s. YAML
  parsing passed. Requires the observability values to be reapplied before live effect; monitor
  M4 CPU/API latency afterward.

- **2026-08-27 status credential discovery:** commit `f07adea8` adds fallback to the deployed
  password-only `identity/keycloak-admin-secret` (master realm/admin-cli) for smoke login checks;
  webhook tests pass. Prometheus/public endpoints recovered after OrbStack + edge restart, but the
  aggregate health sweep remains slow under control-plane load.

- **2026-08-27 hub control-plane outage:** restarting agent-0 and the k3s server did not restore
  the API. Kine reported slow SQL/handler timeouts and hub containers saturated CPU; Prometheus
  remained unavailable. Incident recorded in `docs/issues/2026-08-27-hub-control-plane-still-unavailable.md`.

- **E2E transient cleanup (2026-08-27):** commit `6b20cced` pushed on `k3d-manager-v1.27.0`.
  `_e2e_teardown` now best-effort removes orphaned vCluster kubeconfigs/proxies and transient
  per-run logs while retaining JSON audit summaries; regression coverage added. Host remains
  CPU-saturated by OrbStack/browser workloads, so m2 remains the preferred E2E runner.

- **Hostinger access-layer recovery (2026-08-26):** k3d agent-0 exited (143), causing hub workload
  evictions and local ArgoCD/Keycloak/Prometheus 502s; restarting the single stopped container
  restored all hub nodes to Ready and Prometheus replayed its WAL. Commit `44de06f7` fixes the
  Keycloak forward from service port 80 to 8080, pins tunnel/health probes to IPv4, and uses the
  valid `/realms/master` status path. Focused BATS 68/68, shellcheck, and `_agent_audit` passed.
  Repeated direct public probes reached ArgoCD/Keycloak 200; wrapper flapping remains a live
  follow-up when transient port-forward client resets occur. The shared wrapper now tolerates
  three consecutive health failures, retries after 2 seconds, and binds kubectl to IPv4; local
  ArgoCD and Keycloak checks returned 200 after regeneration. Fix commit `a5dc3967` is pushed.
  Incident:
  `docs/issues/2026-08-26-hostinger-keycloak-port-forward-service-port.md`.

- **Hostinger capacity check (2026-08-26):** live node `srv1754834` has 2 vCPU / 7.75 GiB RAM;
  current requests are 1610m CPU (80%) and 4880Mi memory (61%), while observed usage is 404m CPU
  (20%) and 5496Mi node memory (69%). It currently runs 44 pods, including ArgoCD, Vault, ESO,
  Prometheus, Loki, Trivy, and all shopping-cart services. Moving Keycloak+PostgreSQL there would
  fit steady-state usage but leaves inadequate CPU/request and rollout-failure headroom; defer until
  the node is upgraded to at least 4 vCPU/16 GiB or a second worker is added.

- **M2 E2E acceptance blocked (2026-08-25):** bootstrap/preflight passed and the intentional
  invalid-digest run produced a failed artifact, but publisher variables were absent. Replay
  and the passing run are blocked because `m2jump` cannot resolve `m2-air.local`. Evidence:
  `docs/issues/2026-08-25-m2-e2e-acceptance-blocked.md`.

- **CVE remediation panels empty — FINAL root cause (Claude 2026-08-25).** Two prior RCs were
  incomplete: Codex's "in-memory/no durable source" was WRONG (the CM-based durable source
  exists); my own "missing app-rebuild secret" was NECESSARY-BUT-NOT-SUFFICIENT. **Fixed the
  secret half (live):** stored classic PAT (`repo`+`read:packages`) as Keychain
  `platform-ops-app-rebuild/k3dm` → `argocd_sync_app_rebuild_secret` created the Secret →
  deleted 32h-wedged job `cve-auto-1787541034` → manual run `cve-verify-1787657822` completed
  clean, GHCR auth works, `product-catalog`+`payment` PROMOTED for real HIGH/CRIT CVEs.
  **Panels STILL empty → true RC (Bug A):** *nothing in the repo CREATES* the
  `k3dm.k3d.io/cve-remediation-event=true` ConfigMaps — `cve-remediation-verify.sh` only
  reads/transitions them, the exporter only reads them, and `app-cve-scan.sh` `_promote_image()`
  does live-patch+git-persist+notify but emits NO event CM. Consumer+exporter read events the
  producer never writes. **Bug B surfaced:** `_git_persist_promotion()` writes its askpass helper
  into the same dir it `git clone`s into → clone fails 100% ("destination not empty"), promotions
  are live-patch-only (revert on next ArgoCD sync). Token/netpol/git+CA all ruled out.
  **Fixes APPLIED + live-deployed (commit `915d1459`):** (A) `_promote_image()` now emits a
  durable `cve-remediation-event` CM via new `_emit_remediation_event()` — **verified end-to-end**
  (applied one such CM live → exporter emitted `cve_remediation_event_info{current="true"}`, the
  panels' query, cve_ids parsed; test CM deleted). (B) `_git_persist_promotion()` clones into
  `${_p_work}/repo` so the askpass helper no longer poisons the dest — **VERIFIED LIVE
  (deterministic, `7a830dda`+repro):** the failure is CVE-independent, so confirmed with a repro pod
  on real `aquasec/trivy:0.63.0` + live `platform-ops-git-writer/git-token` — OLD path reproduced
  `fatal: destination path '…' already exists and is not an empty directory`, NEW path cloned OK
  with `services/shopping-cart-payment/kustomization.yaml` at HEAD 7a830dd on k3d-manager-v1.27.0
  (no push). A pre-fix `cve-auto` pod on 08-25 had again logged `GITWRITE … clone … failed`,
  confirming the bug was 100% live before the fix. Deployed live by re-creating the
  `argocd-cve-scan-script` CM. **Hardening/UX DONE (`65bf4e31`):** (1) `argocd_sync_app_rebuild_secret`
  `_warn`s loudly when PAT absent + CronJob exists + no Secret (the wedge condition), stays optional
  otherwise; (2) `activeDeadlineSeconds: 1200` on the app-cve-scan CronJob (live) so a
  CreateContainerConfigError pod self-terminates in 20m vs the 32h backoffLimit-never-trips wedge;
  (3) no-data `description` on both remediation panels (live in monitoring CM). Full trail in
  `docs/issues/2026-08-24-cve-remediation-panels-empty.md` +
  `docs/bugs/2026-08-25-git-persist-clone-into-nonempty-dir.md`.

- **✅ CVE panel ② ("Shopping-cart Unique CVEs") — RESOLVED + DURABLE (2026-08-24).** 75 actionable
  `trivy_vulnerability_inventory{image_repository=~"wilddog64/shopping-cart-.*"}` series, native
  operator-generated (self-refreshing 24h TTL), Prometheus-verified. Three durable commits in
  `trivy-operator-acg-values.yaml`: `49477017` (`trivy.slow`+`timeout 15m0s`) + `8bfcbcc9` (scan-job
  CPU request `50m→10m`) + **`aac9cb27` (`operator.privateRegistryScanSecretsNames` +
  `accessGlobalSecretsAndServiceAccount: true`)**. Real root cause: workloads carry NO imagePullSecret
  anywhere (pod spec AND `default` SA empty) → private images pull via node-level containerd cred,
  invisible to the operator → silent skip; operator-upgrade is a dead end. Manual-CR stopgap (352
  all-sev) deleted in favor of native (75 actionable). Hub-side wiring (RBAC/ESO/appset `84817d88`,
  live Vault SA + policy fixes `9c9c8bb8`/`0f7ea0ad`) complete + verified end-to-end.
  Bug: `docs/bugs/2026-08-24-trivy-operator-skips-private-images-sa-imagepullsecret.md`.
  Auto-memory: `reference_trivy_operator_node_cred_private_image_skip`.
  - **Close-out (2026-08-24, both done):** (a) `acg-trivy-operator` **ArgoCD-synced** — the 3
    OutOfSync resources converged via a manual sync (ref `k3d-manager-v1.27.0` contains `aac9cb27`,
    so the private-registry env survived); app Synced/Healthy, panel ② held at 75 (payment 52 / order
    11 / basket 8 / product-catalog 4). (b) `allow-cve-scan-egress` netpol given a durable home —
    **spec'd + pushed** to shopping-cart-payment `docs/plans/durable-trivy-scan-coverage.md` (branch
    `feat/trivy-scan-egress-netpol`, `3ca0dca`, PR gated); flags the kustomize `commonLabels`→selector
    gotcha + optional SA imagePullSecrets hardening. Live netpol stays drift until that merges. The
    originally-planned pod-spec imagePullSecrets / scan-CR CronJob / operator upgrade are
    UNNECESSARY / redundant+harmful / dead — see bug doc "reassessed".
  - ⚠️ The 2026-08-23 "ArgoCD stale-render bug" was a **mis-diagnosis** (I read the hub's own trivy
    configmap, not hostinger's `acg-trivy-operator`, which has no `automated` syncPolicy so manual
    patches stick). Durable git fixes are correct + live.

- **Keycloak hub deploy DONE + dev SSO RESOLVED (2026-08-22).** `keycloak-0` 1/1, VirtualService
  live (`keycloak.3ai-talk.org/realms/master` 200); port-forward remote-port bug fixed (`04cc1e14`,
  →8080). Realm `home` (`dc=home,dc=org`) is the DESIGNED truth; admin/developer/operator synced,
  the only gap was missing LDAP passwords — fixed `bin/cluster-up` step 10d.5 seed loop (`9efb23f7`)
  + live `seed-dev-sso-passwords.sh` (all 3 verified via ldapwhoami, mirrored to
  `secret/keycloak/users/*`). Steps 10d.6/10d.7 realm-federation reconcile are broken+redundant →
  follow-up: delete or retarget `-r home`. **SSO login round-trip to realm `home` still to be
  confirmed by user.** Docs `docs/bugs/2026-08-22-keycloak-*`, `-hub-openldap-wrong-realm-*`.

- **hostinger istiod-scheduling cascade RESOLVED — 3/3 (2026-08-22).** Single 2-CPU node
  `srv1754834` chronically 95–98% CPU requests; istiod Pending 2d → ambient mesh down →
  product-catalog CrashLoop + frontend stuck. Break-glass restored istiod+frontend; product-catalog
  durable via PR #49 `505f758a` (cpu 100m→50m). **ArgoCD source gotcha (keep):** the hub app reads
  `repo=k3d-manager rev=k3d-manager-v1.26.0` whose kustomization pulls REMOTE
  `shopping-cart-product-catalog//k8s/base?ref=main`; a `refresh=hard` annotation re-fetched `ref=main`
  → OutOfSync, user-run `kubectl patch cpu=50m` landed it (durable, selfHeal won't revert).

- **hostinger CPU right-sizing — durable fix committed, ACTIVATION PENDING (2026-08-24).**
  Investigated: node `srv1754834` is **request-bound, not load-bound** — CPU *requests* 98%
  booked (1960m/2000m, 40m free) while *actual* usage ~20% (419m). 0 pending / no FailedScheduling
  at rest; the risk is a future rollout deadlock (surge pod > 40m free → the
  `hostinger_maxsurge_rollout_deadlock` / istiod-cascade class). Durable overlay patches committed
  `6851b5b0` on `k3d-manager-v1.27.0` (`services/shopping-cart-*/kustomization.yaml`): payment
  requests.cpu 200m→50m (+150m); basket/order/frontend maxSurge=1/unavail=0 → maxSurge=0/unavail=1.
  Each `kubectl kustomize` build verified. **INERT until activated:** the `services-git` appset renders
  app `targetRevision` from `${K3D_MANAGER_BRANCH}`, frozen at `k3d-manager-v1.26.0`; `services/` is
  byte-identical v1.26.0↔v1.27.0 so reapplying at `k3d-manager-v1.27.0` pulls ONLY this fix. Live
  patches will NOT stick (all 5 apps `selfHeal=true`). **All three prepped 2026-08-24:**
  (a) `services-git` appset re-rendered at v1.27.0 (server-diff = ONLY the branch ref moves) — apply
  BLOCKED by classifier, handed to user as a `!` command (`kubectl apply -f
  .../services-git-v127.yaml`). (b) rabbitmq 200m→50m committed `1a85dc7a` on branch
  `feat/rabbitmq-cpu-request-trim` in `shopping-cart-infra` → **PR #93 MERGED** `59ed6342` on
  2026-08-24. `enforce_admins` RESTORED (confirmed `true`); `required_reviews` remains 1. Rabbitmq trim
  now live on ref=main (ArgoCD will roll to hostinger via data-layer app read).
  (c) istiod pilot cpu 100m→50m committed `1dbe68dc` on v1.27.0 in
  `scripts/etc/argocd/applicationsets/istio-ambient.yaml` — istiod `maxSurge=100%` is a hardcoded istio
  chart default (NOT helm-overridable in a pure-helm ArgoCD source), so the request trim shrinks the
  surge-pod footprint instead; re-rendered + server-diff = ONLY pilot cpu; apply BLOCKED by classifier,
  handed to user (`kubectl apply -f .../istio-ambient-v127.yaml`).
  **✅ ALL THREE LIVE + VERIFIED 2026-08-24:** both appsets reapplied at v1.27.0 (services-git
  `targetRevision` v1.26.0→v1.27.0; istiod appset pilot cpu 50m). basket/frontend/order Synced+Healthy,
  payment rolled (50m), istiod Synced/Healthy (surge pod scheduled), rabbitmq rolled via data-layer.
  Hostinger node `srv1754834` CPU requests **1960m (98%) → 1610m (80%)** = ~350m reclaimed (~40m→~390m
  free); zero Pending pods. Rollout-deadlock class eliminated. hostinger CPU right-sizing CLOSED.

- **Other live/tracked follow-ups:**
  - Replace the interim in-cluster CVE promoter git-writer token with a fine-grained
    contents-write-only PAT.
  - Reconcile stale port-forward/LaunchAgent state on public Grafana/status probe failures
    (`reference_single_service_502_zombie_port_forward` in auto-memory).
  - Re-seed display-only Vault paths wiped in rebuild (Prometheus basic-auth, ArgoCD/Grafana
    mirrors) — display-only, not ESO-managed; `make show-service-passwords` triage in
    `reference_show_service_passwords_na_root_causes`. Hub Prometheus is UNAUTHENTICATED (rotate fn
    targets ACG, not hub).
  - Keep ArgoCD smoke credential-drift + k3s-aws SSM registration issues visible in `docs/issues/`
    until their live follow-ups close. Account-level SSM Default Host Management Role optional.
  - Dependabot alert #6 (js-yaml) remediated as lib-foundation `v0.4.11` (subtree `1bf1d2ce`,
    lockfile `3.15.1`); reads `open` only because Dependabot scans main → auto-closes when
    v1.26.0 → main. Dev-only transitive, low risk.

- **k3d agent watchdog hardening (2026-08-26):** existing bounded `node-health-watch` previously
  skipped exited containers; commit `15c7d072` now uses `docker start` for `created`/`exited`/`paused`
  states and `docker restart` only for running containers. Focused BATS 2/2, ShellCheck, and
  `_agent_audit` passed. Watchdog reinstalled live with the existing 3-failure/300-second cooldown.

## Operating decisions

- **2026-08-26 hub outage:** an exited k3d agent caused node-affine Prometheus/Loki pods to hang and
  Kine/SQLite readiness to fail, producing edge 502s. Agent/server restart plus stale pod cleanup
  restored the workloads; public forwards still require live verification. See
  `docs/issues/2026-08-26-hub-control-plane-and-edge-forward-outage.md`.

- **Edge forward hardening:** `ea91431d` increases wrapper probe timeout/hysteresis (5s/6 failures)
  to avoid restarting ArgoCD/Keycloak on transient control-plane latency. Public ArgoCD/Keycloak
  checks still need re-verification once the k3s API settles.

- `make status` follows the active provider (concise/full/JSON); Slack reuses the same summary contract.
- CVE remediation current-state excludes terminal `superseded`/`deployment_advanced` events; history
  keeps the audit trail. Verifier cadence/bounds stay conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore credentials,
  and an EXIT-trap result artifact written before teardown.
- **2026-08-27 M2 E2E migration:** corrected the remote dispatcher to forward an explicit immutable
  `E2E_IMAGE_TAG` to the M2 runner (`0f16f0de` on `k3d-manager-v1.27.0`). The corrected image build
  (`shopping-cart-e2e-tests` run `33073207387`, source `0c2505bb`) passed; live M2 acceptance remains
  the next verification step. M4 storage is healthy (58% root, 196 GB free; OrbStack 26%, 184 GB free).
  The 2026-08-27 M2 run used the immutable tag but failed 31/102 (26 passed, 45 skipped), with
  basket/order response-shape failures and payment-suite failures; see
  `docs/issues/2026-08-27-m2-e2e-acceptance-after-immutable-image.md`.
- **2026-08-27 Keycloak smoke fallback:** committed `931839ab` on `k3d-manager-v1.27.0` to support
  deployed password-only Keycloak admin Secrets while preserving the existing username/password path.
  Focused Keycloak BATS passed 12/12 and ShellCheck was clean.
- Do not deploy source-only changes until their release-branch/PR gates + live verification are explicit.
- When the laptop Vault reverse bridge is required (`HUB_VAULT_USE_BRIDGE=1`, default), k3s-aws selects
  SSH and overrides explicit SSM with a warning; SSM stays available for non-bridge Vault profiles.

- **2026-08-28 hub last-mile close-out** (`k3d-manager-v1.27.0`): four follow-ups from the CPU-crisis
  resolution actioned.
  - **Governance already durable (verified, no-op):** `argocd_check_values_branch` → all 6 Applications
    track `k3d-manager-v1.27.0` (no drift); live `monitoring` ns confirms Step 2 governance is applied —
    loki-canary=0, prom scrapeInterval/eval=60s, retention=3d, retentionSize=8GB. ApplicationSets were
    already reapplied; nothing inert.
  - **Vault auto-unseal watchdog deployed + fixed:** installed `vault_install_unseal_watchdog` (CronJob
    `vault-unseal-watchdog`, ns `secrets`, `* * * * *`, Forbid). Found + fixed two bugs — (1) stale
    pinned image `1.18.3` vs live `1.20.1`, and vars.sh unconditionally exporting the stale default,
    defeating derivation; now `vault.sh` derives the image from the running Vault StatefulSet and vars.sh
    leaves `VAULT_UNSEAL_IMAGE` empty; (2) per-node k3d image cache + `activeDeadlineSeconds:50` killed a
    cold pull → raised to 150. Validated: manual job SUCCEEDED ~12s, logs `vault already unsealed`. Note:
    a real restart preserves node image caches, so the cold-pull only bites first-deploy. Spec:
    `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`.
  - **Frontend-login false-red fixed:** `bin/k3dm-webhook` skip guard extended from `kc_via_smoke_client`
    to a new `kc_token_is_stub` flag (True on both smoke-client AND admin-cli fallback paths), so an
    expected 401 on `/api/cart` from a stand-in admin token is a SKIP not a hard FAIL. `make status` now
    `WARN (1 warning)` — the lone warning is the honest "no real smoke user seeded" skip; everything else
    green. Real outages still FAIL (guard is 401/403-only). Spec:
    `docs/bugs/2026-08-28-smoke-frontend-login-stub-token-false-fail.md`. Durable follow-up (out of scope):
    seed a real `k3dm-smoke-user` in the shopping-cart realm to make this a true PASS.
  - **loki re-shed declined (data-driven):** offered when server-0 was ~360% cold-start; it has since
    settled to **95–130%** with canary already gone. A manual `loki=0` would be reverted by ArgoCD
    selfHeal (git declares 1) and would remove log aggregation for CPU that is no longer pressured — left
    loki at 1/1. One-command shed remains available if headroom is ever needed.
- **2026-08-28 optional durable follow-ups:**
  - **deploy_vault now auto-installs the unseal watchdog** (`vault.sh`, after `_vault_setup_pki`, guarded
    `|| _warn`) so auto-unseal survives a hub rebuild without a second command — same pattern as
    platform-ops in the ArgoCD bootstrap. Decision folded into
    `docs/bugs/2026-08-28-vault-unseal-watchdog-stale-image.md`.
  - **Real smoke-user seed NOT applicable on the hub — architecture finding.** `keycloak_seed_smoke_user`
    targets a `shopping-cart` realm, but the hub Keycloak (identity ns, reached at
    `keycloak.shopping-cart.local`) has only `home` + `master` realms — no `shopping-cart` realm and no
    frontend/app client (`home` has only default clients). The shopping-cart frontend + its realm live on
    the **app-cluster (ACG)**, not the hub. So seeding a hub user cannot produce a true Frontend-login PASS
    without first provisioning the shopping-cart realm + frontend client on the hub Keycloak (a real setup
    task, not a last-mile seed). The honest SKIP from the `kc_token_is_stub` fix is the correct state. Seed
    aborted at the realm-existence check — created nothing (verified: no `k3dm-smoke-user` secret, no
    `k3dm-smoke` client). Also noted: codebase default realm `shopping-cart` is stale vs live hub `home`.

- **2026-08-29 monitoring-pause Grafana keep-list — LIVE-VERIFIED (8506f5fe, pushed):** pure
  whole-word `_observability_workload_in_keep_list` + default
  `OBSERVABILITY_PAUSE_KEEP=kube-prometheus-stack-grafana` pause-sweep exemption; resume unchanged.
  Five pure BATS cases + Makefile help. Spec `docs/bugs/2026-08-29-pause-keep-grafana-up.md`. Coded by
  Codex, Claude-verified (BATS 5/5, `bash -n` clean, SC2016 pre-existing only). Live hub:
  `make monitoring-pause` keeps grafana 1/1 (loginable, `database:ok`) while everything else → 0/0;
  resume → HEALTHY. By design panels show "No data" while paused (UI reachable, not live data). To
  restore the old all-or-nothing sweep set `OBSERVABILITY_PAUSE_KEEP=""`.

- **2026-08-29 layered `monitoring-resume` — LIVE-VERIFIED (1bdbe3c6, pushed):** `make
  monitoring-resume LAYER=1` brings up **Grafana + Prometheus only** (live dashboards), all else 0;
  `LAYER=2` or no arg = full stack (existing body, verbatim). Added `_observability_normalize_layer`
  (1→1, 2/empty/unknown→2 — forgiving) + `_observability_resume_layer1` (keeps ArgoCD `automated:null`
  so selfHeal can't resurrect the 0-set; explicit replica drive; idempotent from pause/L1/L2), reusing
  the keep-list predicate with `OBSERVABILITY_LAYER1_UP=kube-prometheus-stack-grafana
  prometheus-kube-prometheus-stack-prometheus`. Makefile `$(LAYER)` passthrough + help. 5 pure BATS
  normalize cases. Spec `docs/bugs/2026-08-29-layered-monitoring-resume.md`. Coded by Codex,
  Claude-verified (BATS 10/10, `bash -n` clean, SC2016 pre-existing only, diff==spec, scope==3 files).
  **Live hub:** L2→`LAYER=1` dropped to grafana 1/1 + prometheus 1/1 (rest 0/0), Prometheus `up` query
  returned series + Grafana `database:ok`; `LAYER=2` restored all 7 workloads 1/1, `make status`
  HEALTHY. One manual touch during the L2 ramp: deleted a stale `Unknown` prometheus pod from the known
  CPU-starvation cascade (full stack starting at once) — not a feature defect.

- **2026-08-29 Tier-1 E2E orders.spec ROOT-CAUSED + FIXED (aa2f2190, pushed) — gate rerun
  confirming:** the orders.spec wholesale failure (42 ✘) was NOT a client-contract bug. Ground
  truth (captured Playwright `results.json` from the live pod before teardown + direct
  port-forward replay): the deployed order image `sha-56033880` is the **Go** rewrite (commit
  `5603388`), not Java (earlier Dockerfile read was wrong), and it ships **no runtime migration** —
  the substrate created the `orders` DATABASE but never the `orders`/`order_items` TABLES →
  every order DB op HTTP 500 (`relation "orders" does not exist`, 42P01). Fix: added
  `20-orders-schema.sql` to `scripts/etc/e2e/postgres.yaml` initdb (`\connect orders` + DDL).
  Critical nuance: DDL must match the **deployed** commit `5603388` — its `order_items` has **no
  `total_price`** column; copying repo-HEAD/testdata DDL (which added `total_price NOT NULL`) 500s on
  insert (23502) since that binary never writes it. **Live-validated** against the running substrate:
  `POST /api/orders → 201` with full contract (id, status PENDING, items[].subtotal, totalAmount,
  shippingAddress, currency USD), `GET …?customerId=X` (X-User-ID header) → 200 with the order. List
  filters by `X-User-ID` (MockAuthMiddleware), not the query param — e2e client sends it consistently,
  no change needed. Payments.spec (27) + payment cross-service stay Tier-1-out-of-scope (no payment
  manifest = Tier-2/ACG's job). Spec `docs/bugs/2026-08-29-e2e-order-schema-missing.md`; durable
  service-side self-migrate follow-up `docs/issues/2026-08-29-order-service-no-startup-migration.md`.
  Confirming rerun DONE (`~/.k3dm/e2e/1788051374-25838.json`, commit 86298144): **passed 26→45,
  failed 31→12, skipped 45**. Cross-service fully greened (21→0), orders 42→2. **Residual 12 =
  ZERO substrate bugs**: (a) 9 payments `ECONNREFUSED :8084` — no payment svc in Tier-1
  (Tier-2/ACG's job); (b) 2 order status-update — e2e test sends status `CONFIRMED` which is NOT
  in the deployed `OrderStatus` enum (PENDING/PAID/PROCESSING/SHIPPED/COMPLETED/CANCELLED) + illegal
  transitions (PENDING→only PAID/CANCELLED) → PATCH 400 → status undefined = **e2e-test contract bug**
  (shopping-cart-e2e-tests, spec-not-direct); (c) 1 cart remove-qty-0 — `cart.items` undefined,
  pre-existing basket/e2e mismatch. Substrate fix is COMPLETE for its scope. To green the gate:
  cross-repo — fix the 3 test-contract bugs in the e2e repo (+ rebuild image) and decide payment
  (Tier-1 manifest vs scope-to-non-payment + Tier-2). User chose (2026-08-29): **fix e2e tests,
  payment→Tier-2.**

- **2026-08-29 e2e residual triage — CART RECLASSIFIED as a basket-service bug (specs written,
  Codex handoff pending):** on grounding the 3 residuals, only 2 are e2e-test bugs; the cart one is
  a service bug:
  - **Order status (2, e2e-test bug):** tests send status `CONFIRMED`, absent from the deployed
    `OrderStatus` enum (PENDING/PAID/PROCESSING/SHIPPED/COMPLETED/CANCELLED) + illegal transitions
    (PENDING→only PAID/CANCELLED). Fix = use real enum + legal chain (PENDING→PAID; history
    PENDING→PAID→PROCESSING→SHIPPED). Spec `docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md`
    (repo `shopping-cart-e2e-tests`).
  - **Cart qty-0 (1, BASKET-service bug, NOT a test bug):** basket `UpdateItemRequest.Quantity`
    is `binding:"required,min=0"`; gin treats int 0 as "missing" so `{quantity:0}` → 400 before the
    handler's `quantity<=0` remove path runs. Test is CORRECT. Fix = drop `required` (use `min=0`).
    Issue `docs/issues/2026-08-29-basket-update-quantity-zero-required.md` (repo `shopping-cart-basket`).
  Both are shopping-cart repos → spec+Codex, branch+PR, rebuild image (spec-not-direct). Codex handoff
  + image rebuild + Tier-1 re-verify still to do; PR/merge gated.

## Canonical pointers

### 2026-09-01 — live frontend Keycloak client hotfix
- Created missing public OIDC client `frontend` in hub `shopping-cart` realm (Keycloak admin API returned HTTP 201); verified by an in-pod admin query.
- Configured callback `https://frontend.3ai-talk.org/callback` and web origin `https://frontend.3ai-talk.org`, matching the deployed frontend bundle.
- Public `keycloak.3ai-talk.org` DNS currently fails to resolve from the workstation, so browser verification remains blocked by the edge/tunnel path, not Keycloak client configuration.

- Roadmap: `docs/roadmap.md`
- v1.27.0 plans: `docs/plans/v1.27.0-*`
- Active bugs/incidents: `docs/bugs/` and `docs/issues/`
- Release history: `CHANGELOG.md` and `docs/retro/`

### 2026-09-02 — ArgoCD identity sync recovery and secure credential handling
- ArgoCD password was handled only in process memory via a Kubernetes-secret-to-API
  pipeline; no password file, shell argument, log, or output was created.
- Recreated the stuck `argocd-application-controller-0` pod and cleared its stale
  operation. Identity sync now reaches the immutable `postgres-keycloak-pvc` blocker.
- Added `Replace=true` to the identity Application template in `bin/cluster-up`.
- Follow-up issue: `docs/issues/2026-09-02-secure-argocd-sync-and-pvc-blocker.md`.

### 2026-09-03 — Grafana CVE panels empty
- Prometheus retained 6,066 vulnerability series and 6 remediation events, but the
  vulnerability exporter target was down on scrape timeout because `/metrics`
  synchronously refreshed both clusters.
- Exporter now refreshes in a 60-second daemon loop and serves the cached snapshot
  immediately. Manifest applied; post-rollout scrape confirmation is pending.
- Issue: `docs/issues/2026-09-03-grafana-cve-tables-empty-exporter-timeout.md`.
### 2026-09-01 — status blind spot documented
- Filed `docs/issues/2026-09-01-status-blind-spot-on-exited-hub-agent.md`: when a hub agent exits, webhook-backed `make status` reports only `UNKNOWN` and omits node evidence. Recommended bounded local Docker/node fallback; no automatic restart.
### 2026-09-01 — status fallback and Keycloak credential lookup fixed
- `make show-service-passwords` now reads `identity/keycloak-admin-secret` key `password`; verified it reports admin present without exposing the value.
- `bin/cluster-status-summary` now adds local `k3d-k3d-cluster-agent-0` Docker state to webhook-unavailable output. Syntax and all 8 BATS tests pass.
### 2026-09-01 — Hermes automation roadmap
- Added an unversioned forward theme for optional Hermes event-driven operations automation: read-only monitoring first, then approval-gated repairs, cooldowns/budgets, audit, and verification. k3d-manager webhook remains authoritative.

### 2026-09-03 — keycloak-secrets ES root cause = Vault FIELD SCHISM (not missing data)
- Live `keycloak-0` is DECOUPLED from `keycloak-secrets`/`postgres-keycloak`: it connects to
  `jdbc:postgresql://keycloak-postgresql:5432/bitnami_keycloak` (legacy Bitnami PG, user `bn_keycloak`)
  with a FILE-based password (`KC_DB_PASSWORD_FILE`) from configmap `keycloak-env-vars`. SSO is safe to
  touch these secrets — nothing live reads them.
- The failing ExternalSecrets (`keycloak-secrets`, `keycloak-client-secrets`, `ldap-secrets`) all use
  store `vault-kv-store`; the WORKING ones (`keycloak-admin-secret`, `keycloak-ldap-secret`, `openldap-admin`)
  use `keycloak-vault-store`. Error is `cannot find secret data for key: "admin_password"` at
  `secret/data/keycloak/admin` — the secret is READABLE but the FIELD is misnamed.
- `secret/keycloak/admin` holds only `password` (keycloak.sh convention); the infra ES wants `admin_password`
  + `db_password` (shopping_cart.sh convention). `secret/ldap/admin` does not exist; canonical ldap admin pw
  is `secret/ldap/openldap-admin#LDAP_ADMIN_PASSWORD`.
- FIX (operational seed, NOT a manifest change): patch `secret/keycloak/admin` to ADD
  `admin_password`(=existing `password`) + fresh `db_password`; create `secret/ldap/admin#admin_password`
  (=openldap-admin LDAP_ADMIN_PASSWORD). Auto-mode classifier blocked the read-into-var+write script twice;
  handed the exact command to the user to run via `!`.
- Live identity app syncOptions = ["CreateNamespace=true","Replace=true"] (Codex 0bca3e21 IS live) with
  automated=null (Stage A suspension holds). DO NOT resume auto-sync until Replace=true is scoped to the
  Keycloak Service only (Stage B) — resuming with blanket Replace=true would force-replace Keycloak STS/PVC.
- Sequence once seeded: ES reconciles (15m or forced) → keycloak-secrets syncs → postgres-keycloak leaves
  CreateContainerConfigError → identity app heals to Healthy while auto-sync STAYS suspended (safe hold).
