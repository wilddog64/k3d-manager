# Changelog

## [Unreleased]

### Added
- **Managed sandbox registration cleanup (v1.26.0 foundation)** — ArgoCD cluster registrations can carry provider, release, sandbox, and expiry metadata; `make cleanup-stale-clusters` previews and, with explicit confirmation, removes only expired, managed k3s-aws registrations after an API-failure grace period. Hostinger/permanent registrations are skipped, generated Application resources are never pruned, and JSONL audit decisions are retained.
- **Safe local cache retention** — the existing daily `com.k3d-manager.cleanup` LaunchAgent now removes only unreferenced Packer ISO/lock artifacts older than 30 days and stale port markers older than 7 days; active caches and unrelated OrbStack data are untouched.
- **Tier 1 E2E verification harness** — `e2e_verify_vcluster` (`scripts/plugins/e2e.sh`) stands up the shopping-cart stack (postgres + redis + product-catalog/basket/order + seed) in a throwaway vCluster via a self-contained kustomize bundle (`scripts/etc/e2e/`, zero Vault/ESO/ArgoCD dependency, `OAUTH2_ENABLED=false`, all images pinned), runs the Playwright `api`+`flows` suite as an in-cluster Job against ClusterIP DNS, writes an exit-code-faithful JSON summary to `$E2E_REPORT_DIR/<run_id>.json`, and tears the vCluster down on success **and** failure. Optional arg overrides the service-under-test image with a candidate digest. Structural + exit-code-contract coverage in `scripts/tests/plugins/e2e.bats`; learning guide `docs/guides/vcluster-e2e-harness.md` — see `docs/plans/v1.25.0-e2e-harness-tier1-impl.md`. (Part 1, the publishable `shopping-cart-e2e-tests` image + `workflow_call` surface, is a companion change in that repo.)

### Fixed
- Remediation events classified as `superseded` or `deployment_advanced` now remain in audit history but
  are excluded from the Current CVE Remediation Status table, avoiding rows that have no applied timestamp.
- **Monitoring stability under load** — raised the local Prometheus/Grafana CPU budgets and bounded the
  monolithic Loki workload so liveness probes do not restart Prometheus during expensive CVE queries;
  see `docs/issues/2026-08-17-grafana-no-data-control-plane-load.md`.
- `make down CLUSTER_PROVIDER=k3s-aws` now deregisters the sandbox cluster and generated hub Applications, while local-provider dry-runs load the command bridge before launchd teardown (`469a3427`) — see `docs/bugs/v1.25.0-bugfix-dry-run-phase3-make-down-deregister.md`

- Standardized lifecycle dry-run handling on `DRY_RUN` (while retaining the legacy alias), completed per-operation teardown guards, and added stubbed cluster-up/down coverage (`d2263cc2`) — see `docs/bugs/v1.25.0-bugfix-dry-run-phase2b-standardize-and-complete.md`

## [1.24.1] - 2026-08-13

**Theme: make cluster status legible — one concise service-health view for the terminal, Slack, and automation.** A point release on top of v1.24.0. `make status` used to dump a long multi-section report that was hard to consume; it now defaults to a **concise, color-coded service-health summary** (with `make status-full` for the old detailed report and `make status-json` for a stable machine-readable summary), follows the **active cluster provider**, and takes `SERVICE=<name>` for focused per-service diagnostics. The same summary now reaches **Slack**: `/cluster-status` renders an emoji-severity one-liner (`:x:` / `:warning:` / `:white_check_mark:` + `N ok / N warn / N fail`) instead of a wall of ANSI-derived text. The CVE remediation dashboard is split into a live **Current CVE Remediation Status** table and a **Remediation History (audit)** table, with the exporter marking superseded / deployment-advanced events, and both dashboard and inventory tables hide repeated Prometheus scrape metadata behind concise column headers. Verified live on the hub: `make status-json` returns `overall=healthy` for `k3s-hostinger`, and the Slack path renders `:white_check_mark: *Cluster status: HEALTHY* — \`k3s-hostinger\` (13 ok / 0 warn / 0 fail)` from real cluster data.

### Added
- Concise color-coded `make status` service-health output (new default) plus `make status-full` (the detailed pod/diagnostic report) and `make status-json` (stable JSON summary for Slack/CI); `SERVICE=<name>` focuses a single service; new `bin/cluster-status-summary` and `--summary`/`--full`/`--json` flags on `bin/cluster-status` (`7ed82b89`) (`Makefile`, `bin/cluster-status`, `bin/cluster-status-summary`, `scripts/tests/bin/cluster_status_summary.bats`) — see `docs/plans/v1.24.1-status-output-contract.md`
- Slack `/cluster-status` (hostinger) renders as a concise emoji-severity summary with no ANSI, via `bin/cluster-status --json` fed through a shared `_format_status_summary_slack` (raw-report fallback retained) (`5b9442cf`) (`bin/k3dm-webhook`) — see `docs/bugs/v1.24.1-bugfix-slack-cluster-status-summary-wiring.md`
- CVE remediation dashboard splits **Current CVE Remediation Status** from **Remediation History (audit)**; the `vulnerability-inventory-exporter` exposes `current` and marks `superseded` / `deployment_advanced` failed events with a `display_reason`, so stale failed rows no longer read as current state (`d471d075`, `a119fdde`) (`scripts/etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml`, `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`)

### Fixed
- `make status` and `make status-json` follow the **active provider** (from `~/.local/share/k3d-manager/active-provider`) in every mode instead of defaulting to `k3s-aws`, and classify an optional Pushgateway connection refusal as a warning rather than a failure (`2758e626`, `7c000254`) (`Makefile`, `bin/cluster-status-summary`)
- The status source reads the webhook token from the **keyed** Keychain account (`k3dm-webhook-token`/`k3dm`) so the summary tool authenticates to `/api/v1/health` (`15579e7a`) (`bin/cluster-status-summary`, `bin/k3dm-webhook-setup`)
- The login smoke checks use **current** Vault-sourced ArgoCD/Grafana credentials (post-rotation) and hub-scoped Keycloak credentials, and the LaunchAgent renderer substitutes the real `$HOME` in `KUBECONFIG`, so ArgoCD/Grafana/Keycloak logins stop false-failing after a credential rotation (`a729e8ce`) (`bin/k3dm-webhook`)
- The CVE dashboard and CVE-inventory tables hide repeated Prometheus scrape metadata (`service`, `container`, `endpoint`, exported labels) and use concise headers (`CVEs`, `Affected service`, `Image`, `Requested`, `Applied`, `State`, `Reason`) (`199621e1`, `91b13fe3`) (`scripts/etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml`)

## [1.24.0] - 2026-08-11

**Theme: platform hardening — reconcile live drift into git, automate credential rotation, and make CVE remediation durable.** This release closes four seams where the live cluster had drifted ahead of git or where a security control was one boundary deep. The internet-facing k3dm webhook now **fails closed** on malformed Slack signature input and enforces the Slack `user`→role allowlist as real code (the helper was dead until this release), so a present-but-invalid identity resolves to reader, never admin. Istio-ambient and hostinger-CNI fixes that had only ever been applied to the live cluster (committed to the archive branch) are reconciled **onto the release branch** so a rebuild reproduces them. Two persistent credentials gain **recurring rotation**: a least-privilege in-cluster ArgoCD admin rotator (monthly CronJob, bcrypt fed via stdin, no argv leak, sidecar-excluded so the Job can complete) and a host-side Prometheus basic-auth launchd timer — and the weak `admin/password` Prometheus default is removed at the source. The CVE remediation promoter stops **live-patching** the ArgoCD Application (lost on rebuild) and instead **persists the pinned digest to git** on the app's tracked branch, so a remediation survives a cluster recreate. Verified live on the hub: a one-shot ArgoCD rotation advanced `argocd-secret` mtime, wrote a clean bcrypt, and the new Vault password logged into `/api/v1/session`; the promoter's git-persist path was dry-run end-to-end (clone → awk-pin → `push --dry-run` authenticates) leaving the remote untouched.

### Added
- Monthly **ArgoCD admin credential rotator** — an in-cluster CronJob (namespace `cicd`) that generates a new password, writes it to Vault (`secret/argocd/admin`), bcrypts it via `argocd account bcrypt` over **stdin** (never `--password` argv), and patches `argocd-secret`; a least-privilege `Role` with pinned `resourceNames` (no wildcard, no cluster-admin) and a `sidecar.istio.io/inject: "false"` annotation so the Job isn't deadlocked by the mesh proxy (`3db193cb`, `84232cc0`) (`scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml`, `scripts/plugins/argocd.sh`, `scripts/tests/plugins/argocd.bats`) — see `docs/plans/v1.24.0-credential-rotation-automation.md`
- Host-side **Prometheus basic-auth rotation** — a launchd timer (`com.k3d-manager.prometheus-credential-rotator.plist.tmpl`) driving `observability_rotate_prometheus_basic_auth`, which regenerates a strong bcrypt and re-applies `prometheus-web-config` (the `alpine/k8s` image has no htpasswd/openssl, so rotation is host-side, not a CronJob) (`3db193cb`) (`scripts/plugins/observability.sh`, `scripts/etc/launchd/com.k3d-manager.prometheus-credential-rotator.plist.tmpl`)
- **Git-persisted CVE remediation promoter** (task #18) — `_git_persist_promotion` clones the app's tracked `targetRevision` branch, awk-pins the remediated `digest:` in `services/shopping-cart-<svc>/kustomization.yaml`, and commits+pushes as `k3dm-cve-promoter`, so a promotion is durable in git instead of a live Application patch lost on rebuild; `GIT_WRITE_TOKEN` is `optional: true` — absent, the promoter falls back to live-patch-only (`3df62fbf`) (`scripts/etc/argocd/platform-ops/app-cve-scan.sh`, `scripts/etc/argocd/platform-ops/app-cve-scan-cronjob.yaml`, `scripts/plugins/argocd.sh`) — see `docs/plans/v1.24.0-order-remediation-promoter.md`

### Changed
- `make show-service-passwords` reads the ArgoCD admin credential from Vault (`secret/data/argocd/admin`) instead of the install-time `argocd-initial-admin-secret`, which goes stale after the first rotation and no longer logs in (`33e42905`) (`Makefile`)
- The hostinger status report keeps its header and per-service health sections when long — truncation now preserves head+tail instead of dropping the tail wholesale (`8eb8cc34`) (`bin/k3dm-webhook`) — see `docs/bugs/v1.24.0-bugfix-hostinger-status-report-truncation.md`

### Fixed
- The Prometheus basic-auth generator no longer seeds the weak `admin/password` default — both weak-hash fallback references are removed and credentials are generated via stdin-fed `htpasswd -i` (`e1256d0a`) (`scripts/plugins/observability.sh`) — see `docs/bugs/v1.24.0-bugfix-prometheus-weak-basic-auth-default.md`
- Four latent ArgoCD-rotator defects the structural test missed, caught in live verify: `argocd account bcrypt` fed via `printf '%s'` (no newline) → `fatal EOF`, fixed with `printf '%s\n'`; the tool prints its `Password: ` prompt to **stdout**, corrupting the captured hash, stripped with `sed 's/^Password: //'`; the CronJob's istio sidecar in the injected `cicd` namespace deadlocked the Job (`BackoffLimitExceeded`), fixed with `sidecar.istio.io/inject: "false"`; and the Prometheus rotator's launchd plist templated a nonexistent `bin/k3d-manager` (the dispatcher is `scripts/k3d-manager`) (`84232cc0`) (`scripts/etc/argocd/platform-ops/argocd-credential-rotator.yaml`, `scripts/plugins/observability.sh`, `scripts/tests/plugins/argocd.bats`) — see `docs/bugs/v1.24.0-bugfix-argocd-rotator-bcrypt-and-istio-sidecar.md`
- Istio-ambient and hostinger drift reconciled onto the release branch: `istio-ambient.yaml` gains a `ServerSideDiff=true` compare-option and `ignoreDifferences` for the istiod `ValidatingWebhookConfiguration` caBundle/failurePolicy (controller-owned runtime state); `k3s-hostinger.sh` sets `AMBIENT_CNI_CONF_DIR`/`_BIN_DIR` pointing the Istio CNI DaemonSet at the k3s/flannel paths (not Cilium defaults) (`357edf52`) (`scripts/etc/argocd/applicationsets/istio-ambient.yaml`, `scripts/lib/providers/k3s-hostinger.sh`, `scripts/etc/argocd/projects/shopping-cart.yaml.tmpl`) — see `docs/plans/v1.24.0-istio-hostinger-drift-reconcile.md`
- The webhook's headless CVE alert analysis stops auto-denying — `_call_gemini` prepends a headless tool-suppression guard to every prompt (single choke point) and detects the `"headless mode"…"auto-denied"` string, so a TrivyCritical Slack alert now returns real analysis text from context instead of the raw jetski permission-denied string (`69e21e15`) (`bin/k3dm-webhook`) — see `docs/bugs/v1.24.0-bugfix-webhook-gemini-headless-permission.md`

### Security
- The webhook Slack signature verification **fails closed** on malformed timestamp/body input (try/except around the sig verify) instead of throwing an unhandled error, and the Slack `user`→role allowlist is enforced in `bin/k3dm-webhook` (import + reject block) rather than sitting as dead code — an unknown or invalid Slack identity resolves to reader, never admin (`3fddcf3e`) (`bin/k3dm-webhook`, `scripts/lib/webhook/auth.py`, `scripts/tests/lib/webhook.bats`) — see `docs/plans/v1.24.0-webhook-auth-reconcile.md`
- The ArgoCD and Prometheus rotators keep the plaintext credential out of process argv — bcrypt/htpasswd read the new password from **stdin**, and the ArgoCD rotator runs under a namespace-scoped `Role` with pinned `resourceNames` (no cluster-admin, no wildcard verbs) (`3db193cb`, `84232cc0`)

## [1.23.0] - 2026-08-09

**Theme: make CVE remediation observable and self-verifying.** v1.20.0 made the auto-patch loop *run*; this release makes it *trustworthy*. A CVE inventory dashboard and a vulnerability-inventory exporter show **what** is vulnerable and **where** (real namespace, image, resource); the remediation verifier stops guessing from the pod's runtime `imageID` — which containerd aliases to a different OCI index digest for multi-arch images, producing false `ready_pod_digest_mismatch` on images that were in fact patched — and instead confirms the **Deployment-pinned spec digest** plus readiness, and it now looks in each service's real namespace (`payment` runs in `shopping-cart-payment`, not `shopping-cart-apps`). Stale remediation state clears itself (the event ledger is garbage-collected to the newest N terminal events per service), and the alert stream stops re-paging about images already being fixed (a new `CVERemediationInFlight` alert inhibits `TrivyCriticalVulnerabilityDetected` for the same image during an active auto-patch, and the analyze route caps re-notification at 12h). Two Bitnami-removal outages are closed by re-pinning the remediation verifier and LDAP rotator off the deleted `bitnami/kubectl` image, and the pulled-forward **Grafana admin credential rotation** (Vault-sourced + monthly rotator) is made to actually run end-to-end after four latent blockers. Verified live end-to-end on the hub: the verifier flips matching-digest payment events `promotion_requested → applied`, and Alertmanager suppresses the paired TrivyCritical during an in-flight remediation and lifts it on completion.

### Added
- CVE inventory Grafana dashboard (four tables — platform/shopping-cart unique CVEs, recent remediations, firing critical CVE alerts) driven by a new `vulnerability-inventory-exporter` that emits `trivy_vulnerability_inventory` / `cve_remediation_state` / `cve_remediation_event_info` series; both are applied by `deploy_argocd_platform_ops` so they survive a rebuild (`43ece528`, `06a0416e`) (`scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`, `scripts/etc/argocd/platform-ops/grafana-dashboard-cve-autopatch.yaml`, `scripts/plugins/argocd.sh`)
- CVE remediation event garbage collection — `_gc_events` keeps the newest `REMEDIATION_EVENT_KEEP_PER_SERVICE` (default 5) **terminal** events per service (never touching `promotion_requested`), using the name-embedded `YYYYMMDDHHMMSS` for ordering, so the dashboard stops showing all-time stale `manual_review` rows (`9168edd7`) (`scripts/etc/argocd/platform-ops/cve-remediation-verify.sh`) — live: event ConfigMaps dropped 70→15
- `CVERemediationInFlight` alert (fires while `cve_remediation_state{state="promotion_requested"}`) inhibits `TrivyCriticalVulnerabilityDetected` for the same image during an active auto-patch; the `k3dm-analyze` route caps re-notification at `repeatInterval: 12h` instead of inheriting the Alertmanager global default (`ed52cf0c`, `72be9383`) (`scripts/etc/argocd/platform-ops/prometheusrule.yaml`, `scripts/etc/argocd/platform-ops/alertmanager-config.yaml`) — see `docs/bugs/v1.23.0-bugfix-cve-alert-inhibit-and-repeat-interval.md`
- Grafana admin credential sourced from Vault with a monthly rotator CronJob (Vault write → ESO force-sync → k8s secret → Grafana DB reset) — pulled forward onto this release after a leaked admin password (`5b418dd7`) (`scripts/etc/argocd/platform-ops/grafana-admin-externalsecret.yaml`, `scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml`, `scripts/plugins/vault.sh`, `scripts/plugins/observability.sh`, `scripts/etc/helm/observability/kube-prometheus-stack-values.yaml`)

### Changed
- The remediation verifier CronJob, its `cve-remediation-verify.sh` script, and RBAC are carried onto the release branch and wired into `deploy_argocd_platform_ops` (the verify-script ConfigMap is built from the working tree), so the every-5-minute remediation-state loop is part of the durable platform-ops deploy instead of living only on the archive branch (`33b151ba`) (`scripts/etc/argocd/platform-ops/`, `scripts/plugins/argocd.sh`)
- `make show-service-passwords` reads the Grafana admin credential from Vault (`secret/data/observability/grafana`) instead of the post-rotation-stale k8s secret (`31db9732`) (`Makefile`)

### Fixed
- The remediation verifier confirms the **Deployment-pinned container spec digest** (plus the readiness gate) instead of the pod's runtime `imageID` — containerd reports a multi-arch pod's `imageID` as whichever OCI **index** digest it first cached the platform child under, so a byte-identical patched image string-compared as a `ready_pod_digest_mismatch` false-negative; payment/product-catalog now verify correctly (`33b45a41`) (`scripts/etc/argocd/platform-ops/cve-remediation-verify.sh`) — see `docs/bugs/v1.23.0-bugfix-cve-remediation-verify-multiarch-index-digest.md`
- The remediation verifier looks up each service in its real namespace via a `_namespace_for` map (`payment-service` → `shopping-cart-payment`, others → `shopping-cart-apps`) instead of a hard-coded `-n shopping-cart-apps`, which had mis-verified payment (`8a8566e8`) (`scripts/etc/argocd/platform-ops/cve-remediation-verify.sh`)
- The `CVERemediationInFlight` source alert normalizes `image_repository` with `label_replace` (strips the `ghcr.io/` registry host) because `cve_remediation_state` is host-qualified while `trivy_vulnerability_inventory` is bare `org/repo` — without it the inhibit rule's `equal: ["image_repository"]` join matched nothing (caught by a live hub check) (`72be9383`) (`scripts/etc/argocd/platform-ops/prometheusrule.yaml`)
- `TrivyCriticalVulnerabilityDetected` no longer fires on an empty `image_repository` (transient VulnerabilityReports for ephemeral job pods can carry an empty `artifact.repository`, paging with an unactionable empty app name): the alert selector gains `image_repository!=""` and the exporter skips empty-repository reports in both the hub and app loops (`5302ea54`) (`scripts/etc/argocd/platform-ops/prometheusrule.yaml`, `scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`) — see `docs/bugs/v1.23.0-bugfix-trivy-critical-empty-image-repository-alert.md`
- CVE inventory attributes to the real workload namespace — the exporter ServiceMonitor uses `honorLabels: true` so Prometheus stops overwriting the metric's `namespace` with the scrape target's `platform-ops` (`43ece528`) (`scripts/etc/argocd/platform-ops/`); the summary panels were subsequently restored to group by `namespace` to match the shipped Codex dashboard 1:1 (`06a0416e`)
- The Grafana monthly rotator runs end-to-end for the first time — four latent blockers fixed: the pod could never start (`runAsNonRoot: true` on a root `alpine/k8s` image with no `runAsUser` → `CreateContainerConfigError`) is fixed with `runAsUser`/`runAsGroup: 65534` (`a66463e1`); `openssl` is absent from `alpine/k8s` so password generation uses `/dev/urandom`+`od` (`4557cdeb`); `kubectl rollout status` needs `deployments` **list/watch** (a ListWatch informer, for which `resourceNames` is ignored) so a separate verbs-only rule is added alongside the name-scoped get/patch (`a0bb46c2`); and the rotated password is applied to Grafana's sqlite DB via `grafana cli admin reset-admin-password --password-from-stdin` while the webhook status smoke reads the **hub** `grafana-admin-credentials` instead of the absent hostinger `acg-…` secret that had produced a false-red 401 (`816835fd`) (`scripts/etc/argocd/platform-ops/grafana-credential-rotator.yaml`, `bin/k3dm-webhook`)
- The remediation verifier and LDAP password rotator are re-pinned off the removed `docker.io/bitnami/kubectl:latest` image (deleted in Bitnami's Aug 2025 catalog migration → `ImagePullBackOff`) to the maintained `docker.io/alpine/k8s:1.31.4` (`33b151ba`, `ddc68c90`) (`scripts/etc/argocd/platform-ops/app-cve-scan-cronjob.yaml`, `scripts/etc/ldap/vars.sh`)
- The webhook rate limiter runs **after** authentication/signature checks (a single global bucket per channel let an unauthenticated flood `429` the one legitimate caller) and both POST sites guard `Content-Length` through `_content_length` (`400` on a non-numeric header instead of a traceback) (`ee32837d`) (`bin/k3dm-webhook`, `scripts/tests/bin/webhook_request_hardening.py`) — see `docs/bugs/v1.23.0-bugfix-webhook-ratelimit-order-and-content-length.md`
- The webhook alert-analysis default model and the `gemini.sh` fallback chain are retired off the removed `gemini-2.5-flash` id to current `agy` model ids (`gemini-3.5-flash-medium` / `3.6-flash-medium` / `3.1-pro-low`), with `antigravity.bats` assertions updated in lockstep, so a TrivyCritical Slack alert no longer analyzes with an `invalid model selection` error (`8e7a5c79`, `612ca86d`) (`bin/k3dm-webhook`, `scripts/plugins/gemini.sh`, `scripts/tests/plugins/antigravity.bats`)
- `TrivyCriticalVulnerabilityDetected` no longer floods Slack with non-actionable upstream CVEs: a live hub check found 39 firing alerts but only 1 (`wilddog64/shopping-cart-payment`) auto-remediable — the other 38 were third-party images (`hashicorp/vault`, `grafana/grafana`, `istio/pilot`, `library/postgres`, `keycloak/keycloak`, …) the app-cve-scan loop cannot rebuild, yet all carried `remediation: cve-auto-patch` and routed to the remediate + analyze webhooks. The alert is split by image ownership: only `wilddog64/*` keeps `remediation: cve-auto-patch`; upstream images get a `tier: upstream` rule routed to a new `k3dm-quiet` blackhole receiver (still visible on the CVE inventory dashboard, no Slack). namespace is not a usable discriminator — the exporter attributes every image to `platform-ops`, so a namespace exclusion would suppress the one real alert. Also fixed the analyze Slack title rendering the wrong label (`labels["name"]` → empty for Trivy alerts, arriving as `TrivyCriticalVulnerabilityDetected — ''`), now falling back to `app`/`image_repository` (`scripts/etc/argocd/platform-ops/prometheusrule.yaml`, `scripts/etc/argocd/platform-ops/alertmanager-config.yaml`, `bin/k3dm-webhook`) — see `docs/bugs/v1.23.0-bugfix-trivy-critical-upstream-image-alert-noise.md`

### Security
- `make show-service-passwords` no longer passes the Vault root token on the `curl` command line (visible in process listings) — the Grafana and Prometheus credential lookups now write the token to a `mktemp` header file and pass it via `-H "@<file>"`, matching the existing `observability.sh` pattern (Copilot PR #112) (`Makefile`)
- The `vulnerability-inventory-exporter` gains a writable `/tmp` `emptyDir` so `readOnlyRootFilesystem: true` no longer breaks cert-based app-cluster scraping, where `exporter.py` materializes client cert/key via `tempfile` (Copilot PR #112) (`scripts/etc/argocd/platform-ops/vulnerability-inventory-exporter.yaml`)
- `_vault_configure_secret_writer_role` quotes `mount_path` with `printf %q` before the `vault secrets enable` command string crosses `_vault_exec`'s `sh -lc` boundary, closing a shell-injection surface in the reusable helper (Copilot PR #112) (`scripts/plugins/vault.sh`)

## [1.22.0] - 2026-08-07

**Theme: migrate OpenLDAP off the retired Bitnami image to the Symas chart.** Bitnami's `bitnamilegacy` OpenLDAP images are no longer maintained; this release moves the directory service to the community `jp-gouin/openldap-stack-ha` chart (4.3.3) and reconciles every consumer so the cutover is transparent. Admin/config passwords are now generated delimiter-safe so the chart's `sed`-based templating can't corrupt them, the platform `admin`/`developer`/`operator` users survive the chart swap (Vault-seeded bootstrap made durable), and Keycloak's LDAP federation plus the password-rotator labels are reconciled to the new `openldap.identity.svc.cluster.local` service. Verified live: the Symas chart is running, `developer` login succeeds through Keycloak, and Jenkins LDAP auth is reconciled. Pure-logic BATS `ldap_chart_passwords` 2/2 green; shellcheck clean on all changed shell.

### Changed
- OpenLDAP migrated from the retired `bitnamilegacy` image to the Symas `jp-gouin/openldap-stack-ha` chart (4.3.3); Keycloak LDAP federation and Jenkins LDAP auth reconciled to `openldap.identity.svc.cluster.local` (`0b23884b`) (`scripts/plugins/ldap.sh`, `scripts/etc/ldap/values.yaml.tmpl`, `scripts/etc/ldap/vars.sh`, `scripts/etc/keycloak/vars.sh`, `scripts/plugins/keycloak.sh`, `scripts/plugins/jenkins.sh`, `scripts/etc/jenkins/values-ldap.yaml.tmpl`)

### Fixed
- LDAP chart admin/config passwords are generated delimiter-safe (hex), so the Symas chart's `sed`-based value templating can no longer corrupt them (`7fb1ad28`) (`scripts/plugins/ldap.sh`, `scripts/tests/plugins/ldap_chart_passwords.bats`) — see `docs/issues/2026-08-05-openldap-chart-password-sed-delimiter.md`
- Platform `admin`/`developer`/`operator` users are preserved across the Symas migration — the Vault-seeded bootstrap is now durable instead of one-shot (`c6195bb2`) (`scripts/plugins/ldap.sh`, `scripts/etc/ldap/bootstrap-basic-schema.ldif`)
- Keycloak policy and password-rotator labels reconciled to the new OpenLDAP service so consumer wiring survives the cutover (`e9fa00cc`) (`scripts/plugins/keycloak.sh`, `scripts/etc/ldap/ldap-password-rotator.sh`, `scripts/etc/ldap/ldap-password-rotator.yaml.tmpl`) — see `docs/issues/2026-08-05-openldap-consumer-reconciliation.md`

## [1.21.0] - 2026-08-03

**Theme: harden the k3dm webhook auth surface.** A security review of the internet-facing webhook (Cloudflare Worker → tunnel → `127.0.0.1:7443`) found the bearer token was the only real boundary — and it grants full admin. This release adds defense-in-depth so a leaked token, a Slack user without an explicit role, or a crafted `/ask` payload can no longer reach admin operations. The Slack command path now enforces the same RBAC as the HTTP path, roles fail **closed** instead of open, the `/ask` bash sandbox blocks interpreter and shell escapes, and the server gains a rate limiter, guarded JSON parsing, a bounded event-id cache, and a token-file permission check. Verified live on a restarted `:7443` instance (health 200; no-token → 401; invalid role → 403 fail-closed to reader; malformed JSON → 400; sustained GETs trip the 429 rate limiter) and by `bin/smoke-test-webhook` (13/13 health checks) with 49/49 BATS green. **Owner deploy note:** populate `K3DM_SLACK_ROLE_MAP` (env or Keychain `k3dm-slack-role-map`) before deploy, or every Slack user is treated as reader-only.

### Security
- Slack command path enforces RBAC — a `user`→role allowlist (`K3DM_SLACK_ROLE_MAP` env / Keychain `k3dm-slack-role-map`, unknown user → reader) plus a minimum-role check in `_handle_thread_command`, so Slack no longer bypasses the role gate the HTTP path enforces (`490756e1`) (`bin/k3dm-webhook`, `scripts/lib/webhook/auth.py`)
- Roles fail **closed** — a present-but-invalid role header now resolves to reader instead of admin (an absent header is still the direct-token admin path, unchanged) (`490756e1`) (`scripts/lib/webhook/auth.py`)
- `/ask` bash sandbox blocks interpreters, nested shells, and redirection in `k3dm-ask-bash`, closing the denylist-bypass paths in the read-only sandbox (`490756e1`) (`bin/k3dm-ask-bash`)
- Fixed-window rate limiter returns `429` on sustained request bursts; guarded POST `json.loads` returns `400` on malformed bodies instead of tracing back; the Slack `_seen_event_ids` dedup cache is bounded (OrderedDict cap 2048); a `TOKEN_FILE` with over-permissive mode is rejected; the `GEMINI_CLI_TRUST_WORKSPACE` workspace-trust escape hatch is dropped (`490756e1`) (`bin/k3dm-webhook`)

### Fixed
- `make show-service-passwords` shows the current Keycloak user passwords (`21cf3a38`) (`Makefile`)
- `stale_test_refs.bats` guards its three fixture tests with a commit-reachability `skip` so a fresh CI clone stays green — the hard-coded historical SHAs (`f03df202`/`4c89dabb`/`e3a75f1f`) were orphaned by the v1.20.0 branch cleanup and are unreachable in CI even under `fetch-depth: 0` (`scripts/tests/lib/stale_test_refs.bats`)

## [1.20.0] - 2026-08-01

**Theme: make the CVE auto-patch loop actually run.** v1.18.0 wired up the Trivy→webhook→`app-cve-scan` detect→patch loop; this release fixes the many ways it broke in practice. `app-cve-scan` now targets ArgoCD Applications by their cluster-prefixed name (26 remediation jobs had been failing on the bare service name and never patched anything), resolves multi-arch image digests through OCI image-index media types, authenticates registry reads with the scan pod's BusyBox `wget`, and exits 0 when a scan completes — a still-pending per-service remediation no longer marks the whole CronJob Failed, which had a triage bot looping on a misleading "Trivy exits 1 on CRITICAL" diagnosis. Failed scan pods no longer accumulate, the Hub chart is read from live deployment metadata instead of a guessed path, and `make up` reconciles platform-ops so the CVE stack is present after a cold bring-up. (v1.19.0 was a shopping-cart-only Dependabot milestone with no k3d-manager changes — no tag.)

### Changed
- `make up` reconciles the platform-ops stack after the cluster comes up, so the CVE scan and dashboards are present on a cold bring-up instead of needing a manual `make platform-ops` (`0a316fb6`) (`Makefile`)

### Fixed
- `app-cve-scan` patches ArgoCD Applications by their cluster-prefixed name instead of the bare service name — root cause of 26 remediation-job failures that ran but patched nothing (`9f7cdfe0`) (`scripts/etc/argocd/platform-ops/app-cve-scan.sh`)
- `app-cve-scan` accepts OCI image-index media types in the manifest `Accept` header, so multi-arch `latest`/`sha-*` digests resolve instead of silently failing candidate resolution (`17f5f0e0`) (`scripts/etc/argocd/platform-ops/app-cve-scan.sh`)
- `app-cve-scan` authenticates registry reads with the scan pod's BusyBox `wget --header` instead of the GNU-only `--config`, which BusyBox `wget` does not support (`47c2e2d7`) (`scripts/etc/argocd/platform-ops/app-cve-scan.sh`)
- `app-cve-scan` exits 0 when the scan completes — a per-service unresolved-digest or failed-rebuild-dispatch state now emits a warning notification instead of poisoning the Job exit code; only a run that matched zero VulnerabilityReports fails the Job. Both scan CronJob pod templates carry `app` / `app.kubernetes.io/name` labels so alerts render the workload name instead of `app ''` (`03fe5684`) (`scripts/etc/argocd/platform-ops/`)
- CVE scan no longer retries a service whose immutable candidate image cannot be resolved this run — it notifies and moves on instead of spinning the batch (`0136571f`) (`scripts/etc/argocd/platform-ops/app-cve-scan.sh`)
- CVE scan CronJobs bound `backoffLimit` and `ttlSecondsAfterFinished`, so failed scan pods no longer accumulate in `platform-ops` (`bda65d5c`) (`scripts/etc/argocd/platform-ops/`)
- Hub CVE scan reads the target chart from live deployment metadata instead of a hard-coded path, so it keeps working when the Hub chart layout changes (`699da11b`) (`scripts/etc/argocd/platform-ops/cve-scan.sh`)
- LDAP password seeds are verified during cluster bring-up, so identity login self-heals instead of silently seeding an unusable credential (`bb5b5653`) (`bin/cluster-up`)

## [1.18.0] - 2026-07-28

**Theme: close the first-mile CVE gap.** A Trivy vulnerability report on a running app now drives an automatic patch end-to-end: the Trivy alert fires a webhook that re-runs `app-cve-scan`, and — for the app dependencies Trivy can't rebuild — Dependabot is enabled on all five shopping-cart repos so dependency CVEs self-heal into PRs. The platform-ops stack (CVE scan + dashboards + webhook-token sync) now deploys from bootstrap so it survives a rebuild, a hub Grafana dashboard makes the auto-patch loop observable, and the webhook token has a Keychain→Secret disaster-recovery path. Ships lib-foundation **v0.4.8** via subtree (brace-expansion CVE fix).

### Added
- Event-driven CVE auto-patch — a Trivy vulnerability alert fires the k3dm webhook, which re-runs `app-cve-scan` for the affected workload, closing the detect→patch loop without manual intervention (`1684190c`) (`bin/k3dm-webhook`, `scripts/plugins/`)
- Hub Grafana dashboard visualizing the event-driven CVE auto-patch loop — Trivy reconcile health, alert dispatch, and scan outcomes (`29a087cf`) (`scripts/etc/helm/observability/`)
- Webhook-token disaster recovery — the `k3dm-webhook-token` Secret auto-syncs from the macOS Keychain on every platform-ops deploy, and the Keychain→Secret sync is generalized so the app-rebuild `gh-token` follows the same DR path (`b0bc5a21`, `907f6259`) (`scripts/plugins/argocd.sh`)
- `make status` reports ApplicationSet values-branch drift so a set frozen on a stale release branch is visible instead of silently inert (`3e847b26`, `c704d669`) (`scripts/plugins/argocd.sh`, `Makefile`)
- Dependabot version + security updates enabled on all five shopping-cart repos (`basket`, `frontend`, `order`, `payment`, `product-catalog`) so app-dependency CVEs self-heal into PRs, with branch protection made Dependabot-mergeable (real required checks replacing the phantom `Go CI`, `required_approving_review_count: 0`) (`595f6750`, `b6df96af`, `0df2b0a5`)

### Changed
- platform-ops (CVE scan, dashboards, webhook-token sync) now deploys from the ArgoCD bootstrap path so it survives a cold rebuild instead of needing a manual reapply (`8537f27e`) (`scripts/plugins/argocd.sh`)
- Alertmanager `matcherStrategy: None` so a cluster-wide CVE alert routes to the webhook receiver regardless of namespace labels (`5af5e3a7`) (`scripts/etc/helm/observability/`)
- Every Trivy version pinned explicitly on the newest matched values set — no floating tags (`f428225f`) (`scripts/etc/helm/observability/`)
- lib-foundation subtree synced to **v0.4.8** (`79294e89`) (`scripts/lib/foundation/`)

### Fixed
- `app-cve-scan` authenticates ghcr reads with `GH_TOKEN`, so it can pull vulnerability reports for private packages instead of silently seeing nothing (`191d9f4a`) (`scripts/plugins/`)
- CVE scan matches Trivy vulnerability reports on the registry-less repository path, so reports keyed without the registry prefix are no longer missed (`43e63b53`) (`scripts/plugins/`)
- Keycloak LDAP federation component is created when absent, so login self-heals on a cluster rebuild instead of staying broken (`989dc8e4`) (`scripts/plugins/keycloak.sh`)
- `make show-service-passwords` displays the correct dev users (`admin`/`Shopping1!`, …) instead of the stale `alice`/`test1234` (`ad96c028`) (`Makefile`)
- Trivy reconcile Grafana panel — fixed a query that matched zero lines, corrected `timeFrom`, and converted the render to a per-container bar gauge on an instant Loki query so it actually shows data (`9fde2c43`, `a7d230f2`, `1d33df99`, `cf0901e6`, `67f018a7`, `bf32a000`) (`scripts/etc/helm/observability/`)

### Security
- brace-expansion bumped to 1.1.16 via the lib-foundation v0.4.8 subtree, clearing the transitive DoS advisory (`79294e89`) (`scripts/lib/foundation/`)

## [1.17.0] - 2026-07-24

**Theme: the smoke test proves real logins.** `make status` used to false-green because the health smoke only fetched health URLs — a Keycloak stale-session page returns HTTP 200 and counted as a pass. The smoke now performs credentialed logins (token mint / authed request) against Keycloak, the frontend, ArgoCD and Grafana, seeding its own Keycloak client and user so it never depends on app-owned client configuration.

### Added
- k3d-manager seeds its own `k3dm-smoke` Keycloak client + user via `keycloak_seed_smoke_user`, storing the generated credential in the `identity/k3dm-smoke-user` Secret — the app-owned `frontend` client has `directAccessGrantsEnabled=false`, so a password grant can never succeed against it (`647b4181`) (`scripts/plugins/keycloak.sh`)
- Login smoke auto-discovers ArgoCD and Grafana admin credentials from their in-cluster Secrets instead of requiring the operator to export env vars (`cdeebfa6`) (`bin/k3dm-webhook`)

### Changed
- Health smoke verifies **real logins** rather than health pages — a credentialed token POST for Keycloak, an authed request for the frontend, and credentialed logins for ArgoCD/Grafana, so a stale-session page can no longer report green (`843e643a`) (`bin/k3dm-webhook`)

### Fixed
- Seeded smoke user now receives the Keycloak 24+ declarative User Profile attributes that are required by default (`email`, `firstName`, `lastName`, `emailVerified`), and repairs them idempotently on re-run, so the direct-access-grant token mint no longer fails `invalid_grant "Account is not fully set up"` on a fresh cluster (`950998aa`) (`scripts/plugins/keycloak.sh`)
- Frontend login smoke attempts the authed `/api/cart` request when falling back to the `k3dm-smoke` client instead of unconditionally skipping it — 2xx passes, a smoke-client `401`/`403` skips (audience-strict deployment), anything else fails (`2a55f0be`) (`bin/k3dm-webhook`)
- `_ambient_install_cilium` builds `ssh_cmd` as an array instead of a string, so all three remote invocations quote the key path and user@host correctly (`05d74f6c`) (`scripts/plugins/shopping_cart.sh`)

### Removed
- Dead `_argocd_configure_post_deploy` — orphaned since the deploy path was restructured — along with the `enable_vault` local it was the only consumer of (`ac729e14`, `db26dd61`) (`scripts/plugins/argocd.sh`)

## [1.16.0] - 2026-07-23

**Theme: ambient mesh comes to the app tier.** Migrate the hostinger shopping-cart workloads from sidecar injection to Istio **ambient** (ztunnel + istio-cni, HBONE/mTLS with zero sidecar containers), make the ambient path durable across `make refresh` and cold `k3s-aws` rebuilds, harden multi-cluster ArgoCD so a second app cluster no longer clobbers the first, and right-size control-plane/observability CPU for the 2-CPU hostinger node. Ships lib-foundation **v0.4.7** via subtree.

### Added
- Ambient dataplane on the app tier — the `shopping-cart-apps` namespace is enrolled via `istio.io/dataplane-mode=ambient` (ztunnel HBONE + mTLS, no `istio-proxy` sidecars); verified live carrying real traffic on hostinger (`ebf27de3`) (`services/shopping-cart-namespace/namespace.yaml`)
- `cluster-status` now reports service-mesh mode, CNI substrate, and ambient-namespace enrollment so mesh/CNI health is visible at a glance (`da67e2bf`) (`bin/cluster-status`)
- Ambient CNI conf/bin dir variables defaulted and exported in the ArgoCD bootstrap path (`AMBIENT_CNI_CONF_DIR`/`AMBIENT_CNI_BIN_DIR`) (`a08911b3`) (`scripts/etc/argocd/vars.sh`)
- shopping-cart `AppProject` so data-layer and services Applications can sync, including the `secrets` namespace for the vault-bridge (`e118f664`, `64168cc7`) (`scripts/etc/argocd/`)

### Changed
- istio-cni conf/bin dirs are now CNI-substrate aware — resolve to the Cilium defaults (`/etc/cni/net.d`, `/opt/cni/bin`) or the k3s/rancher paths as appropriate instead of a single hardcoded assumption (`9c0e336a`, `ce4d83f0`) (`scripts/etc/argocd/applicationsets/istio-ambient.yaml`, `scripts/plugins/istio_ambient.sh`)
- `istiod` and `ztunnel` CPU requests right-sized for the 2-CPU hostinger node (`1af15217`); the built-in Trivy server scheduling reservation trimmed `200m`→`50m` on both the hub and the app-cluster (`acg`) observability values so `product-catalog` can schedule (`7345b24a`, `45381c7d`) (`scripts/etc/helm/observability/`)
- ArgoCD appsets derive `APP_CLUSTER_NAME` from the active cluster instead of hardcoded hostinger, and `services-git` Application names are keyed by cluster, so a second app cluster no longer collides with the first (`896d08ad`, `18b92cd2`) (`scripts/etc/argocd/applicationsets/`)
- lib-foundation subtree synced to **v0.4.7** — `acg_restart` shell entrypoint for the orphaned recovery script, stale `playwright-artifacts-*` temp-dir sweep, and `acg_check_ttl`/wrapper node-exit captures made `set -e`-safe (`40d4c42d`) (`scripts/lib/foundation/`)

### Fixed
- hostinger `make refresh` now reapplies the `istio-ambient` ApplicationSet instead of dropping it, so the ambient dataplane survives a refresh (`470ef7d8`) (`scripts/lib/providers/k3s-hostinger.sh`)
- `k3s-aws` cold rebuild — node-ready and SSM-register wait loops made `set -e`-safe (assignment form, not `(( var++ ))`), `k3sup --k3s-version` pinned so provisioning survives an `update.k3s.io` channel outage, and `K3S_AMBIENT_MESH=true` defaulted in the up flow so Cilium installs for ambient (`520621a9`, `5be42ae4`, `bca7d59a`) (`scripts/lib/providers/k3s-aws.sh`)
- ArgoCD appset `envsubst` now fails loudly on an unset variable instead of substituting an empty string that silently mis-renders a manifest (`2966a3b9`) (`scripts/lib/providers/`)
- app CVE scan dispatches via `wget` (with matching bats coverage) and fails loudly when the infra cluster secret is absent instead of scanning nothing (`89c2efd6`, `5fcc3f89`) (`scripts/plugins/`)
- trap-guarded the bare `mktemp` sites in `shopping_cart.sh`/`argocd.sh` so temp files are cleaned on RETURN even without an interrupt (`319762b9`) (`scripts/plugins/`)
- hub k3d k3s image pinned to `v1.32.0-k3s1` to satisfy the istioctl precheck floor (`1cc55252`) (`scripts/lib/cluster.sh`)

## [1.15.0] - 2026-07-13

**Theme: security & multi-cluster provider hardening.** Close a dev-dependency DoS advisory via the lib-foundation subtree, end Trivy Standalone scan-job cache-lock failures by moving to a shared built-in Trivy server, and harden multi-cluster registration (per-context hub-Vault connectivity, safer default provider with a reachability preflight).

### Changed
- Per-context hub-Vault ClusterSecretStore connectivity — hub-Vault CSS overrides are now keyed per app context so registering a second app cluster no longer clobbers the first cluster's connectivity profile (`46f400b9`) (`scripts/etc/vault/vars.sh`)
- Default cluster provider demoted off `k3s-aws` with an added reachability preflight, so a bare invocation no longer defaults to an AWS cluster and an unreachable target fails fast instead of hanging (`2f74acf3`) (`scripts/lib/provider.sh`)
- lib-foundation subtree synced to v0.4.4 — ACG Extend sandbox-tab routing fix plus the js-yaml advisory bump below (`999edb81`) (`scripts/lib/foundation/`)

### Fixed
- Trivy scan-job cache-lock — migrated the Trivy Operator from Standalone to ClientServer mode via the chart's built-in shared Trivy server, eliminating the per-job vuln-DB `cache may be in use by another process: timeout` failures under concurrent scans (`855a06e4`) (`scripts/etc/helm/observability/trivy-operator-values.yaml`, `trivy-operator-acg-values.yaml`)

### Security
- js-yaml DoS advisory closed — dev-only transitive `js-yaml` bumped `3.14.2`→`3.15.0` via the lib-foundation v0.4.4 subtree, resolving Dependabot GHSA-h67p-54hq-rp68 (medium) once merged to the default branch (`scripts/lib/foundation/`)

## [1.14.0] - 2026-07-12

**Theme: observability & multi-cluster reliability hardening.** A reactive hardening sprint from operating the observability stack and the multi-cluster (laptop / Hostinger / OCI / ACG) fleet under real load — 21 bug specs in `docs/bugs/`, of which 19 shipped as `fix(...)` commits.

### Changed
- Vault per-context app-cluster auth mount (Workstream 3 Phase 1) — `configure_vault_app_auth_for_context` now derives a per-cluster Kubernetes auth mount `kubernetes-<sanitized-context>` via a new `_vault_app_auth_mount` helper and threads it through all three env-driven mount sites (`configure_vault_app_auth`, the shopping-cart ClusterSecretStore auth block, and the ESO remote-Vault SecretStore), so registering a second app cluster no longer overwrites the single shared `kubernetes-app` mount and invalidate the prior cluster's ESO auth (last-cluster-wins). An explicit `APP_K8S_AUTH_MOUNT` override pins the legacy single-cluster path for migration (`scripts/lib/core.sh`, `scripts/plugins/vault.sh`, `scripts/plugins/shopping_cart.sh`, `scripts/plugins/eso.sh`)
- lib-foundation subtree synced to v0.4.3 (v0.4.1/v0.4.2 pulled en route — ACG headless CDP auto-login + reclaim/reuse) (`scripts/lib/foundation/`)

### Fixed
- Grafana stability — raised the Grafana memory limit to stop frequent restarts and liveness-probe kills (`1af49f44`) (`scripts/plugins/observability.sh`)
- Prometheus durability — hub Prometheus TSDB moved off `emptyDir` onto a PVC with a raised `retentionSize` (`6ae2f758`); app-cluster Prometheus given its own PVC and 15d retention so it no longer keeps only 2h (`23e5d67f`) (`scripts/plugins/observability.sh`)
- Grafana public route — `grafana.3ai-talk.org` routed back to the hub Grafana so hub CVE/Trivy/Image-Updater dashboards resolve to the hub instance (`65dcf6e8`)
- Trivy hub dashboard correctness — object-level drilldown links + visible in-viewport banner (`f4560d56`/`d0a2d92f`/`76752337`), finding explanations (`44488f88`), actionable alert summaries (`a95fda82`), ownership classification and fixed-state (`215a4157`/`68b71222`/`44488f88`), active-finding + zero-value compliance-row dedupe (`215a4157`/`68b71222`/`ae088b34`), and Image Updater processing-log counter parsing (`06813683`) (`scripts/plugins/observability.sh`, `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`)
- Loki logs panels — filtered and formatted so they no longer render empty or raw JSON (`7e39ffaa`) (`scripts/plugins/observability.sh`)
- Trivy scan-job OOMKills — raised the scan-job scanner memory limit 512Mi→1Gi and request 64Mi→256Mi in both hub and ACG values files to stop `exit 137` OOMKills on heavier Standalone-mode scans (`d434e289`); `operator.resources` unchanged (`scripts/etc/helm/observability/trivy-operator-values.yaml`, `trivy-operator-acg-values.yaml`)
- Hostinger Grafana port-forward regenerated for the ACG service (`14fd68b2`) (`scripts/lib/providers/k3s-hostinger.sh`)
- ACG sandbox lifecycle — seed Vault address resolved at call time to stop the `exit-22` empty-port freeze (`ac5e3fde`); `_vault_kv_put` surfaces the KV write HTTP status on seed failure instead of swallowing it (`44c1aec8`); an absent sandbox is classified separately from tunnel loss (`e2c79595`); `k3s-oci` mapped to its own kube context (`80ac1ba0`); tunnel mode auto-selects SSM vs SSH by probing `iam:CreateRole` (`2834e1d3`) (`scripts/plugins/acg.sh`, `scripts/plugins/vault.sh`, `scripts/lib/cluster_provider.sh`)
- Hub-Vault profile state scoped by app context so a per-cluster profile is no longer shared across clusters (`e7fc432e`); the shopping-cart rerun Vault helper scope resolved for LDAP password seeding (`df74e754`) (`scripts/plugins/vault.sh`, `scripts/plugins/shopping_cart.sh`)

## [1.13.0] - 2026-07-05

### Added
- Isolated webhook-server smoke gate — `bin/smoke-test-webhook` boots a throwaway `k3dm-webhook` instance against an overridden `K3DM_JOB_DIR`/`K3DM_RUN_DIR` and smoke-tests `/api/v1/health`, so CI and pre-restart checks can exercise the server without clobbering the live `:7443` job dirs (`bin/smoke-test-webhook`)
- Post-refactor webhook-server architecture doc — documents the `bin/k3dm-webhook` monolith plus the `scripts/lib/webhook/` module layout after the v1.13.0 modularization, the request flow, and the remaining extraction phases (`docs/architecture/webhook-server.md`)

### Changed
- Webhook modularization Phase 1 — pure, low-risk helpers extracted verbatim from the `bin/k3dm-webhook` monolith into an importable `scripts/lib/webhook/` package: `config.py` (constants, paths, `_safe_job_dir`), `render.py` (Slack output helpers), `proc.py` (the fork-safe `os.posix_spawn` capture primitive), and `auth.py` (Keychain lookup, bearer-token resolution, Slack signature verification). No change to command behavior or the external Slack/Worker contract (`bin/k3dm-webhook`, `scripts/lib/webhook/config.py`, `render.py`, `proc.py`, `auth.py`)

### Fixed
- Vault token hygiene — `VAULT_TOKEN` is delivered to Vault commands via stdin instead of process argv, so it can no longer leak through the process table or shell history (`scripts/plugins/vault.sh`)
- Trivy Operator RBAC — chart pin realigned with the `0.31.2` operator image to restore the PV/PVC RBAC the version skew had dropped, ending the reconciler crashloop (`scripts/etc/argocd/applicationsets/observability.yaml`, `scripts/etc/argocd/applicationsets/observability-acg.yaml`)
- Trivy ServiceMonitor — the acg Trivy release gets its own `release` label so its ServiceMonitor stops colliding with the platform Trivy and Grafana scrapes both (`scripts/etc/argocd/applicationsets/observability-acg.yaml`, `scripts/etc/helm/observability/trivy-operator-acg-values.yaml`)
- Webhook BATS isolation — the suite now stubs `make`, `K3DM_GEMINI_BIN`, and `kubectl` in `setup_file`, isolates `K3DM_JOB_DIR`/`K3DM_RUN_DIR`, and serializes cluster-queue tests on a per-test cluster-idle wait, so running tests no longer launches live `make up`/Chrome/`agy`, mutates a live cluster, pollutes the live run dir (false Slack orphan-job alerts), or flakes with `409 cluster job already running` on fast CI runners (`scripts/tests/lib/webhook.bats`)

## [1.12.0] - 2026-07-03

### Added
- App-image CVE auto-update pipeline — ArgoCD Image Updater watches shopping-cart app images (`basket`, `order`, `product-catalog`), gates promotion on Trivy vulnerability reports, writes back immutable SHAs (not `latest`), and dispatches rebuilds; Image Updater is installed during bootstrap so it survives cluster rebuilds, with a `ghcr-pull-secret` provisioned in `cicd` for GHCR auth (`scripts/etc/argocd/applicationsets/services-git.yaml`, `scripts/plugins/argocd.sh`)
- App CVE visibility in `make status` and Grafana — status surfaces the app CVE scan plus Trivy VulnerabilityReport and infra-security summaries; a hub Grafana dashboard (auto-refresh 5m) shows Image Updater readiness, watched-app churn, and Loki-backed logs (`bin/cluster-status`, `scripts/plugins/observability.sh`, `scripts/etc/argocd/platform-ops/grafana-dashboard-argocd.yaml`)
- Remote operator access over Slack/Cloudflare — the relay assigns per-command roles and forwards `X-K3DM-Role`/`X-K3DM-Actor`/`X-K3DM-Source-Command`; `bin/k3dm-webhook` enforces minimum roles (returns `403`), writes a JSONL audit trail under `~/.local/share/k3d-manager/audit/`, and adds a read-only `/cluster-diagnose` path (allowlisted verbs, repo-owned namespaces only) (`workers/slack-relay/index.js`, `bin/k3dm-webhook`)
- Public Alertmanager access — exposed via Cloudflare behind a credential-rereading basic-auth proxy (`feat(observability): add alertmanager basic auth proxy`, `expose alertmanager via cloudflare`) (`bin/alertmanager-auth-proxy`, `scripts/plugins/observability.sh`)
- Trivy Operator observability — scan-job failures and infra-security findings surface in Grafana with new Prometheus alert rules routed to the analyzer webhook (`scripts/etc/argocd/applicationsets/observability*.yaml`, `scripts/etc/argocd/platform-ops/prometheusrule.yaml`, `alertmanager-config.yaml`)

### Changed
- Debug artifacts moved out of `/tmp` — script-owned output now lands in `~/.local/share/k3d-manager/run`; `bin/k3dm-cleanup` prunes those artifacts and age-prunes stale repo-owned `/tmp` leftovers safely (`bin/k3dm-webhook`, `scripts/plugins/acg.sh`, `bin/k3dm-cleanup`)
- ArgoCD alerts grouped and broadened — rules carry a shared `group: argocd` label and cover watched apps; Image Updater flapping raises a dedicated `ArgoCDImageUpdaterFlapping` alert (`scripts/etc/argocd/platform-ops/prometheusrule.yaml`, `alertmanager-config.yaml`)
- Webhook failure analysis defaults to the Antigravity CLI (`agy`) instead of the retired Gemini CLI (`bin/k3dm-webhook`)

### Fixed
- Hostinger `refresh` hardening — refresh is idempotent, reapplies GitOps/observability/data ApplicationSets to the hub context, clears stale `ubuntu-hostinger-platform` app ownership generically, restores the Alertmanager access layer, re-resolves frontend nginx upstream DNS, and self-heals the `shopping-cart-apps` GHCR pull secret (`scripts/lib/providers/k3s-hostinger.sh`, `scripts/plugins/shopping_cart.sh`, `scripts/plugins/vault.sh`)
- Vault token hygiene — refresh no longer inlines Vault tokens in auth commands or logs; the app-cluster policy is rewritten every refresh, the GitHub PAT is seeded into the app Vault, and canonical secrets (redis/rabbitmq/minio/ldap/keycloak) seed from the source Vault for parity (`scripts/plugins/vault.sh`, `scripts/plugins/shopping_cart.sh`)
- Slack `/cluster-status` reliability — the relay acks immediately and relays in the background; the webhook accepts the `provider` kwarg on the hostinger status path; the worker smoke-tests after deploy and fails fast when the Cloudflare token is missing (`workers/slack-relay/index.js`, `bin/k3dm-webhook`, `bin/k3dm-worker-setup`, `Makefile`)
- Trivy operator rendering — pinned to a released chart version with a public operator image override after ArgoCD refused to render `0.31.2` on Kubernetes 1.36 (`scripts/etc/argocd/applicationsets/observability*.yaml`, `scripts/etc/helm/observability/trivy-operator-values.yaml`)
- Loki/Grafana wiring — hub Loki release name kept promtail-compatible, simple-scalable targets disabled in monolithic mode, Fluent Bit ships container log paths, and Image Updater dashboard datasource UIDs pinned (`scripts/plugins/observability.sh`, `scripts/etc/argocd/platform-ops/*`)
- ACG watcher and bootstrap — `make up` bootstraps the Playwright module before cluster-up, and the ACG watch LaunchAgent reloads after its log paths are retargeted to the run dir so the change takes effect on the live agent (`bin/cluster-up`, `bin/cluster-refresh`, `scripts/plugins/acg.sh`)
- Frontend GHCR pulls — Deployment patched with `imagePullSecrets: [ghcr-pull-secret]` to fix anonymous GHCR `401 Unauthorized` (`services/shopping-cart-frontend/kustomization.yaml`)
- Alertmanager status — `make status` self-heals missing local Alertmanager LaunchAgents and falls back to the local proxy, and the auth proxy rereads credentials on every request so rotation takes effect without a restart (`scripts/plugins/observability.sh`, `bin/cluster-status`, `bin/alertmanager-auth-proxy`)

## [1.11.0] - 2026-06-28

### Added
- Tier 3 P3 canonical-source Vault seeding — `vault_seed_hub_into_context` operator plus idempotent seeding of `redis/*` and `rabbitmq/default` from a canonical source (re-runnable without drift), with retargeted inner seed helpers (`scripts/plugins/vault.sh`, `scripts/plugins/shopping_cart.sh`)
- Tier 3 P4 assisted-failover watchdog — `vault_failover_hub_into_context` (probe the hub Vault → on sustained failure flip `HUB_VAULT_PROFILE` and persist it → re-seed the in-cluster Vault → reconcile the app-cluster ClusterSecretStore), the `vault_install_failover_watchdog` installer, a `com.k3d-manager.vault-failover` LaunchAgent (StartInterval 300s) with its plist template, and the `bin/k3dm-vault-failover` wrapper (`scripts/plugins/vault.sh`, `scripts/etc/launchd/com.k3d-manager.vault-failover.plist.tmpl`, `bin/k3dm-vault-failover`)

### Fixed
- Failover watchdog hardening — the wrapper prepends the Homebrew prefixes (`/opt/homebrew/bin:/usr/local/bin`) to PATH so it finds `kubectl`/`helm`/`jq` under launchd's minimal PATH, and the re-seed call runs in a subshell so an unreachable laptop source degrades to warn-and-continue instead of aborting the failover before the CSS reconcile (`bin/k3dm-vault-failover`, `scripts/plugins/vault.sh`)
- Failover watchdog now sources `vars.sh` before reading the active profile, so the persisted `HUB_VAULT_PROFILE` from the state file is honored in the watchdog dispatch path while explicit env still wins (`scripts/plugins/vault.sh`)
- App-cluster Vault auth targets the in-cluster Vault context under the `hostinger` profile instead of the laptop hub (`scripts/plugins/vault.sh`)
- Audience bound on the app-cluster `eso-app-cluster` kubernetes-auth role so ESO token review succeeds (`scripts/plugins/vault.sh`)
- `deploy_eso` skips the Helm install when ESO is externally managed (ArgoCD-owned), preventing an install conflict during the in-cluster cutover (`scripts/plugins/eso.sh`)
- `k3s-hostinger` `refresh` now runs `launchctl enable` before `bootstrap` so it heals previously disabled launchd agents (`scripts/lib/providers/k3s-hostinger.sh`)

### Changed
- `.gitguardian.yaml` migrated to the v2 schema and the ggshield cache is now ignored (`.gitguardian.yaml`, `.gitignore`)

## [1.10.0] - 2026-06-27

### Added
- Provider-agnostic app-cluster Vault auth keyed on kube-context (`configure_vault_app_auth_for_context`) — the Kubernetes auth wiring is now portable across providers (EKS/AKS/ACG/Azure/OCI/Hostinger) instead of being pinned to Hostinger (`scripts/plugins/vault.sh`)
- `HUB_VAULT_PROFILE` endpoint seam (`laptop` | `hostinger`) selecting the hub-Vault `server:` URL written into the app-cluster ClusterSecretStore and whether the reverse-tunnel/socat bridge is stood up; default `laptop` keeps today's behavior byte-for-byte (Tier 3 P1, `scripts/etc/vault/vars.sh`)
- In-cluster auto-unseal watchdog CronJob for a relocated hub Vault — replays the Shamir shard from the in-cluster `vault-unseal` Secret on a `vault status` exit-code trigger; pinned image, namespace-scoped, no RBAC; self-contained and behavior-preserving (nothing auto-calls it) (Tier 3 P2a, `scripts/plugins/vault.sh`)
- `vault_deploy_hub_into_context` wrapper to provision the hub Vault inside an app cluster (current-context save/restore idiom; `HUB_VAULT_INCLUSTER=1` guard bypasses the `CLUSTER_ROLE=app` early-return), plus a least-privilege `app-cluster-reader` Vault policy (7 `secret/{data,metadata}/*` prefixes, no wildcard) and a kubernetes-auth ClusterSecretStore variant selected by `HUB_VAULT_CSS_AUTH` (`laptop`→token, `hostinger`→kubernetes); default profile stays `laptop` so the cutover is P3-gated (Tier 3 P2b, `scripts/plugins/vault.sh`, `scripts/plugins/shopping_cart.sh`)

### Fixed
- Hostinger `refresh` now ensures the `vault-port-forward` LaunchAgent is present so the laptop→Hostinger Vault bridge survives a refresh (`scripts/lib/providers/k3s-hostinger.sh`)
- ArgoCD `data-layer` ApplicationSet ignores controller-injected `volumeClaimTemplates[]` fields (`.status`, `.apiVersion`, `.kind`) so StatefulSets stop showing a permanent cosmetic `OutOfSync` (`scripts/etc/argocd/applicationsets/data-git.yaml`)

## [1.8.0] - 2026-06-26

### Added
- ESO operator install on app clusters via an ArgoCD ApplicationSet cluster generator (`scripts/etc/argocd/applicationsets/eso.yaml`) — selects `k3d-manager/role: app-cluster`, installs the `external-secrets` chart `1.0.0` with CRDs into the `secrets` namespace using server-side apply; portable across host OS and CPU arch (install runs in-cluster, not from the local CLI)

### Changed
- lib-foundation subtree synced to v0.4.0 — absorbed lib-acg, added `_ensure_agy_cli` and the extensible cluster-provider hook (`scripts/lib/foundation/`)
- ACG module now sourced from lib-foundation: the `acg.sh`, `gcp.sh`, and `gemini.sh` stubs repoint to `scripts/lib/foundation/scripts/lib/acg/` (Phase 2 of the lib-acg absorption); `bin/cluster-up` / `bin/cluster-refresh` npm-prefix and `acg-credential-test` paths follow
- `gemini.sh` browser automation retargeted from the retired `@google/gemini-cli` to the Go-based Antigravity CLI (`agy --dangerously-skip-permissions`); `_ensure_gemini` now provisions `agy` instead of npm-installing gemini-cli; public `gemini_*` function names retained (backend-only swap)

### Fixed
- shopping-cart data-layer routing: the app-cluster ArgoCD cluster secret now carries the `k3d-manager/role: app-cluster` label so the `data-git` ApplicationSet generator matches it (`scripts/lib/providers/k3s-hostinger.sh`, `scripts/etc/argocd/cluster-secret.yaml.tmpl`)
- Slack webhook: `cluster-up`/`cluster-down`/`cluster-resume` are now accepted as top-level standalone commands (were thread-reply-only); provider allowlist on all three now includes `hostinger` and defaults to `hostinger` instead of `aws`, so a bare or unrecognized provider no longer silently starts an ACG AWS sandbox run (`bin/k3dm-webhook`)
- `k3s-hostinger` reconcile now provisions `ghcr-pull-secret` on the Hostinger context (best-effort with a warning), so shopping-cart pods stop sitting in `ImagePullBackOff` after a deploy/refresh
- `k3s-hostinger` app-cluster registration uses CA-verified TLS and ensures the `argocd-manager` ServiceAccount exists before registering with the hub ArgoCD
- `k3s-hostinger` provider-aware `refresh` restored — re-bootstraps ESO, restarts the keycloak public port-forward, restores the repo-managed cloudflared tunnel, and is now bash 3.2-safe with rebuilt browser wrappers
- `k3s-hostinger` ArgoCD access layer hardened on refresh — kills stale argocd wrappers, clears stale 8080 listeners, and restarts the argocd port-forward
- provider state precedence: a live Hostinger cluster now wins over a stale active-provider state file, and the active-provider state stays in sync across Hostinger switches (no more falling through to AWS defaults)
- `make status` / smoke probes are provider-aware for Hostinger — preflight apps are reported separately and the Hostinger access layer is restarted
- preflight vcluster is now deregistered from the hub ArgoCD on destroy; stale preflight stack retired and app-cluster role relabeled on the hub
- observability: ACG monitoring secrets are created against the resolved active app-cluster instead of a stale context

### Removed
- standalone `lib-acg` subtree (`scripts/lib/acg/`) and its git remote — fully absorbed into lib-foundation

## [1.7.0] - 2026-06-13

### Added
- `k3s-hostinger` cluster provider — single-node k3s app cluster on a permanent Hostinger KVM VPS via SSH/k3sup (no VM lifecycle); env-overridable `HOSTINGER_HOST` default via `scripts/etc/hostinger/vars.sh`
- `k3s-hostinger` app cluster registration with the hub ArgoCD via mTLS cluster secret (`cluster-ubuntu-hostinger` in `cicd`)
- `bin/hostinger-status` — read-only full status report (app nodes/pods, API health, hub ArgoCD registration, ArgoCD apps/applicationsets); wired into `make status CLUSTER_PROVIDER=k3s-hostinger`
- `APP_CLUSTER_NAME` envsubst parameter for ApplicationSet destination (default `ubuntu-hostinger`) — retargets shopping-cart + observability workloads off the retired ACG `ubuntu-k3s` cluster

### Fixed
- `k3s-hostinger` make `up` arm passes `--confirm` so the deploy gate accepts non-interactive provision
- `k3s-hostinger` provider sources `shopping_cart.sh` for `_ensure_k3sup`; resolves host to IP for k3sup load
- `k3s-hostinger` remote sudo written via a single `_run_command` line (de-obfuscate the bare-sudo guard)

## [1.6.5] - 2026-06-13

### Added
- `k3s-az` Azure provider — VM provision, k3sup install, and shopping-cart deploy; wired into `bin/acg-up` and `bin/acg-down`
- Optional `provider` argument for `/acg-up`, `/acg-down`, and `/acg-resume` Slack commands
- Provider-aware `make refresh` / `make status` / `acg-refresh` / `acg-status` — active provider is recorded at provision time (state file primary, kube-context probe fallback, explicit env override) so Azure/GCP clusters no longer fall through to AWS defaults

### Fixed
- Slack relay accepts `az` as the canonical provider token (with `azure` alias) for `/acg-up` and `/acg-resume`
- SSH: non-interactive host keys in shopping-cart deploy + known_hosts prune during `acg-up` preflight
- shopping-cart cross-cluster deploy: poll for data-layer StatefulSet presence instead of one-shot check; re-login ArgoCD before cluster add; purge stale default cluster/user before kubeconfig flatten; resolve SSH alias to IP; copy k3s kubeconfig to user home for sudo-free re-export; wait for product-catalog-seed job deletion before re-apply; default SSH user to `ubuntu`
- `acg-up` Azure path: gate `az group list` behind `_az_ok` (no spurious device-code auth); require non-empty resource group in the fast-path so stale creds don't skip extraction; guard `KV_NAME` in `azure-vars.sh`; extract Azure creds in Step 1 via `acg-credential-test`
- `acg-up` OrbStack/Docker preflight: recover a stopped OrbStack VM via `orbctl start`; dismiss OrbStack update dialogs; kill stale Vault port-forward via `lsof` before rebind
- `azure.sh` no longer sources `azure-vars.sh` at top level — `az ad app create` no longer runs on every plugin load
- Webhook skips `ask` sub-jobs in `_find_job_by_thread_ts` so Codex no longer repeats prior answers

### Changed
- lib-acg subtree synced to v0.1.7 (PR #44) — Azure SP/CLI-first credential validation, extend/restart hardening
- lib-foundation subtree synced — extensible cluster-provider hook (PR #30)

## [1.6.4] - 2026-06-10

### Added
- Slack Events API text commands — `acg-status`, `acg-refresh`, `ask`, `claude`, `gemini`, `codex` now work from thread replies and top-level channel messages via Events API; slash commands continue to work as before
- Slack thread context for text commands — orphan threads create anchor jobs so replies stay threaded
- Prometheus observability stack: Pushgateway deployment metrics, Grafana dashboard with k3d tag, non-interactive auth bootstrap in webhook startup
- `make show-service-passwords` target — display all basic-auth credentials including Prometheus admin user
- ACG screenshot archival — restart failure screenshots now captured and archived to `~/.local/share/k3d-manager/screenshots/`

### Fixed
- `/claude`, `/gemini`, and `/codex` agent prompts now keep raw probe commands and verbose kubectl output out of the Slack `ANSWER:` while preserving concise diagnostic conclusions
- Pushgateway deployment metrics now retry briefly before skipping so transient Pushgateway readiness gaps do not drop the last deployment sample
- Remove remaining fork-based subprocess calls from webhook job execution — all subprocess calls now use `posix_spawn` for NEF safety
- Webhook logs command falls back to output file for acg-up jobs when logs directory is unavailable

### Changed
- lib-acg subtree synced to v0.1.4 — Azure SP/CLI-first credential validation, screenshot archival support, sandbox retry hardening

## [1.6.3] - 2026-06-07

### Added
- `/acg-resume` Slack command — checkpoint-based pipeline re-entry for interrupted ACG provisioning workflows
- `/ask` Slack command — multi-agent troubleshooting with Claude, Gemini, and Codex from job thread replies
- `make fix-*` agent fix targets — named, discoverable cluster recovery operations for agent fix mode
- Webhook Slack thread context injection — fetch thread history and inject into agent prompts for better context
- Gemini side-observation bug filing — structured OBSERVATIONS block in sandbox for automatic issue creation
- Webhook read-only bash sandbox for `/ask` agents — deny destructive kubectl/helm/rm commands
- Webhook prompt injection guard and structural system/user separation for `/ask` agents
- Webhook semaphore and timeout protection for ask jobs (5 max turns, 300s timeout)
- Webhook job context prepend injection from parent job output tail (reduce wasted turns)
- Keycloak group-ldap-mapper reconciliation during reprovisioning

### Fixed
- NEF atfork SIGSEGV: replace all post-NEF subprocess.run calls with `os.posix_spawn` for job execution, `/ask claude`, `/ask codex`
- Replace subprocess kubeconfig parse with file-based parser (no fork) to avoid NEF child crashes
- Move k8s API context initialization to webhook startup to avoid macOS NEF atfork SIGSEGV
- Use `shlex.quote()` not `shutil.quote()` in webhook job execution
- Add data-layer StatefulSet readiness check to post-provision smoke test
- Always run post-provision smoke test unconditionally (remove ArgoCD early-return gate); add reconciliation note when hub is down but services are up
- Demote data-layer sync timeout to warning when StatefulSets are already Ready (skip wait on ubuntu-k3s refresh)
- Skip data-layer sync wait when StatefulSets already ready on ubuntu-k3s
- Remove ArgoCD port-forward unload from EXIT trap in acg-up
- Fix Gemini NEF fork bug and Keycloak port 18080 conflict
- Keycloak port-forward now kills existing listener before starting (fixes port conflict on resume)
- ArgoCD controller reconnection wait before data-layer sync (ensure ArgoCD is ready on ubuntu-k3s)
- Suppress Gemini CLI startup warnings at source
- Strip Gemini CLI Warning banners from failure analysis output
- Webhook diagnosis fallback to output file for acg-resume jobs
- Webhook ask-agent sanitize (sanitize user question before job context prepend to fix ask-agent rejection)
- `/tmp` file leaks from install-sudoers, k3s-oci-storage, and session teardown (add EXIT traps)
- Remove invalid cwd kwarg from posix_spawn Gemini call
- Add 5-attempt retry loop with 15s sleeps for Keycloak admin token fetch during ACG provision
- Auto-reinstall missing system daemon plists (argocd-browser-https, keycloak-browser-http, frontend-browser-http) on acg-refresh
- Auto-install ACG npm dependencies when node_modules missing in acg-up/acg-refresh
- Patch CoreDNS NodeHosts ConfigMap with host.k3d.internal before restart in acg-refresh
- Refresh ArgoCD cluster secret with host.k3d.internal on each sandbox rotation
- Restore ubuntu-k3s kubeconfig on resume with targeted Slack advice
- Auto force-sync data-layer on ArgoCD sync timeout before failing
- Retry kubeconfig fetch on SSH delay in acg-up
- ACG credentials: click "Extend Session" button (not Cancel) on session-extension dialog
- Keycloak group-ldap-mapper reconciliation persists across reprovisioning
- Install sudoers script — use `--interactive-sudo` + NOPASSWD rules for safe self-update
- k3s-aws idempotency — skip `deploy_app_cluster` when nodes already Ready

### Changed
- Webhook output — visual diagnosis via Gemini CLI with Playwright failure screenshots
- Webhook failure analysis — enrich with live pod and ArgoCD app state + node state distinction
- Observability: prune ~40 noisy kube-prometheus-stack default alert rules; enable Grafana on ACG cluster
- Prometheus 2Gi memory limit + narrow federation scope
- Keycloak port-forward now bypasses Istio sidecar for reliability
- Health check curl timeout increased from 35s to 90s (cover full smoke test duration)
- Make `/ask` max-turns adjustable via `K3DM_ASK_MAX_TURNS` env var and `turns=N` inline token

## [1.6.2] - 2026-06-05

### Added
- `/acg-refresh` Slack slash command — routes through `workers/slack-relay` → `bin/k3dm-webhook` → `bin/acg-refresh` for on-demand credential and SSH tunnel refresh from Slack

### Fixed
- `bin/acg-refresh` now removes pre-auth sudo block for headless webhook execution (no TTY in Cloudflare Worker)
- `bin/acg-refresh` makes summary `kubectl get nodes` non-fatal (webhook has no `ubuntu-k3s` kubeconfig context)
- `bin/acg-up` adds 5-attempt retry loop with 15s sleeps for Keycloak admin token fetch to handle slow startup during provision

## [1.6.1] - 2026-06-05

### Fixed
- `bin/acg-refresh` now auto-reinstalls missing system daemon plists (`argocd-browser-https`, `keycloak-browser-http`, `frontend-browser-http`) from their wrapper scripts when detected missing on refresh — prevents dark ports 80/443/8880 after partial `acg-up` failures
- `bin/acg-refresh` regenerates Keycloak port-forward LaunchAgent plist when missing on refresh
- `bin/acg-refresh` waits for SSH tunnel port to be ready before proceeding after launchctl restart
- `bin/acg-refresh` skips sudo pre-auth prompt when credentials already cached, improving UX on repeated runs
- `bin/acg-up` installs Vault port-forward LaunchAgent (`com.k3d-manager.vault-port-forward`) during provisioning and keeps port 18200 alive across cluster restarts
- `bin/acg-up` adds `RunAtLoad` and generator script to all LaunchAgent plists for reliability
- `/acg-status` now displays caveat labels for stale ArgoCD display when ACG cluster unreachable
- Prometheus `web.config.file` additionalArg conflict with prometheus-operator v0.79.2 fixed (removed arg)

## [1.6.0] - 2026-06-04

### Added
- Webhook Slack threading — all job notifications grouped into a single thread with thread-aware replies
- Slack thread commands — `/kill`, `/diagnosis`, `/status`, `/logs` commands reply directly in job thread
- ArgoCD CVE scan CronJob (bi-weekly, Hub cluster) — direct kubectl invocation, no webhook dependency
- ArgoCD upgrade pipeline notifications via SendGrid + PagerDuty integration
- Cloudflare Worker deploy workflow — `bin/k3dm-worker-setup` and `make deploy-worker` for slash command relay deployment
- AI-powered failure analysis on webhook job failures — Gemini triage + visual diagnosis (Claude vision on Playwright screenshots)
- Post-provision health check — Claude Haiku AI triage of degraded apps after `acg-up`
- Webhook token auto-rotation every 6 hours via LaunchAgent — `bin/rotate-webhook-token` keeps token in sync with Cloudflare Worker
- Stall detection for long-running ACG jobs — AI analysis + automatic kill action with Slack notification
- Python 3.13 interpreter in webhook plist template — fixes SIGSEGV on macOS 26.5.1 Beta

### Fixed
- Slack slash command Request URLs now point to `https://k3dm-slack-relay.k3dm.workers.dev` (Cloudflare Worker relay with auth) instead of direct tunnel endpoint — fixes 401 errors and prevents auth bypass
- Webhook restart-orphan handling — notify Slack when a restart kills a running job
- Webhook e2e token verification on rotation — verify new token before committing to Keychain
- Webhook SSH tunnel check before remote kubectl in failure analysis — prevents hung diagnosis waits
- Webhook TimeoutExpired exception handling — catch separately to prevent prompt leak in Slack message
- k3s-aws idempotency — skip `deploy_app_cluster` when nodes already Ready
- Keycloak group-ldap-mapper reconciliation — LDAP group sync persists across reprovisioning
- Install sudoers script — use `--interactive-sudo` + `NOPASSWD` rules for safe self-update

### Changed
- Webhook output — visual diagnosis via Gemini CLI with Playwright failure screenshots
- Webhook failure analysis — enrich with live pod and ArgoCD app state + node state distinction (cluster vs app failure)

## [1.5.3] - 2026-06-01

### Added
- ACG Alertmanager: NodePort 30093, Vault-backed SMTP secret integration, email alert routing

### Changed
- Observability: prune ~40 noisy kube-prometheus-stack default alert rules not applicable to k3s (apiserver SLO burn-rates, alertmanager HA, config-reloaders); enable Grafana on ACG cluster (NodePort 30030)
- README: add Trivy Operator to architecture diagram
- Shopping Cart: increase MinIO rollout timeout 120s→300s for slow container registry pulls

### Fixed
- ACG credentials: click "Extend Session" button (not Cancel) on session-extension dialog, preserving the once-per-session session-extension opportunity

## [1.5.1] - 2026-05-31

### Added
- OCI object storage backup/restore: `oci_backup` and `oci_restore` commands for k3s-oci provider — auto-backup after deploy, Makefile `backup` and `restore` targets
- ACG credential automation: auto-launch Chrome CDP, handle session-expired redirects; open sign-in page for manual completion when CAPTCHA is required

### Fixed
- Fix Python one-liner quoting in `cloudflared-backup` and `alertmanager-secret` Makefile targets — replace double-quoted `-c` arg and positional `sys.argv` with single-quoted `-c` and env-var injection to prevent shell brace expansion
- BATS observability tests: fix `>>` stub in `test_deploy_observability` (append to log instead of overwrite)
- `bin/acg-up`: make System Keychain cert trust non-fatal (warn on permission error instead of aborting)
- ACG credential automation: handle session-expired login redirects, navigate to signin page on 404/off-site redirect
- ACG credential automation: click sign-in button and navigate to sign-in form; user completes CAPTCHA manually when required
- `k3s-oci-storage`: replace hex-encoded sudo with named `_OCI_SSH_SUDO` variable for clarity

### Changed
- `Makefile`: add `trivy-scan-report` alias for `vuln-scan` target

## [1.5.0] - 2026-05-31

### Added
- `CLUSTER_PROVIDER=k3s-oci`: new OCI Always Free provider — single-node ARM64 k3s cluster on Oracle Cloud (2OCPU/12GB); Cilium CNI; Cloudflare Tunnel ingress
- `CLUSTER_PROVIDER=k3s-oci` two-node cluster: server + agent (4OCPU/24GB total); automated agent wait loop in BATS coverage
- `scripts/plugins/observability.sh`: deploy Prometheus+Grafana+Trivy to Hub k3d via ArgoCD ApplicationSet; Alertmanager with email-to-SMS via Vault-backed config
- `scripts/etc/prometheus/rules/shopping-cart-apps.yaml`: PrometheusRule CRDs (ServiceDown, PodCrashLooping, HighErrorRate)
- `scripts/etc/prometheus/alertmanager.yaml.tmpl`: envsubst-rendered Alertmanager config template
- `scripts/etc/observability/istio.yaml`: Istio Gateway + VirtualServices for prometheus.3ai-talk.org and grafana.3ai-talk.org
- `Makefile`: `observability`, `observability-acg`, `observability-status`, `vuln-scan`, `show-service-passwords`, `alertmanager-secret`, `cloudflared-backup` targets
- `bin/acg-up`: check sandbox TTL before provisioning and extend if below threshold
- `bin/acg-up`: patch CoreDNS NodeHosts instead of injecting a duplicate hosts block into CoreDNS Corefile
- `bin/acg-up`: generate cloudflared config from template and add keycloak to the Cloudflare tunnel
- `docs/bugs/` entries for OIDC issuer mismatch in product-catalog and payment services
- `bin/acg-up`: add prometheus/grafana URLs to public URL summary after `make up`
- `feat/cloudflared`: persist tunnel config to repo + restore credentials from Keychain on Hub rebuild; auto-sync credentials Keychain→Vault

### Changed
- Pull lib-acg v0.3.0 subtree with `ACG_CLUSTER_TEMPLATE` env var support for CloudFormation template path
- `scripts/etc/observability/`: rename observability DNS from `shopping-cart.local` to `3ai-talk.org`
- `scripts/plugins/observability.sh`: replace Alertmanager heredoc + hardcoded PrometheusRule with template files under `scripts/etc/prometheus/`

### Fixed
- `scripts/plugins/observability.sh`: subshell guard on `_kubectl get application` check — `_err()` calls `exit 1` not `return 1`; wrapping in `( )` prevents script abort on missing app
- `scripts/plugins/observability.sh`: silence Python traceback when Vault alertmanager secret not yet configured
- `scripts/plugins/observability.sh`: raise ACG Prometheus memory limit 256Mi→512Mi (OOMKilled)
- `scripts/plugins/observability.sh`: raise trivy scan job memory limit to 512Mi (OOMKilled)
- `Makefile`: add missing observability + credentials targets to `make help` output
- `bin/acg-up`: replace broken 40-retry credential wait loop with delegation to `acg-credential-test`, which has proper ghost-state detection and STS validation with restart capability
- `scripts/lib/acg/bin/acg-credential-test`: fix stderr swallowing — Playwright INFO/WARN/ERROR messages now reach terminal instead of being silently redirected to tmpfile
- `scripts/lib/acg/playwright/acg_credentials.js`: add `page.evaluate` fallback in `_waitForCredentials` when React-managed inputs return empty from `inputValue()` after CDP reconnect
- `scripts/lib/acg/scripts/etc/acg-cluster.yaml`: restore CloudFormation template removed from lib-acg in v0.2.0 without updating reference — broke `make up` with `Invalid template path`
- `scripts/etc/agent/hardcoded-ip-allowlist`: add subtree copy of `acg-cluster.yaml` to bypass IP literal check for CloudFormation CIDR blocks
- ArgoCD OIDC issuer: update to `keycloak.3ai-talk.org` in Helm values template
- `bin/acg-refresh`: non-fatal launchd bootstrap + kill orphans before bootstrap
- `bin/acg-refresh`: manage all port-forward services (PID + launchd)

## [1.4.12] - 2026-05-29

### Fixed
- `scripts/plugins/services.sh`: add imagePullSecrets patch to all named ServiceAccounts during cluster bootstrap — resolves ghcr.io 401 errors when non-default SAs pull images

### Added
- `Makefile`: `sync-branch` and `sync-main` targets for pre-merge ArgoCD branch verification
- `make status`: new ArgoCD ApplicationSets section (ArgoCD v3.4.2 removed UI sidebar — CLI is now the primary status view)

### Changed
- `services/shopping-cart-payment/kustomization.yaml`: remove redundant `payment-db-credentials-eso` ExternalSecret to fix SharedResourceWarning; sole ownership assigned to cicd/product-catalog app in shopping-cart-infra

## [1.4.11] - 2026-05-29

### Fixed
- `scripts/plugins/shopping_cart.sh`: annotate all ExternalSecrets before waiting to prevent ESO controller saturation on fresh clusters
- `scripts/plugins/shopping_cart.sh`: poll for StatefulSet existence before `kubectl rollout status` to fix data-layer race on fresh clusters
- `scripts/plugins/shopping_cart.sh`: add explicit `|| return 1` on `kubectl wait` and `|| _warn` on `kubectl annotate` — silent continuation on timeout was a reliability bug
- `bin/acg-down`: replace `--interactive-sudo` with `--prefer-sudo` on all LaunchDaemon teardown calls — eliminates `Password:` prompt and PTY allocation error on macOS Tahoe
- `bin/acg-up`: add Keycloak group-ldap-mapper reconciliation step — LDAP group sync now persists across reprovisioning
- ArgoCD RBAC: correct `catalog-admin` policy to reference `shopping-cart/shopping-cart-product-catalog` (was `shopping-cart/product-catalog`)
- `bin/acg-down`: move sudo pre-warm to top of script — prompt before any output to improve UX
- `services/shopping-cart-payment/kustomization.yaml`: remove redundant `payment-db-credentials-eso` ExternalSecret — `postgres-payment-app` (shopping-cart-infra) already owns the secret; k3d-manager ESO caused `SecretSyncedError` due to ownership conflict
- `bin/acg-up`: replace broken 40-retry credential wait loop with delegation to `acg-credential-test`
- `scripts/lib/acg/bin/acg-credential-test`: fix stderr swallowing — Playwright messages silently redirected to tmpfile
- `scripts/lib/acg/playwright/acg_credentials.js`: add `page.evaluate` fallback in `_waitForCredentials` after CDP reconnect
- `scripts/lib/acg/scripts/etc/acg-cluster.yaml`: restore CloudFormation template removed from lib-acg in v0.2.0 — broke `make up` with `Invalid template path`
- `scripts/etc/agent/hardcoded-ip-allowlist`: add subtree copy of `acg-cluster.yaml` to bypass IP literal check
- ArgoCD OIDC issuer: update to `keycloak.3ai-talk.org` in Helm values template
- `scripts/etc/argocd/applicationsets/services-git.yaml`: assign shopping-cart apps to `shopping-cart` ArgoCD project
- `bin/acg-down`: remove stale `/tmp/argocd-*.sock`, `/tmp/k3d-config-tmp-*.yaml`, `/tmp/k3d-hostsfile-*` on teardown
- `scripts/plugins/shopping_cart.sh`: add `--wait=false` to seed job delete — ArgoCD hook finalizer blocked `kubectl delete` indefinitely
- `bin/acg-up`: resilient DB password reconciliation — re-aligns Vault KV and PostgreSQL auth on every run
- `bin/acg-up`: reconcile order-service postgres password after sandbox seed
- `bin/acg-up`: sync vault-backed data-layer ExternalSecrets and MinIO on every run
- `scripts/etc/argocd/applicationsets/services-git.yaml`: add `ignoreDifferences` for `order-service-secrets` and `product-catalog-seed-script` labels

### Changed
- Pull lib-acg v0.3.0 subtree with `ACG_CLUSTER_TEMPLATE` env var support for CloudFormation template path
- `services/shopping-cart-*/kustomization.yaml`: move imagePullSecrets from per-app patches to `default` ServiceAccount in `shopping-cart-apps`
- `bin/acg-up`: extract shopping-cart bootstrap logic into `scripts/plugins/shopping_cart.sh`

### Added
- `bin/acg-up`: check sandbox TTL before provisioning and extend if below threshold
- `bin/acg-up`: patch CoreDNS NodeHosts instead of injecting a duplicate hosts block into CoreDNS Corefile
- `bin/acg-up`: generate cloudflared config from template and add keycloak to the Cloudflare tunnel
- `docs/bugs/` entries for OIDC issuer mismatch in product-catalog and payment services

## [1.4.8] - 2026-05-19

### Fixed
- `scripts/plugins/vault.sh`: register cleanup traps immediately after mktemp to prevent temp file leaks on error paths
- `scripts/lib/acg/playwright/acg_extend.js`: disconnect CDP browser connection on exit to prevent WebSocket hang and node process leak
- `bin/acg-up`: set Keycloak frontendUrl to Cloudflare public domain after realm import (fixes redirect loops from non-public domain)
- `bin/acg-up`: replace trycloudflare quick tunnels with named Cloudflare tunnel for stable public URLs across cluster restarts
- `bin/acg-up`: correct realm JSON path from identity/config to identity/keycloak in import payload
- `bin/acg-refresh`: restart Cloudflare tunnel on refresh to clear stale tunnel routes

### Changed
- `bin/acg-refresh`: drop unused SCRIPT_DIR variable

### Added
- `bin/get-keycloak-password`: new script to query Keycloak SSO user passwords from Vault

## [1.4.5] - 2026-05-10

### Added
- ACG AWS sandbox provisioning (`acg_provision`, `acg_extend`, `acg_teardown`)
- LoadBalancer ingress for ArgoCD, Keycloak, Jenkins
- Plugin architecture with lazy loading

### Fixed
- Vault PKI bootstrap on cluster up

## [1.4.0] - 2026-05-01

### Added
- Initial release
