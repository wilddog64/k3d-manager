# Progress — k3d-manager

> **Compressed 2026-08-07.** Shipped-release detail lives in `CHANGELOG.md` + `docs/retro/`;
> the integration-split carry-forward lives in `docs/plans/release-split-intent-map.md`;
> per-incident detail in `docs/issues/` / `docs/bugs/`. Pre-compression history is in git
> (`git log --follow memory-bank/progress.md`).

## Releases

| Version | Theme | State |
|---|---|---|
| v1.22.0 | OpenLDAP bitnami→Symas migration | RELEASED — PR #111 merged `1bbb74b0`, tagged v1.22.0 |
| v1.21.0 | k3dm-webhook security hardening | RELEASED — PR #110 `f68bdee1`, tagged |
| v1.20.0 | CVE auto-patch-loop hardening | RELEASED — PR #109 `9da73458`, tagged |
| v1.18.0 | first-mile CVE gap closure | RELEASED — PR #108 `85742ef7`, tagged |
| v1.17.0 | real login verification in health smoke | RELEASED — PR #107 `b5d401b6`, tagged |
| v1.16.0 | Istio ambient mesh | RELEASED — PR #106 `4c5d3556`, tagged |

(v1.19.0 was a shopping-cart-only Dependabot milestone — no k3d-manager tag.)

## In flight

- [ ] **v1.23.0 — CVE observability + remediation lifecycle (B+C).** Branch re-cut fresh off main
      (`1bbb74b0`); old 50-commit diverged branch archived `archive/k3d-manager-v1.23.0-integration`
      (`48148c0d`); still needs `--force-with-lease` (user-run) to replace the remote branch.
      Spec: `docs/plans/v1.23.0-cve-autopatch-dashboard-observability.md`. Blockers: dashboard v18
      live-apply (Hub tunnel `127.0.0.1:57780`); payment `manual_review` digest-mismatch closeout;
      carries `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`;
      `observability.sh` per-hunk split from E. See `activeContext.md`.
      Part (a) spec handed to Codex: `docs/plans/v1.23.0-cve-dashboard-part-a-image-attribution.md`
- [ ] **CVE Slack-noise inhibit + repeat-interval (folded into v1.23.0).** Code `ed52cf0c`,
      docs+CHANGELOG `388eaeb6`. `CVERemediationInFlight` alert + `inhibitRules` suppress
      TrivyCritical by `image_repository` during active auto-patch; analyze route capped at
      `repeatInterval: 12h`. Corrected `72be9383`: `label_replace` strips `ghcr.io/` so
      `image_repository` matches Trivy (live check found intersection was empty). Spec
      `docs/bugs/v1.23.0-bugfix-cve-alert-inhibit-and-repeat-interval.md`. **LIVE-VERIFIED
      2026-08-09** on hub: CVERemediationInFlight fired for `wilddog64/shopping-cart-payment`,
      Alertmanager suppressed the payment TrivyCritical (inhibitedBy), lifted on completion. Also
      re-verified `33b45a41` live — both matching-digest payment events flipped `failed → applied`.
      Rides the v1.23.0 release PR (no separate PR).
      (panel id 5 image/resource regroup; source-only). Parts (b)/(c) = later handoff.
- [x] **v1.23.0 Part (a) dashboard image attribution — COMPLETE 2026-08-07.** `db81f534` changes
      only panel id 5 to group by `namespace, image_repository, resource_name`, with the specified
      legend and title. Both YAML and embedded JSON parse checks passed; pushed to
      `origin/k3d-manager-v1.23.0`. Live dashboard reapply remains Claude-owned.
- [ ] **v1.23.0 Parts (b)+(c) — spec handed to Codex 2026-08-07.**
      `docs/plans/v1.23.0-cve-dashboard-parts-bc-cveid-and-remediation-target.md` (spec commit
      `5aa7f771`): (b) trivy `metricsVulnIdEnabled: true` (hub+acg) + CVE-ID panel id 8; (c) KSM
      `metricLabelsAllowlist` jobs=[target-namespace,target-image] (hub+acg) + `bin/k3dm-webhook`
      `_create_cve_scan_job` labels the job + bats assertion + remediation-by-target panel id 9.
      6 files, source-only. Panels 8/9 are LIVE-VERIFY (label names confirmed post-apply). Change 7
      is 7b-only (mock already logs argv + falls through exit 0 — no `label job` arm). Live cutover
      (reapply trivy/kube-prometheus values hub+acg, `make restart-webhook`, LIVE-VERIFY) Claude-owned.

- [x] **LDAP rotator image re-pin — COMPLETE 2026-08-07.** Fix commit `ddc68c90` changes only
      `scripts/etc/ldap/vars.sh`, replacing removed `docker.io/bitnami/kubectl:latest` with
      `docker.io/alpine/k8s:1.31.4`. Grep counts are 0/1, shellcheck is clean, and the fix is
      pushed to `origin/k3d-manager-v1.23.0`. The live `cve-remediation-verify` carry-forward
      gap remains out of scope.
- [x] **CVE remediation verifier carry-forward — COMPLETE 2026-08-08.** Fix commit `33b151ba`
      restores the verifier CronJob and script, re-pins the verifier image to
      `docker.io/alpine/k8s:1.31.4`, and wires its ConfigMap in `argocd.sh`. YAML, shellcheck,
      grep, BATS, and `_agent_audit` gates passed; pushed to `origin/k3d-manager-v1.23.0`.
- [x] **Observability values-branch drift + 7 `manual_review` — RESOLVED LIVE 2026-08-08.**
      Reapplied `observability.yaml`+`observability-acg.yaml` in ns `cicd` at v1.23.0 (all 6 apps
      confirmed via `argocd_check_values_branch`). Hard-refreshed the 3
      `ubuntu-hostinger-shopping-cart-{order,payment,product-catalog}` Apps; all 3 live Deployments
      now have `minReadySeconds: 10` (it was already in the shopping-cart repos since 2026-08-05 —
      ArgoCD was serving a cached remote base under the v1.22.0 freeze). Corrected diagnosis in
      `docs/bugs/v1.23.0-bugfix-cve-remediation-verify-carry-forward.md` Part 2.
- [ ] **Webhook rate-limit ordering + Content-Length guard — SPECCED, Codex handoff 2026-08-08.**
      `docs/bugs/v1.23.0-bugfix-webhook-ratelimit-order-and-content-length.md`. From a security
      report: move `_rate_limited` after auth (do_POST both paths + do_GET); add `_content_length`
      guard (400 on malformed) at the two POST sites; new test
      `scripts/tests/bin/webhook_request_hardening.py`. Commit `fix(webhook): rate-limit after auth
      + guard malformed Content-Length`. SHA pending.
- [x] **Webhook rate-limit ordering + Content-Length guard — COMPLETE 2026-08-08.** Fix commit
      `ee32837d` moves rate limiting after auth/signature checks, adds guarded Content-Length
      parsing, and adds the six-test regression script. `py_compile`, regression tests, smoke,
      and `_agent_audit` passed; `make restart-webhook` ran and the live health endpoint returned
      HTTP 200. The smoke output retained the pre-existing Grafana HTTP 401 warning. Pushed to
      `origin/k3d-manager-v1.23.0`.
- [x] **Grafana rotation DB apply + hub-scope smoke — code COMPLETE + verified 2026-08-08.** Task A
      commit `816835fd` adds namespace-scoped pod/exec RBAC, applies the rotated password through
      `grafana cli ... --password-from-stdin`, and reads the hub Grafana credential in the webhook
      smoke. Verified on origin; gates passed. **Fix 2 (hub-scope smoke) LIVE-VERIFIED GREEN**
      (`make status` → `✅ Grafana login: HTTP 200`). **Fix 1 (DB-apply) is code-correct but INERT** —
      the rotator pod can never start (pre-existing `runAsNonRoot: true` + root `alpine/k8s` image, no
      `runAsUser`; `CreateContainerConfigError`, present since `5b418dd7`). Fix validated live
      (`runAsUser: 65534` → pod starts, exec+reset rc 0, login 200). Follow-up bug filed+queued below.
- [x] **Trivy empty `image_repository` alert — COMPLETE + LIVE-VERIFIED 2026-08-08.** Task B commit
      `5302ea54` filters empty repositories in the PrometheusRule and both exporter loops. Verified on
      origin; gates passed. **Live cutover done:** reapplied `cicd/argocd-degraded` rule (Prometheus
      reloaded `image_repository!=""`) + exporter ConfigMap + exporter restart → 46 active TrivyCritical
      alerts / **0 empty-app**; exporter emits 4870 series / **0 empty-repo**. `observability.sh`
      unchanged. (task #14 code+cutover complete)
- [x] **Grafana rotator can't start (runAsNonRoot) — FIXED + committed `a66463e1` (2026-08-08).**
      Spec `docs/bugs/v1.23.0-bugfix-grafana-rotator-runasnonroot-cannot-start.md`. Added
      `runAsUser: 65534` + `runAsGroup: 65534` (kept `runAsNonRoot: true`). Claude applied directly,
      pushed+verified on origin. Live-applied the rotator; manual `rotate-verify` job now **starts as
      uid 65534** — `CreateContainerConfigError` gone. This blocker is resolved.
- [x] **Grafana rotator `openssl: not found` — 3rd blocker, FIXED + committed `4557cdeb`.** Spec
      `7e857fbb`. `alpine/k8s:1.31.4` has no `openssl`; line 109 now uses `/dev/urandom`+`od` (48 hex,
      live-verified). Only the Grafana rotator used openssl.
- [x] **Grafana rotator `rollout status` RBAC — 4th blocker, FIXED + committed `a0bb46c2`.** Spec
      `52493b04` (`docs/bugs/v1.23.0-bugfix-grafana-rotator-rollout-status-rbac.md`). `rollout status`
      needs `deployments` list+watch (ListWatch informer); `resourceNames` is ignored for collection
      verbs, so added a separate verbs-only `list`/`watch` rule (name-scoped get/patch retained).
- [x] **✅ Grafana rotator END-TO-END LIVE-VERIFIED — runs for the first time ever (2026-08-08).**
      Manual `rotate-verify` Job `Complete` (21s, clean logs); password rotated (fingerprint changed);
      login with the new secret → 200 in-pod + external + `make status ✅ Grafana login: HTTP 200`.
      All four latent blockers (runAsNonRoot `a66463e1` → openssl `4557cdeb` → rollout-status RBAC
      `a0bb46c2`, plus Codex DB-apply `816835fd`) resolved. Grafana Fix 1 no longer inert; monthly
      rotation self-heals. Live rotator on hub matches git `a0bb46c2`.

## Pending (integration-split releases — full file map + blockers in the intent map)

- [ ] **TrivyCritical empty-app alert (task #14) — bug filed + QUEUED for Codex.** Spec
      `docs/bugs/v1.23.0-bugfix-trivy-critical-empty-image-repository-alert.md`. Empty `app` == empty
      `image_repository` (rule sets `app: {{ $labels.image_repository }}`); exporter emits it from
      `report.artifact.repository`, empty for transient ephemeral-job VulnerabilityReports. Fix: alert
      selector `image_repository!=""` + exporter skips empty-repo reports (hub+app loops). Commit
      `fix(observability): stop TrivyCritical alert firing on empty image_repository`. SEPARATE from
      Grafana. Live reapply Claude-owned post-commit. SHA pending.
- [ ] **Grafana rotation DB-apply + hub-scope smoke (task #11) — bundled spec READY, handed to Codex.**
      Spec `docs/bugs/v1.23.0-bugfix-grafana-rotation-db-not-applied.md` rewritten with live-verified
      exact blocks (user chose both fixes bundled). Fix 1: `pods`/`pods/exec` Role rules + `grafana cli
      admin reset-admin-password --password-from-stdin` after ESO sync in `grafana-credential-rotator.yaml`
      (Grafana 11.4.0, deployment-form exec exit 0 + login 200 verified live). Fix 2: `bin/k3dm-webhook`
      smoke reads `grafana-admin-credentials` on hub context (was reading hostinger `acg-…` → false-red 401).
      Dropped `observability.sh` (grafana async via ArgoCD, no sync hook; fresh deploy provisions from
      secret). Commit `fix(observability): apply rotated Grafana admin password to DB + hub-scope status
      smoke`. Gates yamllint+py_compile+`make restart-webhook`; manual-rotation LIVE-VERIFY is Claude-owned. SHA pending.
- [ ] **CVE remediation verifier dead (ImagePullBackOff) + carry-forward gap — HOTFIXED live, durable spec QUEUED for Codex.**
      Spec `docs/bugs/v1.23.0-bugfix-cve-remediation-verify-carry-forward.md`. Root cause: the
      `cve-remediation-verify` CronJob (the every-5-min loop driving ALL remediation state
      transitions) was in `ImagePullBackOff` for 2+ days — image `docker.io/bitnami/kubectl:latest`
      removed by Bitnami (same as task #12). Compounded by carry-forward gap: verifier is
      archive-only (branch `app-cve-scan-cronjob.yaml` lost its 96-line verify CronJob doc,
      `cve-remediation-verify.sh` absent, `argocd.sh` unwired). **LIVE HOTFIX 2026-08-07 (Claude):**
      patched running CronJob image → `docker.io/alpine/k8s:1.31.4`, deleted the wedged 2d job, kicked
      a manual run → 41 `promotion_requested` drained: **19 auto-advanced to `applied`** (2→21), 24 →
      `failed` (running hostinger pod digest ≠ target — real gap, correctly reported, NOT auto-forced),
      7 → `manual_review` (`min_ready_seconds_not_configured`). Hotfix is NOT durable — next
      `deploy_argocd_platform_ops` wipes it; durable spec (re-pin + carry `app-cve-scan-cronjob.yaml`
      verify doc + `cve-remediation-verify.sh` + wire `argocd.sh` ConfigMap) queued for Codex.
      Part 2 (separate, shopping-cart repo): set `minReadySeconds` on order/payment/product-catalog
      Deployments to auto-close the `manual_review` gate. Answers the user's "how to address the state
      automatically" — the verifier auto-stamps `applied` once the promoted digest is confirmed running.
- [x] **CVE verifier payment-namespace mismatch — FIXED + committed `8a8566e8` (2026-08-08).** Added
      `_namespace_for` (payment→`shopping-cart-payment`, others→`shopping-cart-apps`); replaced the four
      hardcoded `-n shopping-cart-apps` lookups with `-n "$app_ns"`. shellcheck+`sh -n` clean. **Live
      ConfigMap `cve-remediation-verify-script` updated** from the fixed script (same form as
      `argocd.sh:1454`); the every-5-min CronJob reads it fresh. Full payment→`applied` verification is
      gated on payment going Healthy (see maxSurge PR below).
- [x] **Payment single-node rollout wedge — Option A fix, PR #59 OPEN (shopping-cart-payment).** Branch
      `fix/payment-rollout-maxsurge-single-node` commit `d4b8f038`; PR
      https://github.com/wilddog64/shopping-cart-payment/pull/59 (Copilot tagged, CI running). Root:
      payment app sources **k3d-manager repo** `services/shopping-cart-payment` (kustomize) whose base is
      pulled from `shopping-cart-payment//k8s/base?ref=main` — so the fix lands in that repo's
      `k8s/base/deployment.yaml` on main. History flip-flop: #24 set `maxSurge:0/maxUnavailable:1`, #49
      reverted to `1/0` (zero-downtime). On the 2-CPU node (1810m/2000m reserved, ~190m free; actual
      usage only 341m/17%) the `1/0` surge pod needs 200m → peak 2010m>2000m → wedges Pending 31h →
      Degraded. **User chose Option A** (`0/1`): replace-in-place, peak stays 1810m, ~seconds downtime
      per rollout. NOT merged — awaiting user go (payment app selfHeal pulls ref=main, so merge = live).
      After merge: payment Healthy → verifier (namespace fix live) reaches `applied` (digest
      `sha256:87c1b58c` already running). Note: values ref freeze — payment app targetRevision still
      `k3d-manager-v1.22.0`, but the payment base pin is `ref=main` so it's unaffected by that freeze.
- [i] **Dashboard-state triage record (2026-08-08)** — spec
      `docs/bugs/v1.23.0-bugfix-cve-remediation-verify-payment-namespace.md`.
      The remediation table is a LEDGER of immutable per-attempt ConfigMaps (verifier only
      acts on `state=promotion_requested`, writes terminal state once). `manual_review
      /min_ready_seconds_not_configured` rows are OLD (pre-`minReadySeconds`) history — order now has
      `minReadySeconds=10`, product-catalog recent events `applied`. Root causes of the recurring
      `failed`: (a) **order `ready_pod_digest_mismatch`** — running `sha256:77fbb912` (tag
      `sha-56033880`) ≠ remediation target `sha256:a8813e75`; image tug-of-war (CI/Image-Updater vs
      remediation promotion); (b) **payment `argocd_not_synced_or_healthy`** — app `Synced|Degraded`
      because a surge pod is stuck `Pending 31h` (`FailedScheduling: Insufficient cpu`; hostinger node
      at 90% CPU requests). Payment's remediation digest `sha256:87c1b58c` IS already the running image,
      so payment flips to `applied` once Healthy. **Verifier bug:** `cve-remediation-verify.sh`
      hardcodes `-n shopping-cart-apps`, but `payment-service` runs in `shopping-cart-payment` → after
      the Degraded fix it would still mis-verify. Fix = `_namespace_for` map. Commit
      `fix(cve): verify payment remediation in its shopping-cart-payment namespace` (DONE `8a8566e8`).
      Follow-ons: **payment `maxSurge:0` DONE — PR #59 MERGED `32c06f7b` 2026-08-08.** Post-merge:
      forced ArgoCD **hard refresh** (remote kustomize base `…?ref=main` is cached — a plain sync
      won't re-pull it) → strategy live `0/1` → rollout replaced in-place → the 33h-stuck Pending pod
      scheduled into freed CPU → payment app **Synced|Healthy**. Verifier can now reach `applied` for
      payment (Healthy + namespace fix + minReadySeconds=10 + digest already matches).
- [ ] **Order remediation `ready_pod_digest_mismatch` — deep root cause, Part 3 PENDING (needs decision).**
      Promoter (`app-cve-scan.sh:289`) deploys the patched image by patching the **live ArgoCD
      Application** `spec.source.kustomize.images` (NOT git) → inherently ephemeral (any ApplicationSet
      reconcile/reapply wipes it). product-catalog currently HAS the override
      (`…@sha256:340371a9`, running matches → `applied`); **order's override is EMPTY** → runs base image
      `sha256:77fbb912` (tag `sha-56033880`) ≠ event `to_digest sha256:a8813e75`. Order's promotion event
      has `candidate`/`to_tag`/`from_digest` all EMPTY → promoter never resolved a clean immutable `sha-*`
      candidate for order (`app-cve-scan.sh:333`/`:362` "promotion skipped"/"rebuild dispatched — waits
      for clean candidate"). So order isn't a config toggle: the promoter can't produce/resolve a
      CVE-clean candidate image for order. Two durable fixes to weigh: (a) persist promotions to git
      instead of live-patching the Application (survives reconcile); (b) close order's rebuild→clean-image
      loop. NOT started — flagged to user.
- [x] **CVE remediation dashboard never clears — FIXED + LIVE-VERIFIED 2026-08-08 (queued user item).**
      Spec `docs/bugs/v1.23.0-bugfix-cve-remediation-event-gc.md` (doc `c4cfb388`), fix `9168edd7`
      (`feat(cve): garbage-collect old remediation events (keep newest N per service)`). Root: 70 event
      ConfigMaps, no ownerRefs/TTL/sweeper → immutable ledger; exporter emits one
      `cve_remediation_event_info` series per event → dashboard shows all-time, stale `manual_review`
      (pre-`minReadySeconds`) never clear. Fix: `_gc_events` in `cve-remediation-verify.sh` keeps newest
      `REMEDIATION_EVENT_KEEP_PER_SERVICE` (default 5) **terminal** events per service, never touches
      `promotion_requested`; name-embedded `YYYYMMDDHHMMSS` gives sortable order (no date parsing). SA
      `app-cve-scanner` already had `configmaps delete` (no RBAC change). shellcheck+`sh -n` clean.
      **Live:** updated `cve-remediation-verify-script` ConfigMap; count dropped **70→15** (5/svc), all 7
      stale `manual_review` GONE; exporter now 15 series / 0 manual_review (`{failed:10, applied:5}`).
      Remaining `failed`: 5 payment (clear after PR #59 merge) + 5 order (task #18). Durable via
      `argocd.sh:1454` (script→ConfigMap wiring).
- [x] **Webhook agy model drift — FIXED + restarted + verified 2026-08-08 (queued user notification).**
      Spec `docs/bugs/v1.23.0-bugfix-webhook-agy-model-drift.md` (doc `6e837906`, code `8e7a5c79`).
      `TrivyCriticalVulnerabilityDetected` Slack alert showed `invalid model selection (--model
      "gemini-2.5-flash")` — Alertmanager `k3dm-analyze` → `/api/v1/analyze` → `agy --model
      GEMINI_MODEL` where `bin/k3dm-webhook:211` defaulted to the retired `gemini-2.5-flash`. Fixed
      default → `gemini-3.5-flash-medium` (valid per `agy models`). py_compile clean; `make
      restart-webhook` done; webhook up (health→auth), plist has no `K3DM_ANALYSIS_MODEL` override,
      model ID valid → next alert analysis won't error. Companion fix `612ca86d` (spec `4acf1b6c`):
      `gemini.sh` `_GEMINI_MODELS` (was 2.5/2.0/1.5-flash) → `gemini-3.5-flash-medium` /
      `3.6-flash-medium` / `3.1-pro-low`; `antigravity.bats` assertions updated in lockstep — all 7 bats
      pass, shellcheck clean. No `gemini-2.5/2.0/1.5-flash` refs remain in either file.
- [x] **PACKAGES_TOKEN rotation chore ELIMINATED for PR path — PR #60 (shopping-cart-payment), CI GREEN.**
      Root of the recurring Image Build Check 401 (see [[reference_packages_token_expiry_image_build]]):
      lint/build/image-build-check auth'd the GitHub Packages pull of the **public** `rabbitmq-client`
      with the manually-rotated `PACKAGES_TOKEN` PAT. Switched those 3 jobs to the built-in
      `GITHUB_TOKEN` (branch `fix/ci-github-token-for-packages`, commit `d307ddc`, PR #60). **Image
      Build Check SUCCESS with GITHUB_TOKEN; #60 CLEAN/MERGEABLE** → empirically proven, no PAT rotation
      needed. Awaiting user merge (never auto-merge). After #60 merges → `@dependabot rebase` #56/#53
      → they pick up the fix → Image Build Check passes → auto-merge. `publish` job left on
      PACKAGES_TOKEN (reusable workflow may need cross-repo PAT) + same swap pending for order/basket.
- [x] **CVE dashboard namespace=platform-ops collision — FIXED live + committed `43ece528` (task #13).**
      Spec `docs/bugs/v1.23.0-bugfix-cve-dashboard-namespace-collision.md` (Option A). Root cause:
      `vulnerability-inventory-exporter` runs in platform-ops; Prometheus `honorLabels:false`
      overwrote the metric's `namespace` with the target's. Fix: `honorLabels:true` on the exporter
      ServiceMonitor → `trivy_vulnerability_inventory.namespace` now real (11 namespaces verified);
      `TrivyCriticalVulnerabilityDetected` alert re-fires with correct ns → panel 7 "Firing Critical
      CVE Alerts" attributes correctly. Carried the exporter + inventory-based rule forward (were
      archive-only) and wired `deploy_argocd_platform_ops` to apply the exporter + cve-autopatch
      dashboard (branch bootstrap applied neither). Re-ported part (a)'s panel 5 (deployed the branch
      dashboard live — was committed `db81f534`, never deployed). Kept the alert `app` label (webhook
      renders `.Labels.app`). Correction: the LIVE dashboard was the BRANCH dashboard (not archive) —
      the `exported_namespace` flips were unneeded. Alerts finish → firing after the 15m `for:`.
      **DEPLOYED + PUSHED 2026-08-07** (fix `43ece528` on origin). The cve-autopatch dashboard is
      ArgoCD-managed by ApplicationSet `grafana-dashboards-hub`, frozen at `k3d-manager-v1.22.0`
      (selfHeal reverted my direct applies). Reapplied BOTH `grafana-dashboards-hub` and
      `grafana-dashboards-acg` ApplicationSets to track `k3d-manager-v1.23.0` (K3D_MANAGER_BRANCH);
      hub Synced w/ part(a) panel, ubuntu-hostinger Synced, ubuntu-k3s Unknown (dead sandbox, normal).
      honorLabels ServiceMonitor + inventory rule are NOT ArgoCD-managed (argocd.sh bootstrap) → persist.
      ⚠️ Dashboard ApplicationSets now track the in-flight v1.23.0 branch: future v1.23.0 dashboard
      commits (parts b/c panels 8/9) will auto-deploy on push.
      **Part (a) REVERTED 2026-08-07 (`1d9251b4`)** — after seeing "Critical Vulnerabilities by Image"
      live, the user preferred the original "Critical Vulnerabilities by Namespace" panel format;
      restored panel 5 to the v1.22.0 version (`sum by (namespace) (trivy_image_vulnerabilities)`).
      db81f534 is superseded. The dashboard now matches v1.22.0 exactly; namespace-collision fix
      (honorLabels) unaffected. NOTE: parts (b)/(c) spec `5aa7f771` still references panel-5 "by image"
      as untouched — re-check that assumption before executing b/c.
      **FULL REVERT TO CODEX 1:1 2026-08-07 (`06a0416e`, doc `0516f98d`)** — user reported the live
      dashboard had only ONE table + wrong columns vs what they used to see, asked for exact 1:1
      with Codex. Root cause: live dashboard was the v1.23.0 branch's simpler single-table version,
      not Codex's full 4-table archive dashboard (`archive/…v1.22.0-integration` `eae0d607`). Restored
      `grafana-dashboard-cve-autopatch.yaml` + `vulnerability-inventory-exporter.yaml` byte-for-byte
      from archive; **reverted honorLabels:true** so `exported_namespace` returns (Codex detail tables
      read it). Verified live: ArgoCD `hub-grafana-dashboards` synced `06a0416e`; ConfigMap + Grafana
      provisioned file show all 4 tables (Platform/Shopping-cart Unique CVEs, Recent CVE Remediations,
      Firing Critical CVE Alerts); Prometheus re-scraped honorLabels-off. TRADE-OFF (user chose): summary
      panels group by `namespace` → read `platform-ops` again, as Codex built it. honorLabels/exported_
      namespace fix (43ece528) is superseded — any future namespace fix must modify Codex's dashboard,
      not replace it.
- [ ] **v1.24.0** — webhook + credential rotation + istio/hostinger ops + unseal watchdog (D+E+F).
      Blocker: recurring rotation automation for ArgoCD/Prometheus/Alertmanager (only LDAP+Grafana done).
- [ ] **v1.25.0** — Stripe/Go live acceptance + hostinger capacity (G, BLOCKED, cross-repo). Blockers:
      merge order-repo `0e3feb9` schema fix + promote image → rerun Stripe live E2E (2/4 now);
      hostinger capacity expansion.

## Done — recent (pointers) — cont.

- [~] **Grafana admin password rotation trap — DB never updated (found + stopgap-fixed 2026-08-07).**
      Symptom: `make show-service-passwords` Grafana value gave HTTP 401 at `grafana.3ai-talk.org`,
      but `make status` reported "Grafana login: HTTP 200". Root cause: kube-prometheus-stack Grafana
      applies `admin_password` from `existingSecret` ONLY at first DB provisioning — the monthly
      rotator (`grafana-credential-rotator`) rotates Vault → ESO → k8s secret `grafana-admin-credentials`
      but NEVER changes Grafana's sqlite DB password, so Vault/secret (same hash) drift from the DB.
      **Stopgap applied live:** `grafana cli admin reset-admin-password --password-from-stdin` inside
      the pod, reset DB to the stored secret value → login now HTTP 200. **Will recur on next monthly
      rotation.** Two durable fixes needed (spec pending): (1) rotator + initial deploy must apply the
      new password to Grafana's DB (reset-admin-password or admin API) after writing the secret;
      (2) `bin/k3dm-webhook` hub Grafana smoke reads `acg-kube-prometheus-stack-grafana` (app-cluster,
      ABSENT on hub) → false-green; must read hub `grafana-admin-credentials`
      (monitoring/admin-password) so `make status` actually catches this drift. Audited the others —
      ArgoCD (`argocd-initial-admin-secret`), Prometheus + Alertmanager basic-auth all authenticate
      HTTP 200 with their displayed passwords; only Grafana was broken. See [[project_status_login_verification]].
- [x] **Grafana `show-service-passwords` unblock (2026-08-07).** `make show-service-passwords`
      was reading Grafana from the stale k8s secret after the live credential rotation. Pulled the
      Makefile Grafana hunk forward from workstream E (`40c8b08e`) onto v1.23.0 (`31db9732`); now
      reads `secret/data/observability/grafana` from Vault. Intent map updated: v1.24.0 E carve-out
      skips this hunk. Nothing was lost/overridden — full E work stays parked on
      `archive/k3d-manager-v1.22.0-integration` for v1.24.0.
- [x] **Grafana→Vault wiring RESTORED onto v1.23.0 (2026-08-07, `5b418dd7`) + confirmed LIVE.**
      Restored workstream-E Grafana slice from archive (`141cfa34`/`9d5e25c5`/`5f16d736`/`79019fc9`):
      `grafana-admin-externalsecret.yaml` + `grafana-credential-rotator.yaml` (whole), plus Grafana
      hunks of `kube-prometheus-stack-values.yaml` (existingSecret `grafana-admin-credentials`),
      `observability.sh` (apply + Vault role), `vault.sh` (`_vault_configure_secret_writer_role`).
      **Confirmed deployed & effective 2026-08-07 after OrbStack upgrade + cluster restart:** the
      wiring was already live on the cluster (secret + rotator ~45–46h old, predating the source
      restore) — so the v1.23.0 restore was reconciling the release branch to match live, not a fresh
      deploy. Verified: Vault unsealed (watchdog auto-unsealed on restart, HA active); Vault path
      `secret/observability/grafana` holds `username=admin` + a 48-char rotated password (NOT the
      leaked value); ESO ExternalSecret `SecretSynced: True` re-synced 1h post-restart; Grafana pod
      consuming it via `existingSecret`; monthly rotator CronJob (`0 0 1 * *`) installed. Intent map:
      v1.24.0 E skips the Grafana slice.

## v1.23.0 verifier — queued spec

- [ ] **CVE verifier false-negative on multi-arch index-digest aliasing (spec queued 2026-08-09).**
      Verifier compares pod runtime `imageID` (index digest) vs remediation `to_digest` (different
      index over the same amd64 child) → payment/order mislabeled `ready_pod_digest_mismatch` though
      the patched image IS running (proven: both indexes → child `4e3b7f8c`/config `34599a8c`). Fix =
      verify Deployment-pinned spec digest + readiness gate, drop the runtime-imageID compare. Spec:
      `docs/bugs/v1.23.0-bugfix-cve-remediation-verify-multiarch-index-digest.md`. Not yet handed off.
- [x] **CVE verifier multi-arch index-digest aliasing — COMPLETE 2026-08-09.** Commit `33b45a41`
      verifies the Deployment-pinned digest instead of the unreliable pod runtime `imageID`, while
      preserving readiness and the applied reason. `shellcheck`, `sh -n`, and `_agent_audit` passed;
      pushed to `origin/k3d-manager-v1.23.0`. No dashboard reason-string references were found;
      Claude owns the post-merge verifier reapply and live confirmation.

## Backlog (not release-gated)

- [ ] Shopping-cart Dependabot backlog (Go builder-image bumps, majors held for migration work) —
      tracked in Claude auto-memory `project_backlog.md`.
- [ ] rabbitmq-client-java NPE fix `36ed860` — JAR publish + pom update pending.

## Done — recent (pointers)

- [x] Stripe checkout A–F merged to main across 5 shopping-cart repos (2026-08-02); enablement #47/#66
      merged; order access-control hardening PR #56 `65c5b7a` (IDOR + configurable aud/azp). Detail in
      `docs/issues/2026-08-02-*` + git.
- [x] Branch-protection approval count restored `0→1` on shopping-cart-infra #89 + order #63.
- [x] Integration branch archived `archive/k3d-manager-v1.22.0-integration` (`03ed9ad6`) + intent map.
- [x] v1.22.0 shipped — PR #111 merged `1bbb74b0`, tagged, enforce_admins restored, retro written (2026-08-07).
