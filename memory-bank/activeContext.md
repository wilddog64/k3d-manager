# Active Context — k3d-manager

> **Compressed 2026-08-09.** Live focus + carried-forward blockers only. Shipped detail lives in
> `CHANGELOG.md` (v1.23.0 section), `docs/retro/`, `docs/issues/`, `docs/bugs/`,
> `docs/plans/release-split-intent-map.md`, and git history (`git log --follow memory-bank/`).

## Current focus — v1.23.0 RELEASED; now on `k3d-manager-v1.24.0`

### v1.24.0 handoff batch completed (2026-08-10)

- Webhook auth reconciliation committed and pushed as `3fddcf3e`; hostinger status head/tail
  truncation split and pushed as `8eb8cc34`.
- Istio/Hostinger drift reconciliation committed and pushed as `357edf52`.
- Order remediation promoter git-persistence slice committed and pushed as `3df62fbf`.
- Static gates passed: webhook `py_compile` + BATS (52 and 53 tests respectively), Istio shellcheck/YAML
  parsing, promoter shellcheck/POSIX/YAML parsing, and `_agent_audit` under Bash.
- Promoter live dry-run/auto-sync remains Claude-owned post-merge verification; the dedicated
  `platform-ops-git-writer` least-privilege PAT must be seeded before durable git writes activate.
- **Claude independently VERIFIED all 5 SHAs on `origin/k3d-manager-v1.24.0` (2026-08-10):** archive-revert
  guard intact (`GEMINI_MODEL=gemini-3.5-flash-medium` line 212, `_rate_limited("slack")` line 3054, zero
  `gemini-2.5-flash`, Content-Length hardening present) — the D `bin/k3dm-webhook` edit was hand-applied,
  not a file checkout; `bats webhook.bats` re-run by Claude = `1..53`, **0 failures**; `py_compile` clean;
  promoter touched **exactly 3 files, zero service-kustomization edits**; memory-bank commit (`fcab6f16`)
  is code-free; chain linear off `670ff7c6`, all commit messages match specs verbatim. **D + F + #18 slice
  are code-complete and pushed.** Remaining v1.24.0 work: **E rotation automation** (now the active task),
  agy headless bug doc (`agy --help` discovery), the two Claude-owned live verifications, PAT seed.

### QUEUED (do NOT start until Codex finishes his v1.24.0 assignment) — secure Vault remote access

- **Trigger 2026-08-10:** user cannot reach Vault from office (SSH blocked, browser/HTTPS-only machine).
  Investigation found Vault is fully healthy (pod `1/1`, unsealed, local `:18200` → 200) but has **no
  public path**: not in the laptop cloudflared ingress, no VirtualService, and the only remote path is a
  reverse SSH tunnel (`com.k3d-manager.ssh-tunnel`, autossh `-R 8200:127.0.0.1:18200 ubuntu@srv1754834.hstgr.cloud`)
  landing on hostinger **loopback** `127.0.0.1:8200` — usable only from on the hostinger box. hostinger
  cloudflared is `inactive` and has no vault ingress either.
- **Chosen design (Option B — user-approved direction):** expose the **Vault UI** via the existing laptop
  cloudflared as `vault.3ai-talk.org → http://localhost:18200`, gated by **Cloudflare Access** with **MFA
  = Google IdP** (user's Google Authenticator/TOTP is the second factor). Two independent gates: Cloudflare
  Access (identity+MFA) then Vault's own login (userpass/OIDC — NOT root token).
- **Non-negotiable build order:** create the Access application + default-deny allow-only-me policy FIRST,
  THEN add the cloudflared ingress + proxied DNS; verify an anonymous request redirects to Access (never
  Vault) before trusting. Enable a Vault audit device. Root token stays laptop-only (break-glass).
- **Filing (decision pending):** proposed `docs/howto/secure-vault-remote-access-cloudflare-access.md`
  (mostly Cloudflare Zero-Trust dashboard config + one-line tunnel ingress — runbook, not repo code).
  NOT folded into v1.24.0 (already at 5-plan-doc cap; off-theme). No tunnel/Cloudflare changes made yet.
  See auto-memory [[project_secure_vault_remote_access]].

- **PR [#112](https://github.com/wilddog64/k3d-manager/pull/112) MERGED** (`7253ece4`), tagged
  **v1.23.0** + GitHub release. Post-merge close-out complete 2026-08-09: `deploy_argocd_platform_ops`
  applied the platform-ops files live and the **TrivyCritical ownership split + `k3dm-quiet` blackhole
  route are confirmed live on the hub** (ours = `image_repository=~"wilddog64/.*"` → cve-auto-patch;
  upstream → `tier: upstream` → blackhole); `make restart-webhook` loaded the Slack-title fix;
  `argocd_check_values_branch` = all 6 apps on `k3d-manager-v1.23.0`; `enforce_admins` restored; retro
  `docs/retro/2026-08-09-v1.23.0-retrospective.md`; next branch `k3d-manager-v1.24.0` cut from `7253ece4`.
- **Open follow-up carried to v1.24.0:** headless `_call_gemini` analyze still posts "no output produced
  — command permission auto-denied" for the surviving ours-alert; needs an agy no-tools/permission
  decision. See auto-memory `reference_trivy_critical_upstream_image_noise` and the alert-noise spec
  `docs/bugs/v1.23.0-bugfix-trivy-critical-upstream-image-alert-noise.md`.

### v1.23.0 shipped scope (reference)

- **Scope** was off `k3d-manager-v1.23.0`. Scope = workstreams **B** (CVE inventory dashboard + `vulnerability-inventory-exporter`)
  + **C** (remediation-lifecycle verifier), plus the **pulled-forward Grafana admin credential
  rotation slice** (E — see intent map §E; v1.24.0 must SKIP the Grafana slice) and adjacent
  live-ops bugfixes (agy model drift, webhook rate-limit-after-auth + Content-Length, LDAP rotator
  image re-pin). Full change list = `CHANGELOG.md` [1.23.0]. Both intent-map carried-forward v1.23.0
  items are **resolved**: dashboard is live at **Codex 1:1** (`06a0416e`, user preferred the 4-table
  view over the "by image" regroup); payment digest-mismatch closed by the multi-arch verifier fix
  (`33b45a41`).
- **All B+C work is LIVE-VERIFIED end-to-end on the hub** (2026-08-09): verifier flips
  matching-digest payment events `promotion_requested → applied`; `CVERemediationInFlight` fires and
  Alertmanager marks the paired payment TrivyCritical `suppressed`/`inhibitedBy`, lifting ~16s after
  completion. `label_replace` normalization (strip `ghcr.io/`) confirmed live for all 3 sc services.

## Deferred — carry forward into v1.24.0

- **Order remediation `ready_pod_digest_mismatch` — task #18 SHIPPED 2026-08-10 (`3df62fbf`), Claude-verified.**
  Git-persistence slice (Option B) committed + pushed; `_git_persist_promotion` clones the frozen
  `_app_target_branch`, awk-pins `digest:` in `services/shopping-cart-<svc>/kustomization.yaml`, commit+push;
  falls back to live-patch-only when `GIT_WRITE_TOKEN` unset. Still Claude-owned: live dry-run + PAT seed.
  Decision record below (Option B; open
  questions RESOLVED (`da12ab8c`)). The promoter (`app-cve-scan.sh:289`) patches the **live ArgoCD
  Application** `spec.source.kustomize.images`, not git. order's override is EMPTY and its promotion
  event has `candidate`/`to_tag`/`from_digest` all empty → no clean immutable `sha-*` candidate resolved
  (order is bare-tag / `IfNotPresent`). **Ratified: B (promoter persists override to git → durable for
  ALL services) in v1.24.0; A (order CI `sha-<gitsha>` tagging, cross-repo) → v1.25.0.** Not C.
  Live-verified design (spec now handoff-ready): (1) source is **THIS repo** — `services-git` appset
  generates apps from `repoURL: k3d-manager`, `path: services/shopping-cart-<svc>/kustomization.yaml`,
  `targetRevision: ${K3D_MANAGER_BRANCH}` (NOT shopping-cart-infra); edit is kustomize `images:`
  (name/newTag/digest). (2) Appset has `ignoreApplicationDifferences: .spec.source.kustomize.images` →
  live-patch already survives routine reconcile; the real gap is git≠live source-of-truth (lost on
  rebuild/recreate). (3) Apps run `automated {prune,selfHeal}` (auto-sync) but frozen at
  `k3d-manager-v1.22.0` → promoter must commit to the branch `targetRevision` tracks, not main
  (`${K3D_MANAGER_BRANCH}` inert trap). (4) Promoter runs in `aquasec/trivy:0.63.0` `/bin/sh` — **no
  `git`** → write via GitHub REST Contents API over `wget` (like `_dispatch_rebuild`), scoped
  `contents:write` PAT on `wilddog64/k3d-manager` only, injected as `GIT_WRITE_TOKEN`. **Q4 corrected +
  full impl AUTHORED `70952d53`:** trivy image actually HAS `git` 2.47.2 (busybox wget is POST-only, can't
  PUT → Contents API infeasible) → write path is `git clone --depth 1 --branch <targetRevision>` over
  HTTPS-with-token, awk-edit the kustomization `images:` to pin `digest:` only, commit+push. **awk editor
  tested live in `aquasec/trivy:0.63.0`** against real payment/order (append) + product-catalog (in-place
  `newTag`→`digest`, idempotent). Spec now has 5 exact change blocks (app-cve-scan.sh helpers +
  `_promote_image` hook, cronjob env, argocd.sh `argocd_sync_git_writer_secret`) + user prereq (seed
  `platform-ops-git-writer` PAT in Keychain, contents:write scope only). **#18 now fully handoff-ready
  (transcribe-not-design).**
- **Dashboard parts (b)+(c) superseded.** Spec
  `docs/plans/v1.23.0-cve-dashboard-parts-bc-cveid-and-remediation-target.md` (CVE-ID panel + KSM
  `metricLabelsAllowlist` job-target labeling) was written before the full revert to Codex 1:1
  (`06a0416e`). Re-scope against the Codex dashboard before ever executing; not part of this release.
- **Leftover carry:** `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`;
  `observability.sh` per-hunk split from workstream E — both → v1.24.0.

## Pending releases (from the integration split — files + detail in the intent map)

- **v1.24.0 = platform hardening (D+E+F) — scope CONFIRMED 2026-08-09 (broad reconcile).** The intent
  map's "D+E+F" label was stale: D's webhook hardening mostly shipped in v1.21.0 + v1.23.0 (`ee32837d`),
  F is on main and live-verified, and E's Grafana slice shipped in v1.23.0 (⚠️ SKIP it). But an
  archive-vs-main diff found **genuine live-relevant drift** (fixes applied to the live cluster but
  committed only to `archive/k3d-manager-v1.22.0-integration`), so the user chose the broad reconcile.
  **Confirmed carry-ins (verified real gaps, not superseded forks):**
  - **D — webhook auth.py hardening (spec REVISED 2026-08-10).** `bin/k3dm-webhook:52` imports
    `_verify_slack_signature` from `scripts/lib/webhook/auth.py` (so the lib IS live). Archive adds
    malformed-timestamp/body try/except fail-closed to the Slack sig verify + a
    `_slack_user_is_allowlisted` helper. **Codex hit a real spec defect:** 2 of the 4 archive
    `webhook.bats` tests exercise `bin/k3dm-webhook` code (allowlist ENFORCEMENT + hostinger report
    truncation) that is archive-only, while the spec forbade touching `bin/k3dm-webhook`. **User chose
    (2026-08-10): wire the allowlist enforcement INTO D** (the helper is dead code otherwise — Change 2b
    hand-applies the import + 6-line reject block, ⚠️ NOT a file checkout: archive `bin/k3dm-webhook` is
    older and would revert v1.23.0's `gemini-3.5-flash-medium` + Content-Length hardening; keep main's
    `_rate_limited("slack")`). D now = 3 tests. **Hostinger report truncation SPLIT OUT** to
    `docs/bugs/v1.24.0-bugfix-hostinger-status-report-truncation.md` (its own commit,
    `fix(webhook): keep hostinger status report header + health sections when long`). Codex's auth.py
    Change 1+2 already applied+verified in the working tree (compiles, malformed-sig test passes).
  - **F — Istio/hostinger GitOps drift.** `istio-ambient.yaml`: `ServerSideDiff=true` compare-option +
    `ignoreDifferences` for istiod `ValidatingWebhookConfiguration` caBundle/failurePolicy
    (controller-owned runtime state). `k3s-hostinger.sh`: `AMBIENT_CNI_CONF_DIR`/`_BIN_DIR` pointing
    the Istio CNI DaemonSet at k3s/flannel paths (not Cilium defaults). `shopping-cart.yaml.tmpl` +7.
  - **E — REWRITTEN 2026-08-10 after live discovery (was ArgoCD/Prometheus/Alertmanager, now
    ArgoCD + Prometheus).** User chose "ArgoCD-only (Rec)" then added Prometheus after finding its
    basic-auth is the weak `admin/password`. Live facts: **ArgoCD** = the only genuine persistent
    in-cluster hub credential (`argocd-secret`.admin.password bcrypt) → clean in-cluster CronJob rotator;
    `argocd account bcrypt` reads stdin (no argv leak), reuse it. **Alertmanager** = host-side launchd
    proxy cred (plaintext Vault → local env → python proxy :9093), no in-cluster consumer → **DROPPED
    from E.** **Prometheus** = NOT enforced on hub (empty web-config, localhost port-forward); weak
    `admin/password` applied only to ACG sandboxes via host deploy; `alpine/k8s` image has no
    htpasswd/openssl/bcrypt → recurring rotation is **host-side launchd timer**, not a CronJob. The
    `observability.sh` per-hunk E carry is **VACUOUS** (empty main..archive diff) — dropped. **New bugfix
    filed:** `docs/bugs/v1.24.0-bugfix-prometheus-weak-basic-auth-default.md` (kill the bcrypt('password')
    literal + `:-password` default; htpasswd -i strong gen; self-heal the live weak value; do the bugfix
    FIRST). E spec fully rewritten in `docs/plans/v1.24.0-credential-rotation-automation.md`.
    Live weak value CONFIRMED then **CLOSED 2026-08-10 (Claude ops):** hub Vault
    `secret/k3d-manager/prometheus-basic-auth` overwritten with a 32-char strong password + `$2y$12$`
    bcrypt (token+payload via stdin, no argv leak). Value is now non-weak/non-empty so current unfixed
    code reads it as-is (won't re-seed weak); the bugfix keeps it strong + self-heals. Bugfix code +
    E rotators still to implement (bugfix FIRST). **Grafana Vault `user`-key gap (noted 2026-08-10):**
    `secret/observability/grafana` holds only `password` (matches live secret by SHA); `user` key empty.
    Non-blocking hygiene follow-up recorded in the E spec's "Follow-up note" — NOT in the ArgoCD/Prometheus
    batch; address when the Grafana rotator YAML is next edited (add `"user":"admin"` to its Vault PUT).
  - **Fold-ins (all four, per user):** agy `_call_gemini` headless command-permission fix (v1.23.0
    follow-up); `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md` (already
    filed); order remediation promoter decision (task #18); observability.sh E carry (above).
  - **Specs WRITTEN `8ceb533d` (≤5 plan-doc cap):** 4 plan docs — `v1.24.0-webhook-auth-reconcile` (D,
    exact old/new blocks), `v1.24.0-istio-hostinger-drift-reconcile` (F, exact blocks),
    `v1.24.0-credential-rotation-automation` (E design + observability.sh carry — has open design
    decisions on bcrypt/htpasswd application + Prom/AM shared-credential), `v1.24.0-order-remediation-promoter`
    (task #18 DECISION doc: recommends Option B persist-to-git in v1.24.0, defer Option A order-CI
    sha-tagging to v1.25.0); + `docs/bugs/v1.24.0-bugfix-webhook-gemini-headless-permission.md` (cap-exempt,
    needs `agy --help` flag discovery) and existing `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`.
    Ready for handoff; E + #18 have open decisions the user/impl must resolve first.
  - **Split-execution:** bring archive-only hunks in per-file via
    `git checkout archive/k3d-manager-v1.22.0-integration -- <file>` (per-hunk for shared files);
    `observability.sh` splits across releases so needs per-hunk selection.
- **v1.25.0 = Stripe/Go live acceptance + hostinger capacity (G, BLOCKED, cross-repo).** Merge
  order-repo `0e3feb9` schema fix (`order_items.total_price NOT NULL`) + promote image → rerun Stripe
  live E2E (2/4 now); hostinger 2-CPU capacity expansion (right-sizing is a stopgap).

## Recently shipped (pointers only — detail in CHANGELOG + retro)

- **v1.22.0** RELEASED — OpenLDAP bitnami→Symas migration. PR #111 `1bbb74b0`, tagged. Retro
  `docs/retro/2026-08-07-v1.22.0-retrospective.md`.
- **v1.21.0** RELEASED — webhook security hardening. PR #110 `f68bdee1`, tagged.
- **v1.20.0** RELEASED — CVE auto-patch-loop hardening. PR #109 `9da73458`, tagged.
- Stripe checkout A–F all MERGED to main across the 5 shopping-cart repos (2026-08-02); payment side
  live on hostinger. Remaining live-acceptance work = v1.25.0 (workstream G).
