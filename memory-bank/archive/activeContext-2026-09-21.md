# activeContext archive — 2026-09-01 → 2026-09-04 (v1.28.0 block)

Split out of `memory-bank/activeContext.md` on 2026-09-21 during routine compression.
Everything here is settled: v1.28.0 shipped, its PR merged, and the tree is now on v1.36.0.
Kept verbatim for provenance. Live context stays in `activeContext.md`.

---

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

### 2026-09-04 — v1.28.0 two-cloud bring-up: fresh-hub `make up` aborted on unguarded PrometheusRule apply
- Live two-cloud validation (AWS EC2 k3s + hostinger): both clouds' nodes + hub came up
  (`ubuntu-k3s` 3 nodes Ready, `ubuntu-hostinger` 1 node Ready, hub k3d Up), but ArgoCD stayed BARE
  (0 registered clusters, 0 ApplicationSets, 0 Applications). `make up` had errored, not completed.
- Root cause: `scripts/plugins/argocd.sh` applied `PrometheusRule` (1540), `AlertmanagerConfig` (1546),
  and `vulnerability-inventory-exporter` (1549, bundles a ServiceMonitor) WITHOUT a CRD guard — on a
  fresh hub the Prometheus-Operator CRDs aren't installed yet, so `PrometheusRule` hard-failed
  (`no matches for kind "PrometheusRule" in version "monitoring.coreos.com/v1"`) and aborted the deploy
  BEFORE `register_app_cluster` (bin/cluster-up:758) ever ran. The ServiceMonitor ensure (argocd.sh:512)
  already had the correct guard; these three missed it.
- FIX (this branch): added a single `prometheusrules.monitoring.coreos.com` CRD-presence guard
  (`_prom_operator_present`) mirroring line 512; gated all three applies, left the Grafana ConfigMap
  unconditional. shellcheck clean. Spec: `docs/bugs/argocd-prometheus-operator-unguarded-crd-apply.md`.
- Next: re-run idempotent `make up CLUSTER_PROVIDER=k3s-aws` → confirm it clears platform-ops and reaches
  `register_app_cluster`, then reapply ApplicationSets (hub + ACG) + `argocd_check_values_branch`, then
  inspect the v1.28.0 multi-cloud internals (scoped state dirs, active-providers, port offsets, hub-lock).

### 2026-09-04 (cont.) — argocd guard SHIPPED + verified; next blocker LDAP verify newline FIXED
- argocd guard FINAL scope = ALL SIX monitoring-stack-dependent applies behind one
  `prometheusrules.monitoring.coreos.com` CRD guard: PrometheusRule, AlertmanagerConfig,
  vulnerability-inventory-exporter(+rollout restart), and the argocd/cve-autopatch/e2e Grafana dashboard
  ConfigMaps (all target `namespace: monitoring`, also absent on fresh hub). The earlier "leave the
  ConfigMap unconditional" note was WRONG — corrected before commit. Committed `5f4526fd` (pushed).
- LIVE-VERIFIED: guard fired ("Prometheus-Operator CRDs / monitoring namespace absent; skipping..."),
  platform-ops cleared, `ubuntu-k3s` registered into hub ArgoCD, app stack built through the identity phase.
- NEXT blocker hit at Step 10d.5/14 (LDAP password seed): ldappasswd -S set OK but ldapwhoami verify failed
  Invalid credentials(49) for admin/developer/operator → checkpoint not written → `make up` Error 1.
- Root cause: verify pipe `printf '%s\n'` wrote `<password>\n` to the `-y` file; ldapwhoami -y uses the whole
  file incl. newline as bind password. PROVEN live on openldap-0: -y w/newline → invalid creds(49);
  w/o newline → bind OK. FIX: `printf '%s\n'` → `printf '%s'` at bin/cluster-up:1045 (verify only; the
  ldappasswd -S set step's newlines are prompt delimiters, left as-is). shellcheck clean, bats 8/8.
  Committed `41389804` (pushed). Spec: docs/bugs/2026-09-04-ldap-verify-ldapwhoami-trailing-newline.md.
- Observation (separate, NOT fixed): two LDAP instances in `identity` on hub — openldap-0 (Helm
  openldap-stack-ha StatefulSet, the seed target, holds all real users) + a stray `ldap` Deployment
  (name=ldap, component=directory). Immaterial to the newline bug; matters for Keycloak federation (10d.6).
- IN FLIGHT: `make up CLUSTER_PROVIDER=k3s-aws` re-run (task bsqm1ma34) to confirm 10d.5 clears.
- STILL PENDING after make up completes: reapply ApplicationSets pinned to release branch (hub + ACG) →
  argocd_check_values_branch → inspect v1.28.0 multi-cloud internals across both clouds. No PR yet (gated).

### 2026-09-04 (cont.) — TWO-CLOUD validation COMPLETE (AWS + hostinger, both fixes verified)
- Brought up hostinger as 2nd cloud (`make up CLUSTER_PROVIDER=k3s-hostinger`, task bzqq4i5i6, exit 0).
  Path = deploy_cluster (NOT bin/cluster-up): k3sup install ran idempotently ("Skipping...already exists",
  workloads persist — never touches the VM), merged ubuntu-hostinger kubeconfig, registered into hub
  (ubuntu-hostinger -> https://2.25.146.252:6443), recorded active-providers/k3s-hostinger marker.
- VERIFIED two-cloud state: BOTH cluster secrets in hub cicd (cluster-ubuntu-k3s + cluster-ubuntu-hostinger);
  BOTH active-providers markers coexist; ArgoCD generating ubuntu-hostinger-* apps (data-layer/eso/
  shopping-cart-* Synced+Healthy); both node contexts reachable (k3s=3, hostinger=1); argocd_check_values_branch
  green on k3d-manager-v1.28.0 after BOTH runs; k3s-aws scoped state intact (not clobbered).
- OBSERVATION 1 (consistency, not a bug): k3s-hostinger/ has NO scoped state subtree — deploy_cluster path
  isn't checkpoint-scoped like bin/cluster-up. hostinger uses Cloudflare edge + in-cluster Vault (HUB_VAULT_PROFILE
  =hostinger), so no local port-forward footprint to scope/offset. Port-offset table (aws=0/hostinger=10/...) applies
  to the cluster-up local-PF path only. Candidate v1.28.0 follow-up: scope deploy_cluster state too, or document why not.
- OBSERVATION 2: ubuntu-hostinger-platform app HEALTH=Unknown (others Synced+Healthy) — likely reconciling; recheck.
- MILESTONE STATUS: v1.28.0 two-cloud multi-provider is LIVE-VALIDATED. Remaining before PR (gated): resolve/close
  the two observations, lib-foundation acg-robust-click PR (credential-test first), two-LDAP-instance federation check.

### 2026-09-04 (cont.) — Two v1.28.0 follow-ups CLOSED
- FOLLOW-UP 1 (deploy_cluster scoped-state asymmetry): NO CODE CHANGE — rationale already in
  docs/plans/v1.28.0-parallel-multi-cloud-provisioning.md (~L420: hostinger deliberately flat, "collides
  with nothing", full scoping = tracked future work). Added a dated Live-validation note confirming it:
  hostinger's deploy_cluster path created NO scoped subtree AND no local PF footprint (edge + in-cluster
  Vault), did not disturb k3s-aws state. Sequential two-cloud coexistence PROVEN; literal simultaneity
  (Phase 3/4 ports+flock) still untested.
- FOLLOW-UP 2 (two-LDAP federation check): RESOLVED the question, found a REAL high-sev bug (needs a
  decision, NOT blind-fixed). Keycloak shopping-cart realm federates the osixia `ldap` Deployment
  (ArgoCD-managed by shopping-cart-identity, dc=shopping-cart,dc=local, connectionUrl
  ldap.identity.svc:389), NOT openldap-0. The cluster-up Step 10d.5 seed writes openldap-0
  (dc=home,dc=org) + Vault → DECOUPLED from SSO. PROVEN: Vault dev password fails to bind osixia ldap
  (Invalid credentials 49). So get-keycloak-password returns a non-working-for-SSO password.
  Filed docs/issues/2026-09-04-keycloak-federates-osixia-ldap-not-seeded-openldap.md with 3 decision
  options (A osixia canonical / B openldap canonical / C two-dirs-by-design) + verification steps.
  Supersedes the pre-osixia 2026-08-22 doc. ESCALATED to user — awaiting canonical-directory decision.

### 2026-09-04 (cont.) — Tidy-up: pruned unconditional Jenkins fixtures from LDAP bootstrap seed
- User asked why jenkins-admin appears in openldap-0 though Jenkins was never deployed. Answer: static
  seed fixture in bootstrap-basic-schema.ldif (Jenkins is deprecated/never deployed; 0 jenkins pods on
  hub/aws/hostinger). The ldap.sh generator already GATES jenkins entries behind enable_jenkins; only the
  static bootstrap seeded them unconditionally.
- Pruned (dc=home,dc=org tidy surface, self-consistent): deleted dead jenkins-users-groups.ldif (unloaded);
  removed jenkins-admin user + jenkins-admins group + it-devops dangling jenkins-admin member from
  bootstrap-basic-schema.ldif (kept it-devops w/ chengkai.liang); dropped jenkins-admin from
  test-directory-auto-load user+group loops; dropped jenkins-admin from rotation defaults (vars.sh
  LDAP_USERS_TO_ROTATE + ldap-password-rotator.sh + .yaml.tmpl). shellcheck clean; group blocks keep >=1 member.
- Deliberately KEPT (deprecated-but-gated / separate scope): ldap.sh gated generator, vars.sh LDAP_JENKINS_*
  config block, bootstrap-ad-schema.ldif (separate AD dc=corp,... testing dir), dirservices RBAC,
  jenkins values tmpls, smoke-test-jenkins, ad/vars.sh jenkins-admin path. Source-only cleanup — live
  openldap-0 keeps jenkins-admin until a fresh bootstrap; SSO (osixia ldap) unaffected.
- Spec: docs/bugs/2026-09-04-prune-unconditional-jenkins-ldap-fixtures.md.

### 2026-09-04 (cont.) — DECISION: leave bootstrap-ad-schema.ldif Jenkins fixtures as-is
- After pruning the default-directory Jenkins clutter (d9ee756b), checked the AD-testing schema
  scripts/etc/ldap/bootstrap-ad-schema.ldif (dc=corp,dc=example,dc=com; "Jenkins Service"/"Jenkins Admins").
- FINDING (non-obvious): its Jenkins entries are LOAD-BEARING for a live CI suite —
  scripts/tests/lib/dirservices_activedirectory.bats:227 asserts "CN=Jenkins Admins,OU=Groups,DC=corp,...".
  The whole `activedirectory` directory-service provider is a Jenkins-AD integration feature
  (_dirservice_activedirectory_generate_jcasc/authz, deploy_ad → _ldap_run_ad_smoke_test, AD_BIND_DN=svc-jenkins).
  It loads ONLY under explicit AD testing (ldap.sh:1207 deploy_ad), NOT in the default openldap-0 directory.
- USER DECISION 2026-09-04: LEAVE IT. Removing Jenkins here isn't a fixture tidy — it's "remove the whole
  Jenkins-AD provider + its BATS suite", a separate larger task that conflicts with keep-deprecated-Jenkins.
  Do NOT re-open as "tidy" work. See [[project_jenkins_deprecation]].

### 2026-09-04 (cont.) — lib-foundation PR #45 created (acg robust-click), gates green, AWAITING MERGE GO
- Sequence (user-directed 2026-09-04): (1) lib-foundation PR → (2) subtree-pull into k3d-manager → (3) v1.28.0 PR.
- STEP 1 DONE (prepared, gated): PR https://github.com/wilddog64/lib-foundation/pull/45
  (fix/acg-sandbox-robust-click, commit 91f0f12: _robustClick dispatched MouseEvent for sandbox reveal/provision).
  Gates: make credential-test PASS (extracted + sts-validated AWS creds); CI acg/bats/shellcheck all green;
  scope clean. Copilot NOT attached (appears disabled on lib-foundation; not a payment PR). k3dm overlay
  (scripts/lib/foundation/.../acg/playwright/{sandbox.js,acg_restart.js}) is IDENTICAL to 91f0f12 — no un-upstreamed drift.
- HOLD: never-auto-merge. Awaiting user go to merge #45.
- STEP 2 (after merge): tag lib-foundation v0.4.14 → git subtree pull into k3d-manager (replaces the uncommitted
  overlay). STEP 3: create v1.28.0 k3d-manager PR (branch k3d-manager-v1.28.0, all this session's commits).

### 2026-09-04 (cont.) — STEP 1+2 DONE: lib-foundation v0.4.14 merged + subtree-synced into k3d-manager
- #45 merged (squash dddc18cb); tagged+released lib-foundation v0.4.14; git subtree pull --prefix=scripts/lib/foundation
  lib-foundation v0.4.14 --squash → commits 05c5e952 (squash) + 09dab403 (merge). Overlay now formalized; tree clean.
  Verified: pulled subtree JS identical to v0.4.14, _robustClick present. Pushed origin/k3d-manager-v1.28.0.
- STEP 3 NEXT: create v1.28.0 k3d-manager PR (base main). Pre-PR gates to run: CI green on branch, scope check,
  live smoke. Never-auto-merge holds for the v1.28.0 merge.

### 2026-09-04 (cont.) — STEP 3 DONE: v1.28.0 PR #119 created, CI GREEN, AWAITING MERGE GO
- PR https://github.com/wilddog64/k3d-manager/pull/119 (base main ← k3d-manager-v1.28.0, 24 commits, merge-base 62c9ff27).
- Gates: CI all green (CodeQL actions/js-ts/python, lint, detect, GitGuardian; stage2 skipped-conditional);
  local lib bats 323 exit 0; shellcheck clean; live two-cloud smoke done; scope clean.
- Copilot: NOT attached (requested_reviewers empty on both #45 and #119 via raw-JSON POST — appears Copilot code
  review not enabled on these repos right now). Flagged to user; not a payment PR.
- HOLD: never-auto-merge. Awaiting user go to merge #119. On merge: /post-merge (restore protection, tag v1.28.0,
  release, next branch, retro, standing-docs audit, memory-bank).
- Sequence COMPLETE up to the gate: lib-foundation #45 merged+v0.4.14+subtree-synced → v1.28.0 PR #119 up & green.

## 2026-09-20 — deploy_observability deliberately NOT run; hub control plane degraded

Asked to run `deploy_observability` against the hub. **Stopped short and applied only the
targeted piece.** Live read-only diagnosis found the hub control plane actively failing:

- `state.db` 2.16 GiB + 499 MiB WAL, **zero `COMPACT` events in 24 h**; kine SQL 1–5 s.
- apiserver `/healthz` = `[-]etcd failed` (5/5 probes); storage metrics time out.
- Control-plane node `457182e619fc` `Ready=False (KubeletNotReady) container runtime is down`,
  taint added 13:47:57Z; its own `kube-node-lease` renewals fail.
- Server container 511% CPU, in-container load average 60.03 on `nproc=10`; host load 21.56/10.
- ArgoCD repo-server `10.43.86.193:8081` connection refused → ~20 Applications `sync=Unknown`.

`deploy_observability` reapplies two ApplicationSets at `K3D_MANAGER_BRANCH=k3d-manager-v1.36.0`
(up from v1.35.0), which would repoint `$values` and trigger a full monitoring/trivy resync —
a write burst into the exact datastore that is the bottleneck. Adding that load to a control
plane that cannot renew its own lease was the wrong call, so it was not run.

**Applied instead:** the one mutation that mattered, by hand —
`kubectl -n monitoring patch servicemonitor kube-prometheus-stack-apiserver --type=json`
setting `/spec/endpoints/0/scrapeTimeout` to `45s`. Verified after: `scrapeTimeout=45s`,
`jobLabel=component` intact, `interval` still unset (inherits global 60s). This is the same
single write `_observability_ensure_apiserver_scrape_timeout` (`0d663a40`) performs.

**Running the full `deploy_observability` remains outstanding and is the operator's call**,
ideally after the datastore is addressed.

This is a recurrence of `docs/bugs/2026-09-09-hub-kine-compaction-stall.md` — appended a
`## Recurrence — 2026-09-20` section there rather than filing a duplicate. Key new finding: the
`K3DM_HERMES_AUTO_KINE_GUARD` circuit breaker is **inert** for this recurrence, because it
requires the 2026-09-09 `stale_acg_registration` signature AND an 8 GiB threshold. Growth is
~310 MB/day since the 2026-09-13 rebuild, so it re-reaches 8 GiB in ~19 days unattended.
The `0d663a40` scrape-timeout fix treats a symptom of this and does not close it.

## 2026-09-20 — Tier 2 sandbox defects dispatched to Codex

Spec `docs/bugs/2026-09-20-e2e-sandbox-job-service-names-markers-secrets.md` extended with
`## Before You Start`, `## Rules`, `## What NOT to Do`, `## Commit message (exact)` and an
`## If you cannot commit` fallback; pushed as `8ed24cc0`. Dispatched via `codex exec`
(session `01a0bf1a-c1dc-7f41-b03f-bb9402f3f9c5`, model `gpt-5.6-luna`) with the cluster
explicitly off limits — code + BATS only. Awaiting its report; SHA, gate output and the
mutation table all require independent verification before being trusted.

## 2026-09-20 — Alertmanager notification errors: 50m CPU limit, throttled 83%

Alert `PrometheusErrorSendingAlertsToAnyAlertmanager` (>3% send errors) deep-dived.
Root cause: `kube-prometheus-stack-values.yaml:96` caps alertmanager at `cpu: 50m`, so it is
CFS-throttled in 83–87% of every period, flat over 24 h. Batches of up to 46 alerts (61 firing)
exceed Prometheus's 10 s notifier timeout → `context deadline exceeded`. 168/1469 = 11.4%
cumulative. Memory fine (28 MiB / 64 MiB).
Secondary mode: `no route to host` to stale alertmanager pod IPs (4 distinct IPs in 24 h,
5 restarts) — spiked the ratio to 1.0 during the 14:30–14:50Z k3s crash loop. Amplifier, not
cause.
**Independent of the kine stall** — errors begin 09-17 23:00, before compaction died 09-18
02:16Z, and the throttle fraction is unchanged across it.
Spec: `docs/bugs/2026-09-20-alertmanager-cpu-limit-throttles-notifications.md` — proposes
limits `cpu: 500m` / `memory: 128Mi`, requests `cpu: 50m` / `memory: 64Mi`. ACG variant has no
resources block, unaffected. **Not applied — needs the operator's go.**

## 2026-09-20 — Kine compaction root cause found; Tier 2 fix landed

**Kine (`docs/bugs/2026-09-09-hub-kine-compaction-stall.md`, deep dive appended `160fe63b`).**
Compaction did **not** fall behind churn. It died at `2026-09-18T02:16:19Z` on `Compact failed:
failed to record compact revision: sql: transaction has already been committed or rolled back`
and was never rescheduled — 288 events/day (one per 5 min) through 09-17, then nothing for 2.5
days. My earlier "zero COMPACT events in 24 h" was a **measurement error**: case-insensitive
`grep compact` matches `compact_rev_key` inside Slow SQL text (50,039 lines). Use
`grep 'msg="COMPACT'`.

Corrections to the recurrence section: growth is ~580 MB/day measured post-failure (not 310),
so the 8 GiB deadline is ~7–10 days (not 19); WAL checkpointing is **healthy** (constant size +
advancing mtime = in-place reuse, Q3 was a false alarm); the repo-server CrashLoop is an
**effect** (`exitCode 0 / Completed` on kubelet SIGTERM, `timeoutSeconds=1` probes vs 1.1–11.3 s
health checks) that then amplifies via 27 Applications retrying at `sync=Unknown`. All four nodes
returned to `Ready` on their own; in-container load 67–75 comes with 26% idle, so this is
datastore lock contention (631 `error in txn compare`), not CPU exhaustion.

**Remedy is a k3s server process restart — operator's action, not run.** No rebuild indicated by
this evidence. Raw SQLite retention deletion still forbidden. Durable fix: replace the Hermes
size-plus-stale-registration predicate with a **compaction liveness** check (no
`msg="COMPACT deleted"` for >15 min), which would have caught this at normal DB size. Spec not
yet filed.

**Tier 2 sandbox defects — DONE, `56df33f5`.** Codex implemented; `.git` writes denied for the
fourth time, so it reported the block honestly without fabricating a SHA and Claude committed on
its behalf. Independently verified: scope limited to the three allowed files, `shellcheck -S
warning` exit 0, `e2e.bats` 42/0 (34 → 42, +8 new cases), full `make test` 974/0 `MAKE_EXIT=0`,
and all 8 mutations caught by their intended test. It mirrored the Tier 1 `_e2e_provision_pull_secret`
precedent, and the `declare -f shopping_cart_resolve_ghcr_pat` cross-plugin guard already existed
at `e2e.sh:31`. Stripe key goes in via `--from-file=sk_test=/dev/stdin`, never argv.

Still outstanding: full `deploy_observability` (deferred, operator's call); Tier 2 live run is the
operator's (`acg_restart` then `e2e_verify_sandbox`); ApplicationSet reapply for v1.34.0/v1.35.0
config, which conflicts with the datastore situation until compaction is restored.

## 2026-09-20 — Payment secret seed clobber fix in progress

Implemented the literal replacement from `docs/bugs/2026-09-20-seed-clobbers-real-payment-secrets.md`
in `shopping_cart_seed_sandbox_vault_kv`: payment encryption, Stripe, and PayPal now reuse the
target secret, copy canonical source data, and only then use their existing fallback; Stripe also
uses the exact no-account Keychain accessor specified by the bug. Added six focused BATS cases and
the `[Unreleased]` changelog entry. Keychain existence check without `-w` reported account `cliang`.
Focused BATS: 14/14 passed. `shellcheck scripts/plugins/shopping_cart.sh` reported only the
pre-existing SC2015/SC2016/SC2153 findings in unrelated lines 882–975 — Claude confirmed these are
pre-existing by running shellcheck against `git show HEAD:` of the same file and getting identical
counts (5/3/2), so the change adds zero new warnings. Full `make test` completed 980/980, exit 0.

Implemented by Codex, verified and committed by Claude — Codex again could not commit
(`.git/index.lock: Operation not permitted`), the same sandbox wall as the Hermes fix. See
[[reference_codex_exec_cannot_commit_git_lock]].

**Claude correction on top of Codex's diff:** `_stripe_sk` was assigned without a `local`
declaration, so the real Stripe secret key would have persisted as a **global** for the life of the
shell after `shopping_cart_seed_sandbox_vault_kv` returned. `_src_json` beside it *is* local
(line 630). This was **Claude's spec omission**, not a Codex error — the spec's literal block did
not declare it and Codex copied the block faithfully, as instructed. Fixed by adding `_stripe_sk=""`
to the existing `local` on line 630.

## 2026-09-20 — Alert legibility fixed, `deploy_observability` run, SMS still blocked on a lost Vault key

Ran `deploy_observability --confirm` twice (operator-authorised). Three things are now verified
live on the hub, not merely committed:

| Change | Live evidence |
|---|---|
| apiserver `scrapeTimeout` 45s | `scrape_timeout: 45s` in `/api/v1/status/config`, persisted ≥2 min past an ArgoCD reconcile |
| hub `externalLabels` | `external_labels: cluster: hub` |
| legible control-plane rules | only `kubernetes-control-plane.legible` `KubeAPIDown`/`KubeletDown` exist; upstream duplicates gone |

**The 45s timeout had never actually applied.** `kube-prometheus-stack-apiserver` carries
`argocd.argoproj.io/tracking-id` and the observability ApplicationSet runs `selfHeal: true`, so the
out-of-band `kubectl patch` was reverted within seconds while
`_observability_ensure_apiserver_scrape_timeout` printed success against a value that no longer
existed. Two deploys in a row reported "set to 45s" with the live config still at 10s. Chart 67.9.0
exposes `kubeApiServer.serviceMonitor.interval` but no `scrapeTimeout`, so the patch is the only
lever; fixed with `ignoreDifferences` on `/spec/endpoints/0/scrapeTimeout` **plus**
`RespectIgnoreDifferences=true` — without the sync option, `ignoreDifferences` hides the diff but a
sync still overwrites the field. The function now reads the value back and warns instead of
trusting the patch exit code. See [[reference_argocd_selfheal_reverts_out_of_band_patch]].

**Alert messages are now self-identifying.** Body leads with alertname, severity and cluster, then
prefers `description` over `summary`, then the locating labels, then `StartsAt`; the root route
gained an explicit `group_by` (with none set, Alertmanager groups everything into one group whose
`GroupLabels` is empty, so the Subject rendered as a bare `[ALERT] `). Templates were proven by
compiling and executing them in a standalone Go harness against real alert labels — `amtool
check-config` validates only *file*-based templates and would not have caught an inline error
before send time. See [[reference_alertmanager_inline_templates_no_sprig]]. Spec:
`docs/bugs/2026-09-20-sms-alert-body-is-unidentifiable.md`.

**SMS delivery is still dead, and it is a backup gap, not a config bug.**
`alertmanager-smtp-secret` was lost in the rebuild; the Alertmanager CR still references it, so the
operator fell back to a generated default whose root receiver is `"null"` — `sms-critical` and
`smtp_smarthost` are absent from the running config. `deploy_observability` cannot rebuild it
because Vault's `secret/k3d-manager/alertmanager` went with the Vault PVC. Keychain has
`k3dm-alertmanager-gmail-app-password` but **not** `gmail_from` or `sms_gateway`, so
`make restore-google-app-password` will fail its own `Vault missing gmail_from,sms_gateway` guard.
Only `make alertmanager-secret` (interactive, needs a real TTY — operator's) can restore it. This is
the same class of loss as `cosign-public-key`: fields outside the 14-key canonical allowlist have
zero coverage.

Also outstanding from this pass: `Prometheus Vault credentials unreadable — skipping auth proxy`,
another KV casualty of the same PVC loss.

**Follow-up 2026-09-20 — the credential-restore tooling itself was the blocker.** The operator ran
`make alertmanager-secret` and it aborted with `all three values are required (run in an interactive
terminal)`: every value came from `read -r -p`, so with stdin not a TTY all three read empty. That
left no usable recovery path at all, because `make restore-google-app-password` backs up only
`gmail_app_pw` and therefore dies on its own `Vault missing gmail_from,sms_gateway` guard. Both
targets now resolve each value from env (`ALERTMANAGER_GMAIL_FROM`, `ALERTMANAGER_SMS_GATEWAY`),
then Keychain, then a prompt gated on `[ -t 0 ]`, and name each unresolved field individually.
`alertmanager-secret` backs `gmail_from`/`sms_gateway` up to Keychain on success, so the next PVC
loss is a single `make restore-google-app-password`. The Vault root token moved out of a `curl -H`
argument into the environment, per the CLAUDE.md secret-hygiene rule. Verified: the guard now lists
exactly the two genuinely missing fields and resolves the app password from Keychain silently.

**RESOLVED 2026-09-20 — SMS delivery restored end to end.** `alertmanager-smtp-secret` is rebuilt
and the running Alertmanager config carries `sms-critical` and `smtp_smarthost`; the root receiver is
no longer the generated `"null"` fallback and `group_by` is set. The operator supplied `gmail_from`
and `sms_gateway` once via env, after which both are in Keychain — confirmed by re-running
`make alertmanager-secret` with both env vars unset and no prompts. The secret now takes ~40s to be
picked up by the operator after the Vault write, so an immediate `/api/v2/status` check reports
`sms-critical` absent; poll rather than concluding failure. Routing verified against live alerts: of
3 active criticals, only `ServiceDown` reaches `sms-critical`; both
`TrivyCriticalVulnerabilityDetected` terminate at the `null` route ahead of it, which is the
intended Trivy-noise design, not a routing bug. One email notification attempt, zero failures for
every reason label. Still operator-confirmable only: whether the text physically arrived and reads
well on the handset.

**FIXED 2026-09-21 — `make show-service-passwords` died on `Error: invalid function name: '—'`.** The
recovery branch that restarts the Vault port-forward was written `$$(MAKE)`, so make emitted a
literal `$(MAKE)` to the shell and the shell ran it as a command substitution instead of make running
a recursive sub-make. APFS is case-insensitive, so `MAKE` resolved to `/usr/bin/MAKE` and actually
ran `make`; `.DEFAULT_GOAL := help` printed the help text; that captured stdout was word-split and
executed, and the help's first line carries a UTF-8 em-dash, which reached the dispatcher as a
function name. The error was only the symptom — `install-vault-port-forward` never ran, so the Vault
credential lookup could never recover and the target died on its own 10-attempt retry guard. Fixed to
`$(MAKE)` at `Makefile:502`; it was the only `$$(MAKE)` in the file against 9 correct uses. Verified
with a standalone probe makefile rather than by running the target, which prints live credentials:
`$(MAKE)` expands to the make binary path, `$$(MAKE)` expands to the stdout of a nested make.

**CLOSED 2026-09-21 — the SMS alert legibility bug is fully resolved.** The operator received and
confirmed a legible page: Subject `[FIRING] ServiceDown on hub (1)`, body
`ServiceDown [critical] on hub / No ready pods in namespace shopping-cart-app for > 5 mins ...`. Both
Subject and body arrived — this gateway does not drop the Subject — and the trailing `...` is
truncation at ~160 chars that cut the `where:` and `since:` lines. That is the anticipated behaviour
and the reason identity is emitted first: alertname, severity, cluster and the description all
survived. `docs/bugs/2026-09-20-sms-alert-body-is-unidentifiable.md` has every DoD box checked and is
marked RESOLVED. Treat the `where:`/`since:` tail as best-effort; no identifying field may depend on
it (namespace is already carried in both the description and the Subject).

**FILED 2026-09-21 — the `ServiceDown` page that the operator received is a true positive, and the
root cause is a validation defect.** Deep-dived per the standing rule rather than treating the alert
as known noise. All four `shopping-cart-apps` deployments have been `ImagePullBackOff` for 11h with
`403 Forbidden` from ghcr.io. The plumbing is fine — `ghcr-pull-secret` exists and its ExternalSecret
reports `SecretSynced True` — but all three PAT loaders in `scripts/plugins/shopping_cart.sh` validate
with `GET https://api.github.com/user`, which proves only that the token *authenticates*, never that
it has `read:packages`, the one scope GHCR checks. `gh auth status` shows the CLI token's scopes are
`admin:public_key, gist, read:org, repo` — no `read:packages`. Worse,
`shopping_cart_load_ghcr_pat_from_gh` *persists* that token to `secret/github/pat`, so the Vault
loader then finds it, probes `/user`, gets 200 and never escalates to the prompt: the fallback chain
converges on a permanently broken credential with every layer green. Spec:
`docs/bugs/2026-09-21-ghcr-pat-validated-for-auth-not-packages-scope.md`, which also captures a
secondary CLAUDE.md secret-hygiene violation (Vault token and PAT in `curl` argv at
`shopping_cart.sh:272` and `:311-313`) and prescribes an end-to-end GHCR token-exchange + manifest
HEAD probe as the only check that cannot be wrong. Operator action still required: mint a PAT with
`read:packages` — the gh CLI token can never work, its scopes are fixed by the OAuth app.

Note: I could not verify the stored PAT's scopes directly — reading `ghcr-pull-secret` and the
ExternalSecret spec were both denied as credential materialization, correctly. The diagnosis rests on
`gh auth status` (scopes only, no token) plus the code path, which is sufficient.

**DONE 2026-09-21 — the GHCR PAT scope-validation fix is on the branch (`cb428d09`).** Codex
implemented the spec faithfully and could not commit (`.git/index.lock`: Operation not permitted, the
same wall as 2026-09-20), so Claude verified and committed. Verification: diff scope exactly the two
permitted files, `bats scripts/tests/plugins/shopping_cart.bats` 25/25, shellcheck 10 findings before
and after. **Three defects surfaced during verification, none of them Codex's:** the spec instructed
`_err` in `shopping_cart_prompt_ghcr_pat`, but `_err` exits 1 — it aborted the run and made the next
two lines dead code, so the fall-through to `shopping_cart_resolve_ghcr_pat`'s remedy never happened;
now `_warn`. The argv assertion used a `grep -F` pattern that matched nothing in the **pre-fix** source
either, so it was a gate that could never fail — replaced with one proven to go 2 -> 0. And the
no-persist test asserted on `read:packages` while its own stub printed that string to stderr, so it
was testing the stub rather than the production message. Lesson worth keeping: a new test passing does
not mean it can fail — the no-persist gate was mutation-tested (guard removed -> `not ok 24`) and only
then trusted.

Still operator-only and the thing that actually restores the pods: mint a PAT with `read:packages`,
overwrite `secret/github/pat`, force-sync `ghcr-pull-secret`, restart the four deployments. The gh CLI
token can never work — its OAuth scopes are fixed at `repo, read:org, gist, admin:public_key`.

**2026-09-21 — the obvious restore tool cannot do the hub restore.** Before handing the operator
`bin/rotate-ghcr-pat` (which the plugin's own error message recommends) I read it, and it is wrong
for this in three ways: it hardcodes `--context ubuntu-k3s` in its propagation loop, so during a hub
outage it prints three `✅ namespace:` lines while changing nothing on the hub; it validates with
`GET /user` exactly like the defect just fixed, so it will accept a scope-less PAT and push it to
seven repos plus Vault; and it puts the PAT and the Vault token in argv three times, including
`kubectl create secret --docker-password`. The hardcoded context is a **recurrence** of
`docs/bugs/2026-06-14-bugfix-ghcr-pull-secret-hardcoded-context.md` in a different file. Filed
`docs/bugs/2026-09-21-rotate-ghcr-pat-targets-wrong-cluster-and-leaks-pat-in-argv.md`. Also note the
hub's `ghcr-pull-secret` is ESO-managed, so a direct `kubectl create secret` there would be reverted
on reconcile — the hub path must be *write Vault, force-sync the ExternalSecret*.

Added `bin/restore-hub-ghcr-pat` for the hub: PAT from stdin only, verified against ghcr.io with a
real token exchange before anything is stored, explicit `HUB_CONTEXT` default `k3d-k3d-cluster`,
Vault write through the hardened helper, ESO force-sync, rollout restart of the four deployments.
Refusal path verified live — a junk token is rejected with nothing written, exit 1.

## 2026-09-21 — rotate-ghcr-pat defects assigned to Codex

Spec made implementation-ready and pushed at `796ba237`:
`docs/bugs/2026-09-21-rotate-ghcr-pat-targets-wrong-cluster-and-leaks-pat-in-argv.md`.
Added `## Before You Start`, literal OLD/NEW blocks for 4 changes, the BATS gate list
with an explicit non-vacuity requirement, `## Rules`, and the verbatim commit message.

Dispatched to Codex via `codex exec` (session `01a0c3f9`), log at
`scratchpad/codex-rotate-run.log`. Scope: `bin/rotate-ghcr-pat` +
`scripts/tests/bin/rotate_ghcr_pat.bats` only. Awaiting SHA — verify before trusting.

