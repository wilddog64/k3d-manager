# Progress — k3d-manager

> **Compressed 2026-08-09.** Shipped-release detail lives in `CHANGELOG.md` + `docs/retro/`; the
> integration-split carry-forward in `docs/plans/release-split-intent-map.md`; per-incident detail in
> `docs/issues/` / `docs/bugs/`. Pre-compression history is in git (`git log --follow memory-bank/`).

## Releases

### v1.24.0 completed commits (2026-08-10)

| Work item | Commit | Status |
|---|---|---|
| Prometheus weak basic-auth default removal | `e1256d0a` | pushed; weak-hash grep empty, shellcheck clean, 13 observability BATS pass |
| Monthly ArgoCD + host-side Prometheus rotators | `3db193cb` | pushed; 16 ArgoCD BATS, 14 observability BATS, shellcheck, YAML/plist parsing, and `_agent_audit` pass |

Live deployment and rotation verification are intentionally deferred to release operations.

**E LIVE HALF DONE 2026-08-11 (`84232cc0`):** rotator deployed + Vault `argocd-rotation` role created via
`deploy_argocd_platform_ops`; one-shot Job verified live (mtime advanced, clean bcrypt, new password →
ArgoCD LOGIN SUCCESS); Prometheus host-side launchd agent installed + rotate regenerates a strong cred.
Live verify caught **4 rotator bugs** in Codex's static commit (`docs/bugs/v1.24.0-bugfix-argocd-rotator-bcrypt-and-istio-sidecar.md`):
bcrypt no-newline `fatal EOF`; `Password:` stdout prompt in captured hash; istio sidecar deadlock in `cicd`;
Prometheus launchd `bin/k3d-manager` (nonexistent) → `scripts/k3d-manager`. argocd.bats 17/17, observability.bats 14/14, shellcheck clean.
⚠️ Full deploy also brought #18 promoter code live (GIT_WRITE_TOKEN `optional:true` → safe fallback); **#18 dry-run + PAT seed DONE 2026-08-11 (Claude)** — see below.

| Work item | Commit | Status |
|---|---|---|
| Webhook auth fail-closed + Slack allowlist enforcement | `3fddcf3e` | pushed to `origin/k3d-manager-v1.24.0`; py_compile and 52 BATS tests pass |
| Hostinger status report head/tail truncation | `8eb8cc34` | pushed to `origin/k3d-manager-v1.24.0`; py_compile and 53 BATS tests pass |
| Istio ambient/Hostinger drift reconciliation | `357edf52` | pushed; shellcheck and YAML parsing pass |
| Git-persisted CVE remediation promoter | `3df62fbf` | pushed; shellcheck, POSIX shebang, YAML parsing, and `_agent_audit` pass |

**#18 promoter git-persist DRY-RUN VERIFIED 2026-08-11 (Claude):** Keychain `platform-ops-git-writer`/`k3dm`
seeded (interim `gh auth token`, `repo` scope — local dry-run only; replace with fine-grained
`contents:write`-only PAT before in-cluster use), synced to `platform-ops` Secret key `git-token`.
Exercised the exact git-persist path non-destructively — clone via `x-access-token:` URL (exit 0), real
`set_image_digest.awk` on `services/shopping-cart-order/kustomization.yaml`, promoter-author local commit,
`git push --dry-run origin HEAD:k3d-manager-v1.24.0` → `503b5dd..7e4474e` exit 0 (WRITE authenticates).
Remote untouched. Last open #18 item closed → **v1.24.0 fully code-complete + live-verified.**

| Version | Theme | State |
|---|---|---|
| v1.23.0 | CVE observability + remediation lifecycle (B+C) | RELEASED — PR #112 `7253ece4`, tagged v1.23.0; platform-ops deployed live (alert-noise split active), webhook restarted, `enforce_admins` restored |
| v1.22.0 | OpenLDAP bitnami→Symas migration | RELEASED — PR #111 `1bbb74b0`, tagged |
| v1.21.0 | k3dm-webhook security hardening | RELEASED — PR #110 `f68bdee1`, tagged |
| v1.20.0 | CVE auto-patch-loop hardening | RELEASED — PR #109 `9da73458`, tagged |
| v1.18.0 | first-mile CVE gap closure | RELEASED — PR #108 `85742ef7`, tagged |
| v1.17.0 | real login verification in health smoke | RELEASED — PR #107 `b5d401b6`, tagged |

(v1.19.0 was a shopping-cart-only Dependabot milestone — no k3d-manager tag.)

## Shipped — v1.23.0 (RELEASED 2026-08-09)

PR #112 merged (`7253ece4`), tagged v1.23.0. Post-merge close-out done: `deploy_argocd_platform_ops`
applied live (TrivyCritical ownership split + `k3dm-quiet` blackhole route confirmed live on the hub),
`make restart-webhook` loaded the Slack-title fix, `argocd_check_values_branch` = all 6 apps on
`k3d-manager-v1.23.0`, `enforce_admins` restored, retro at
`docs/retro/2026-08-09-v1.23.0-retrospective.md`. Full change list = `CHANGELOG.md` [1.23.0].
Shipped work (SHA pointers):

- Verifier: multi-arch spec-digest fix `33b45a41`; payment-namespace `_namespace_for` `8a8566e8`;
  event GC `9168edd7`; carry-forward + alpine/k8s re-pin + argocd.sh wiring `33b151ba`.
- Alerting: `CVERemediationInFlight` inhibit + analyze `repeatInterval:12h` `ed52cf0c`;
  `image_repository` `label_replace` normalization `72be9383`; empty-repo TrivyCritical guard `5302ea54`.
- Dashboard/exporter: shipped as **Codex 1:1** 4-table view `06a0416e` (churn `db81f534`→`1d9251b4`→
  `43ece528`→`06a0416e`); exporter + dashboard wired into `deploy_argocd_platform_ops`.
- Grafana rotation (E slice pulled forward): Vault source + monthly rotator `5b418dd7`;
  show-service-passwords `31db9732`; four latent blockers fixed — runAsUser `a66463e1`, openssl-free
  `4557cdeb`, rollout-status RBAC `a0bb46c2`, DB-apply + hub-scope smoke `816835fd`. Runs end-to-end.
- Adjacent: LDAP rotator alpine/k8s re-pin `ddc68c90`; webhook rate-limit-after-auth + Content-Length
  `ee32837d`; agy model-id retirement `8e7a5c79` (webhook) + `612ca86d` (gemini.sh/antigravity.bats).

**Post-merge (Claude) — DONE 2026-08-09:** platform-ops deployed live; dashboard appsets confirmed on
v1.23.0; tagged `v1.23.0` + GitHub release; `enforce_admins` restored; retro written; webhook restarted;
`k3d-manager-v1.24.0` cut from `7253ece4`. Remaining v1.24.0 follow-up: headless `_call_gemini` analyze
still errors ("no output produced — command permission auto-denied") for the surviving ours-alert.

## Deferred — NOT v1.23.0-gating

- [x] **Order remediation promoter — SHIPPED (task #18): Option B, `3df62fbf` 2026-08-10, Claude-verified.**
      Git-persistence slice committed + pushed on `k3d-manager-v1.24.0` (3 files, zero kustomization edits;
      awk-pins `digest:` on the frozen `_app_target_branch`; live-patch fallback when `GIT_WRITE_TOKEN` unset).
      order's own CI `sha-<gitsha>` tagging (root cause A) deferred to v1.25.0 as a cross-repo carry-in.
      Claude-owned follow-up: live dry-run/auto-sync verify + seed `platform-ops-git-writer` PAT.
- [ ] Dashboard parts (b)+(c) — spec `v1.23.0-cve-dashboard-parts-bc-cveid-and-remediation-target.md`
      superseded by the Codex 1:1 revert; re-scope before executing.
- [ ] `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md` +
      `observability.sh` per-hunk split from E → v1.24.0.

## Pending releases (integration-split — full file map + blockers in the intent map)

- [ ] **v1.24.0** — platform hardening (D+E+F), scope CONFIRMED 2026-08-09 (broad reconcile). Detail +
      confirmed carry-ins in `activeContext.md`. Doc set (≤5 plan-doc cap): 4 plan docs —
      `v1.24.0-webhook-auth-reconcile` (D — REVISED 2026-08-10: auth.py fail-closed + allowlist helper
      + wire enforcement into bin/k3dm-webhook (hand-applied, no archive revert) + 3 bats; hostinger
      truncation split to `docs/bugs/v1.24.0-bugfix-hostinger-status-report-truncation.md`),
      `v1.24.0-istio-hostinger-drift-reconcile` (F istio ServerSideDiff/ignoreDifferences + hostinger
      AMBIENT_CNI paths), `v1.24.0-credential-rotation-automation` (E: ArgoCD/Prometheus/Alertmanager
      recurring rotation + observability.sh carry), `v1.24.0-order-remediation-promoter` (task #18); + 2
      `docs/bugs/` (cap-exempt): agy `_call_gemini` headless permission fix, existing app-cve-scan bug.
      ⚠️ SKIP the v1.23.0 Grafana slice. Verified: D/F archive deltas are real live-drift gaps, not forks
      (`bin/k3dm-webhook:52` imports the live `auth.py`; istio/hostinger fixes applied live, committed
      only to archive).
      **STATUS 2026-08-10:** D `3fddcf3e` + hostinger-truncation `8eb8cc34` + F `357edf52` + #18 `3df62fbf`
      all pushed + Claude-verified (archive-revert guard intact, `bats`=`1..53` 0 fail). **E rotation
      automation is the only remaining code slice — NOW ACTIVE** (`v1.24.0-credential-rotation-automation`).
      **E REWRITTEN 2026-08-10 after live discovery: ArgoCD in-cluster rotator + Prometheus host-side rotation;
      Alertmanager DROPPED (host-side proxy cred); observability.sh carry VACUOUS (dropped).** New cap-exempt
      bugfix filed `docs/bugs/v1.24.0-bugfix-prometheus-weak-basic-auth-default.md` (weak admin/password
      confirmed live) — do the bugfix FIRST, then the rotators. Then agy headless bug doc + two live
      verifications + PAT seed.
      **agy headless bugfix spec FINALIZED 2026-08-10 (handoff-ready):** `agy --help` confirms no
      tool-disable flag → prompt-guard fallback authoritative; `docs/bugs/v1.24.0-bugfix-webhook-gemini-headless-permission.md`
      now has 2 exact `_call_gemini` old/new blocks (suppression guard + legible auto-deny message).
      Remaining v1.24.0: hand off/implement the agy fix, then Claude-owned live verifications (E deploy +
      rotate/restore, promoter dry-run) + `platform-ops-git-writer` PAT seed, then the release path.
      **agy fix IMPLEMENTED + verified live 2026-08-11 (`69e21e15`)** — prompt-guard + legible auto-deny;
      py_compile OK, webhook.bats 53/53, live smoke returns real analysis (no tool call), webhook restarted.
      **v1.24.0 is now CODE-COMPLETE.** Also `33e42905`: `make show-service-passwords` ArgoCD block now reads
      Vault `secret/argocd/admin` (was stale `argocd-initial-admin-secret`) — shown password verified to log in.
      **Remaining before release path: #18 promoter live dry-run/auto-sync verify + seed `platform-ops-git-writer` PAT**
      (its code is already live from the E full deploy, GIT_WRITE_TOKEN optional/safe). Then CHANGELOG/README/PR gate.
- [ ] **v1.25.0** — Stripe/Go live acceptance + hostinger capacity (G, BLOCKED, cross-repo). Merge
      order-repo `0e3feb9` schema fix + promote image → rerun Stripe live E2E (2/4 now); hostinger
      capacity expansion. **Live deadlock found + stopgapped 2026-08-10:** order/basket wedged
      mid-rollout (maxSurge=1 needs 2× CPU on a 95%-full 2-CPU node → FailedScheduling 11h/26h);
      live-patched both to `maxSurge=0/maxUnavailable=1`, converged. Durable fix (this workstream):
      commit `maxSurge=0` into app git manifests (ArgoCD may revert the live patch) OR bump node CPU.
      Issue: `docs/issues/2026-08-10-hostinger-rollout-deadlock-maxsurge-on-2cpu-node.md`. **+ E2E verification harness (SCOPED 2026-08-10, plan doc #1):**
      `docs/plans/v1.25.0-e2e-verification-harness.md`. Enable the disabled e2e suite on ephemeral
      substrates — **Tier 1 vCluster** (per-candidate, blocking, `OAUTH2_ENABLED=false`, deploys candidate
      digest, always teardown) + **Tier 2 ACG sandbox** (periodic full-stack, real ingress/OIDC,
      `OAUTH2_ENABLED=true`, runs Stripe live E2E to unblock G). e2e is substrate-agnostic (needs only
      basket/catalog/order URLs + oauth flag). `workflow_call` added to `shopping-cart-e2e-tests`; new
      `scripts/plugins/e2e.sh` (`e2e_verify_vcluster`/`e2e_verify_sandbox`) reusing `vcluster_*` prims.
      Exit-code + JSON-summary contract seeds the v1.26.0 promotion gate ([[project_image_signing_cve_loop]]).
      **+ plan doc #2 `v1.25.0-e2e-observability-path-a.md` (implementation-grade):** surface e2e in
      Grafana by reusing the CVE exporter seam — harness writes `k3dm.k3d.io/e2e-result=true` ConfigMap
      (the JSON summary); extend `vulnerability-inventory-exporter.py` (exact blocks) to emit
      `e2e_run_info`/`e2e_last_run_pass`/`e2e_last_run_timestamp_seconds`/`e2e_last_run_duration_seconds`/
      `e2e_last_success_timestamp_seconds` (gauges, aggregated in Python); new `grafana-dashboard-e2e.yaml`;
      `E2EVerificationFailing`/`Stale` rules; deploy via `argocd.sh` + rollout-restart; NO RBAC widening
      (existing Role already get/list configmaps in platform-ops); writer prunes N=20/service+tier. No new
      component; no Tempo (span tracing = separate forward theme).
- [ ] **v1.26.0** — image signing + attestation, closing the CVE loop (SCOPED 2026-08-10, not started).
      Spec `docs/plans/v1.26.0-image-signing-cve-loop-closure.md`. cosign sign + Trivy vuln/SBOM attest
      at build; `cosign verify` at promotion (promoter gate) AND admission (Kyverno, staged Audit→Enforce,
      app namespaces only). Key-based, private key in Vault + Keychain backup, pub via ESO (LOCKED, not
      keyless). Multi-repo: k3d-manager `signing.sh`/Kyverno/ClusterPolicy/promoter gate + shopping-cart
      `{order,payment,basket,frontend,product-catalog}` CI. Slots after v1.25.0. Auto-memory
      `project_image_signing_cve_loop`.

## Backlog (not release-gated)

- [x] **Jenkins DEPRECATED in docs (DONE 2026-08-10) — code KEPT** — decision revised: keep the Jenkins
      plugin code (retained but unsupported), mark the service **deprecated** in the current-state docs
      rather than removing it. Verified unused (no live namespace/pods; `deploy_jenkins` never auto-invoked;
      not in `docs/roadmap.md`; real CI/CD = GitHub Actions + ArgoCD). **No code-retirement task** — the
      earlier #2 removal item is cancelled. Auto-memory `project_jenkins_deprecation`.
- [ ] **Secure Vault remote access (QUEUED — after Codex's v1.24.0 assignment)** — expose Vault UI via
      laptop cloudflared `vault.3ai-talk.org` behind Cloudflare Access + MFA (Google IdP / Authenticator
      TOTP); Access-app-before-ingress ordering; Vault audit device on; root token laptop-only. Filing:
      `docs/howto/secure-vault-remote-access-cloudflare-access.md` (decision pending). Auto-memory
      `project_secure_vault_remote_access`. No changes made yet.
- [ ] Shopping-cart Dependabot backlog (Go builder-image bumps, majors held) — auto-memory
      `project_backlog.md`.
- [ ] rabbitmq-client-java NPE fix `36ed860` — JAR publish + pom update pending.
