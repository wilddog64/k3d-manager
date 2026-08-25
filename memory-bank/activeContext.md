# Active Context — k3d-manager

> Compressed 2026-08-24 (CVE panel ② saga closed → collapsed to pointers). Settled fixes
> live as pointers; detail in `memory-bank/archive/`, `CHANGELOG.md`, `docs/retro/`,
> `docs/issues/`, `docs/bugs/`, git history, and auto-memory.

## Current focus

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
     **Still BLOCKED** on (b) hostinger node CPU exhaustion (the last gate for the 2-run acceptance).
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
  4. `v1.27.0-adaptive-checkout-load-testing.md` — API-level checkout load + telemetry. **STARTED
     2026-08-24 (sliced).** E=adaptive controller + stop-condition hysteresis + unit tests →
     **DONE** Codex commit `17be2e69`, pushed to `origin/k3d-manager-v1.27.0`; pure decision logic +
     BATS 9/9, no cluster/Prometheus/k6/Stripe. PR URL: none (task prohibits PR creation);
     F=k6/Go generator + Grafana dashboard + live capacity run [Claude live, Stripe test-mode].
     Verify Codex output on origin per [[feedback_codex_verification_protocol]] before trusting;
     note the `codex exec` sandbox has `.git` read-only, so expect Codex to leave files uncommitted
     and Claude commits after review (as with Slice A).
  - Finding 1a — ✅ FIXED + live-verified `5cd67228` (`num()` coerces empty/None→0 so one malformed
    value can't zero the scrape; `up{exporter}=1`, both E2E + CVE dashboards receiving data).
    `docs/issues/2026-08-21-e2e-exporter-empty-duration-metric.md`.
  - Finding 2b — dispatcher `--confirm` strip on `deploy_app_cluster` (OPEN).
    `docs/issues/2026-08-21-dispatcher-strips-confirm-deploy-app-cluster.md`.

- **v1.26.0 RELEASED** — PR #117 `1bbe5439` merged, tag/release published, protection restored
  (`enforce_admins=true`, 1 approval). Shipped 3/5 scopes (fleet count-agnostic lifecycle, E2E
  promotion gate + observability, managed registration cleanup). Retro
  `docs/retro/2026-08-21-v1.26.0-retrospective.md`. v1.25.0 = PR #116 `d48e465f`.
- v1.28.0 planned: parallel multi-cloud provisioning + zero-downtime rollouts.

## Open follow-ups

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

## Operating decisions

- `make status` follows the active provider (concise/full/JSON); Slack reuses the same summary contract.
- CVE remediation current-state excludes terminal `superseded`/`deployment_advanced` events; history
  keeps the audit trail. Verifier cadence/bounds stay conservative under hub load.
- E2E runs use a throwaway vCluster, pinned service images, runtime-generated datastore credentials,
  and an EXIT-trap result artifact written before teardown.
- Do not deploy source-only changes until their release-branch/PR gates + live verification are explicit.
- When the laptop Vault reverse bridge is required (`HUB_VAULT_USE_BRIDGE=1`, default), k3s-aws selects
  SSH and overrides explicit SSM with a warning; SSM stays available for non-bridge Vault profiles.

## Canonical pointers

- Roadmap: `docs/roadmap.md`
- v1.27.0 plans: `docs/plans/v1.27.0-*`
- Active bugs/incidents: `docs/bugs/` and `docs/issues/`
- Release history: `CHANGELOG.md` and `docs/retro/`
