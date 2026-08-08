# Active Context — k3d-manager

> **Compressed 2026-08-07.** This file holds only the *live* focus + carried-forward
> blockers. Completed-work detail lives in `CHANGELOG.md`, `docs/retro/`, `docs/issues/`,
> `docs/plans/release-split-intent-map.md`, and git history (pre-compression versions of
> this file are recoverable via `git log --follow memory-bank/activeContext.md`).

## Current focus — v1.23.0 CVE observability + remediation lifecycle (workstreams B+C)

- **Branch cut fresh off main (`1bbb74b0`).** `origin/k3d-manager-v1.23.0` was 50 commits
  diverged (merge-base at v1.20.0), predating the v1.21.0 + v1.22.0 squash-merges and carrying
  a duplicate OpenLDAP commit (`b30f7898`) plus superseded verbose memory-bank state. Re-cut
  clean (same playbook as v1.22.0): old branch archived intact at
  `origin/archive/k3d-manager-v1.23.0-integration` (`48148c0d`); only the two genuinely-new
  artifacts carried forward — the CVE dashboard spec and the v1.22.0 retro (commit `f7105dc5`).
  ⚠️ The re-cut still needs a **`--force-with-lease`** to replace the diverged remote branch
  (hard-blocked in this env → user runs it). Nothing lost — verified via tree diff before archive.
- **Spec:** `docs/plans/v1.23.0-cve-autopatch-dashboard-observability.md` — make the CVE
  Auto-Patch Grafana dashboard show *what* and *where* (namespace/image/CVE/remediation target),
  not just aggregate counts. Three parts: (a) dashboard query change (no cluster reconfig);
  (b) enable `trivy_vulnerability_id` export + CVE-ID table panel; (c) label `cve-auto-*` Jobs
  with their target + allowlist in kube-state-metrics + remediation-by-target panel. Parts (b)/(c)
  have runtime-label names confirmable only *after* config applies.
- **Carried blockers (from the integration split):**
  - Apply CVE dashboard v18 live (Hub tunnel `127.0.0.1:57780`).
  - Close out payment `manual_review` digest-mismatch event (verify or document as expected).
  - `observability.sh` needs a per-hunk split from workstream E (E lands in v1.24.0).
  - Carries `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`.
  - **Bitnami image removed (found 2026-08-07 post-OrbStack-restart).** `docker.io/bitnami/kubectl`
    is GONE from Docker Hub (Aug 2025 catalog migration) → `ImagePullBackOff`. Two consumers, both
    re-pin to `docker.io/alpine/k8s:1.31.4` (already used pinned by `grafana-credential-rotator`;
    drop-in — both invoke `command: ["sh", <script>]`, no entrypoint dep):
    - **On-branch (bugfix spec written):** `scripts/etc/ldap/vars.sh:99` `LDAP_ROTATOR_IMAGE`.
      Spec `docs/bugs/v1.23.0-bugfix-bitnami-kubectl-image-removed.md`. Handed to Codex.
- **Off-branch carry-forward gap:** live `cve-remediation-verify` CronJob + its script + RBAC +
      `argocd.sh` wiring exist ONLY on `archive/k3d-manager-v1.22.0-integration` (workstream-C gap in
      the v1.23.0 re-cut). Re-pin to alpine/k8s when the verify job is carried forward. Interim:
      delete the orphaned live cronjob (v1.23.0 won't recreate it).

## LDAP rotator image re-pin complete — 2026-08-07

Fix commit `ddc68c90` re-pins `LDAP_ROTATOR_IMAGE` in `scripts/etc/ldap/vars.sh` from the
removed floating `docker.io/bitnami/kubectl:latest` image to the maintained pinned
`docker.io/alpine/k8s:1.31.4`. The file-scoped grep and shellcheck gates passed and the fix is
pushed to `origin/k3d-manager-v1.23.0`. The live `cve-remediation-verify` carry-forward gap
remains explicitly out of scope and Claude-owned.

## CVE remediation verifier carry-forward complete — 2026-08-08

Fix commit `33b151ba` restores the archive's `cve-remediation-verify` CronJob document and
verifier script onto `k3d-manager-v1.23.0`, re-pins its image to
`docker.io/alpine/k8s:1.31.4`, and wires the verifier ConfigMap into `deploy_argocd_platform_ops`.
The YAML, shellcheck, grep, BATS, and `_agent_audit` gates passed; the fix is pushed to
`origin/k3d-manager-v1.23.0`.

### Live follow-ons executed — 2026-08-08
- **Observability values-branch drift FIXED + verified.** All 6 apps (acg-kube-prometheus-stack,
  acg-trivy-operator, hub-loki, kube-prometheus-stack, loki, trivy-operator) were pinned to
  `k3d-manager-v1.22.0`. Reapplied `observability.yaml` + `observability-acg.yaml` in ns `cicd`
  with `K3D_MANAGER_BRANCH=k3d-manager-v1.23.0` / `APP_CLUSTER_NAME=ubuntu-hostinger`; all 6 now
  reference v1.23.0. Confirmed by `argocd_check_values_branch` ("All Applications reference values
  branch k3d-manager-v1.23.0"). NOTE: hub ArgoCD namespace is **`cicd`**, not `argocd`.
- **7 `manual_review` root cause was NOT missing source.** `minReadySeconds: 10` is already in all
  3 shopping-cart repos' `main` (since 2026-08-05). Live lagged because the k3d-manager service
  Apps are frozen at v1.22.0 and ArgoCD cached the remote base (`?ref=main`). Fix = hard-refresh
  (`argocd.argoproj.io/refresh=hard`) the 3 `ubuntu-hostinger-shopping-cart-{order,payment,
  product-catalog}` Apps. All 3 live Deployments now report `minReadySeconds: 10` (order-service &
  product-catalog in `shopping-cart-apps`, payment-service in `shopping-cart-payment`). Corrected
  diagnosis recorded in `docs/bugs/v1.23.0-bugfix-cve-remediation-verify-carry-forward.md` Part 2.
- **STILL real (do NOT auto-force):** payment app `Degraded`; order `ready_pod_digest_mismatch`
  (patched image requested but old pod running).

### TrivyCritical empty-app alert — bug filed + QUEUED (Codex) — 2026-08-08
Recurring Slack page `TrivyCriticalVulnerabilityDetected — ''` (empty app). Live-diagnosed: the rule
sets `app: {{ $labels.image_repository }}`, so empty app == empty `image_repository`, emitted by the
custom `vulnerability-inventory-exporter` from `report.artifact.repository`. Transient VulnerabilityReports
for ephemeral job pods (cve-auto/cve-remediation-verify/acg-expiry-check/scan-vulnerabilityreport) can
have an empty `artifact.repository`; with a CRITICAL finding + `for:15m` it pages with an unactionable
empty name. The notification's own auto-diagnosis was WRONG (claimed missing pod app-label; actual =
image_repository) and its TTL fix is only hygiene, not a root fix. Spec
`docs/bugs/v1.23.0-bugfix-trivy-critical-empty-image-repository-alert.md`: (1) alert selector gains
`image_repository!=""`; (2) exporter skips empty-`repository` reports (hub + app loops). Commit
`fix(observability): stop TrivyCritical alert firing on empty image_repository`. SEPARATE commit from
Grafana. Live reapply (PrometheusRule + exporter ConfigMap + pod restart) is Claude-owned post-commit.
Aside noted (out of scope): every alert groups `namespace=platform-ops` (Prometheus overwrites the
exporter's namespace with the scrape target's; real ns is `exported_namespace`).

### Grafana rotation DB-apply + hub-scope smoke — bundled spec READY (Codex handoff) — 2026-08-08
Task #11. Live-diagnosed the `make status` "Grafana login: HTTP 401": it is a **false-red** — hub
login at `grafana.3ai-talk.org` with `grafana-admin-credentials` returns **200**; the smoke
(`bin/k3dm-webhook:1769-1774`) reads the password from `acg-kube-prometheus-stack-grafana` on the
**hostinger** context (wrong cluster) → 401. Root defect #1: the monthly rotator only
`rollout restart`s Grafana, which never rewrites its sqlite DB, so the rotated password 401s until
manually reset. User chose **both fixes bundled** on v1.23.0. Spec
`docs/bugs/v1.23.0-bugfix-grafana-rotation-db-not-applied.md` rewritten with live-verified exact
blocks: Fix 1 = add `pods`/`pods/exec` Role rules + `grafana cli admin reset-admin-password
--password-from-stdin` (Grafana 11.4.0, homepath `/usr/share/grafana`; deployment-form exec exit 0,
login 200 — verified live) after ESO sync in `grafana-credential-rotator.yaml`; Fix 2 = smoke reads
`grafana-admin-credentials` on hub context. **Dropped** the original `observability.sh` convergence
file (grafana deploys async via ArgoCD, no synchronous hook; fresh deploy provisions DB from secret,
no drift). Gates: yamllint + py_compile + `make restart-webhook`; LIVE-VERIFY (manual rotation →
login 200 → status GREEN) is Claude-owned post-commit. Commit: `fix(observability): apply rotated
Grafana admin password to DB + hub-scope status smoke`. Handed to Codex; SHA pending.

### Grafana rotation + Trivy empty-repository fixes complete — 2026-08-08

Task A commit `816835fd` adds namespace-scoped Grafana pod/exec RBAC, applies the rotated
password to Grafana's DB via stdin, and changes the webhook smoke to the hub credential secret.
Task B commit `5302ea54` excludes empty `image_repository` from the critical alert and skips
empty-repository reports in both exporter loops. YAML parsing, embedded exporter compilation,
Python compilation, and `_agent_audit` passed; both commits are pushed to
`origin/k3d-manager-v1.23.0`. Default yamllint still reports pre-existing line-length violations
in these legacy YAML files; no unrelated formatting was changed. `observability.sh` remains
dropped. Claude owns the live Grafana rotation and Trivy reapply verification.

**Live cutover + verification (Claude, 2026-08-08):** both commits independently verified on
`origin` (SHAs, exact messages, exact-scope diffs, separate memory commit `5c48f087`).
- **Trivy — DONE + verified.** Reapplied `cicd/argocd-degraded` PrometheusRule (Prometheus reloaded
  it: `image_repository!=""` present) + exporter ConfigMap; restarted the exporter. Live: **46**
  active TrivyCritical alerts, **0 empty-app**; exporter emits **4870** series, **0** with empty
  `image_repository`. Two-layer guard live.
- **Grafana Fix 2 (hub-scope smoke) — DONE + verified GREEN.** `make status` → `✅ Grafana login:
  HTTP 200`; direct hub login with `grafana-admin-credentials` → 200. False-red gone. Webhook restarted.
- **Grafana Fix 1 (DB-apply on rotation) — code correct but INERT (blocked).** Discovered the
  rotator pod has **never been able to start**: pod `securityContext` sets `runAsNonRoot: true` with
  no `runAsUser`, and `alpine/k8s` runs as root → `CreateContainerConfigError` (pre-existing since
  the rotator's creation `5b418dd7`; NOT a Codex defect). Live-verified the fix: a clone with
  `runAsUser: 65534`+`runAsGroup: 65534` starts, execs into Grafana, runs
  `reset-admin-password --password-from-stdin` → rc 0, login stays 200. Codex's Fix 1 command form
  is correct; it just can't run until the securityContext is fixed. Reframes the original "401 after
  rotation": no scheduled rotation ever ran — the 401 was DB drift from the `5b418dd7` Vault-sourcing
  cutover (stopgap already repaired live DB). **Follow-up bug filed + QUEUED:**
  `docs/bugs/v1.23.0-bugfix-grafana-rotator-runasnonroot-cannot-start.md` (add `runAsUser: 65534` +
  `runAsGroup: 65534`; commit `fix(observability): let Grafana rotator pod start as non-root
  (runAsUser)`). Post-fix, Claude runs the manual-rotation LIVE-VERIFY.
- **runAsNonRoot fix APPLIED + committed `a66463e1`** (2026-08-08) — Claude applied directly,
  pushed+verified on origin. Live-applied the rotator; CronJob now carries
  `runAsUser/runAsGroup: 65534`. Manual `rotate-verify` job **started as uid 65534** —
  `CreateContainerConfigError` GONE, so this blocker is fixed and confirmed.
- **3rd latent blocker uncovered — `openssl: not found`.** With the pod now starting, the rotator
  aborts at line 109 `new="$(openssl rand -hex 24)"`: `alpine/k8s:1.31.4` ships **no openssl**
  (`command -v openssl` → MISSING; verified live, uid 65534). `set -eu` aborts before any rotation;
  `restore` trap fires. Only the Grafana rotator uses openssl (`grep -rn openssl scripts/etc/argocd/`
  = 1 hit); LDAP rotator unaffected. Portable replacement live-verified in-image:
  `head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n'` → 48 lowercase-hex chars (== `openssl rand
  -hex 24`). **Bug filed `7e857fbb`; fix committed `4557cdeb`** (`fix(observability): generate
  Grafana rotator password without openssl`).
- **4th latent blocker — `rollout status` RBAC.** With openssl fixed, the pod reached line 122
  `kubectl rollout status deployment/kube-prometheus-stack-grafana` and looped on
  `cannot list resource "deployments"` until timeout. `rollout status` uses a ListWatch informer →
  needs `deployments` **list+watch** at collection scope; the Role only had name-scoped `get`/`patch`.
  **RBAC subtlety:** `resourceNames` is ignored for `list`/`watch` (collection verbs), so the fix is a
  **separate verbs-only rule** (`list`,`watch`) alongside the name-scoped get/patch — least privilege
  preserved, namespace-scoped Role. `rollout restart` had worked because it uses get+patch.
  **Bug filed `52493b04`; fix committed `a0bb46c2`** (`fix(observability): grant Grafana rotator
  deployments list/watch for rollout status`).
- **✅ ROTATOR NOW RUNS END-TO-END (first time ever) — LIVE-VERIFIED 2026-08-08.** Manual
  `rotate-verify` Job → **`Complete`** (1/1, 21s), clean logs, stored password fingerprint changed
  (real rotation: Vault write → ESO force-sync → k8s secret → Grafana DB reset). Login with the
  newly-rotated secret: in-pod `POST /login` → 200 `{"message":"Logged in"}`; external
  `grafana.3ai-talk.org` → 200 (one transient 502 during the Grafana restart, recovered on retry);
  `make status` → `✅ Grafana login: HTTP 200`. Empirically confirms the Vault write path (policy
  `grafana-rotation` = create/read/update, vault.sh:2116) + the DB-apply exec. **All four latent
  rotator blockers (runAsNonRoot → openssl → rollout-status RBAC, plus Codex's DB-apply) resolved;
  Grafana Fix 1 is no longer inert — the monthly rotation will self-heal.** Live rotator manifest
  applied on the hub (matches git `a0bb46c2`).

### Webhook request-hardening bugfix specced — 2026-08-08 (Codex handoff)
Spec `docs/bugs/v1.23.0-bugfix-webhook-ratelimit-order-and-content-length.md` (from a security
report on `bin/k3dm-webhook`). Two findings: (1) `_rate_limited` runs BEFORE auth in do_POST/do_GET
— a single global bucket per channel means an unauthenticated flood 429s the one legit caller; fix
= move limiter after signature/token check (NOT re-key by IP/actor — server binds 127.0.0.1 behind
the tunnel so source IP is always localhost and `X-K3DM-Actor` is spoofable). (2) bare
`int(Content-Length)` at two POST sites throws on non-numeric header → fix = `_content_length`
guard → 400. Adds `scripts/tests/bin/webhook_request_hardening.py`. Gates: py_compile + the new
test + `bin/smoke-test-webhook` + `make restart-webhook`. Commit:
`fix(webhook): rate-limit after auth + guard malformed Content-Length`. Handed to Codex; SHA pending.

### Webhook request-hardening bugfix complete — 2026-08-08

Fix commit `ee32837d` moves API/Slack rate limiting after authentication/signature checks and
guards both POST `Content-Length` parses with `_content_length`, returning HTTP 400 for malformed
values. It adds `scripts/tests/bin/webhook_request_hardening.py`; the extensionless webhook module
needed an explicit `SourceFileLoader` in that test so Python can import it. `py_compile`, the six
regression tests, smoke test, and `_agent_audit` passed. `make restart-webhook` was run and the
live smoke check returned HTTP 200; Grafana login emitted the pre-existing HTTP 401 warning while
the smoke command still passed. The fix is pushed to `origin/k3d-manager-v1.23.0`.
- **Part (a) handed to Codex (2026-08-07).** Focused spec
  `docs/plans/v1.23.0-cve-dashboard-part-a-image-attribution.md` — panel id 5 regroup by
  `namespace, image_repository, resource_name` (source-only, no cluster reconfig, no LIVE-VERIFY).
  Parts (b) CVE-id export + (c) job-target labeling are a separate later handoff (need live
  reconfig + ApplicationSet reapply). Live dashboard reapply is Claude-owned post-merge.

## Part (a) source fix complete — 2026-08-07

Commit `db81f534` changes only panel id 5's Prometheus grouping, legend, and title to attribute
critical vulnerabilities by image and resource. Both YAML and embedded-dashboard JSON parse checks
passed; the commit is pushed to `origin/k3d-manager-v1.23.0`. Live reapply remains Claude-owned.

## Parts (b)+(c) handed to Codex — 2026-08-07

Focused spec `docs/plans/v1.23.0-cve-dashboard-parts-bc-cveid-and-remediation-target.md` (spec
commit `5aa7f771`). Six source files: dashboard panels id 8 (CVE-ID table) + id 9
(remediation-by-target), `trivy-operator-values.yaml` + acg `metricsVulnIdEnabled: true`,
`kube-prometheus-stack-values.yaml` + acg KSM `metricLabelsAllowlist` for
`jobs=[target-namespace,target-image]`, `bin/k3dm-webhook` `_create_cve_scan_job` job-labeling +
`_cve_label_value` sanitizer, and the `webhook.bats` label assertion. All old-blocks were verified
against live source before handoff (`import re` present L9; caller vars in scope L3201; dashboard
tail L96–99; trivy L29–31 both files; both kube-prometheus files lack a top-level
`kube-state-metrics` key). Corrected the master spec's Change 7: **7b-only** — the bats mock logs
argv at L45 and falls through to `exit 0`, so a `label job` arm would double-log. Panels 8/9 are
**LIVE-VERIFY** (`vuln_id` / `label_target_*` names confirmed after apply). Live cutover
(reapply trivy + kube-prometheus values hub+acg, ApplicationSet reapply, `make restart-webhook` +
smoke gate, finalize panel 8/9 queries) is **Claude-owned, post-merge**.

## Pending releases (from the integration split — see intent map for files + full detail)

- **v1.24.0 = platform hardening (D webhook + E credential rotation + F istio/hostinger + unseal watchdog).**
  Carried blocker: recurring rotation automation exists ONLY for LDAP+Grafana — ArgoCD/Prometheus/
  Alertmanager were rotated once by hand; per-service automation NOT built.
- **v1.25.0 = Stripe/Go live acceptance + hostinger capacity (workstream G, BLOCKED, cross-repo).**
  Carried blockers: merge order-repo `0e3feb9` schema fix (`order_items.total_price NOT NULL`) +
  promote image → rerun Stripe live E2E acceptance (currently 2/4, Stripe cases fail on schema);
  hostinger 2-CPU capacity expansion (right-sizing is a stopgap).

## Recently shipped (pointers only)

- **v1.22.0** RELEASED — OpenLDAP bitnami→Symas migration. PR #111 merged `1bbb74b0`, tagged v1.22.0
  (2026-08-07). enforce_admins restored on main. Retro: `docs/retro/2026-08-07-v1.22.0-retrospective.md`. (CHANGELOG)
- **v1.21.0** RELEASED — k3dm-webhook security hardening. PR #110 merged `f68bdee1`, tagged. (CHANGELOG)
- **v1.20.0** RELEASED — CVE auto-patch-loop hardening. PR #109 merged `9da73458`, tagged. (CHANGELOG + retro)
- **Stripe checkout A–F** all MERGED to main across the 5 shopping-cart repos (2026-08-02); enablement
  PRs (#47/#66) merged; payment side live on hostinger. Remaining *live acceptance* work is workstream
  G above (v1.25.0). Deep saga detail is in git history + `docs/issues/2026-08-02-*`.
- Branch-protection approval count restored (`0→1`) on shopping-cart-infra #89 + order #63 (task #4, done).
