# Active Context — k3d-manager

> **Compressed 2026-08-11.** Live focus + carried-forward blockers only. Shipped detail lives in
> `CHANGELOG.md` (v1.24.0 section), `docs/plans/v1.24.0-*`, `docs/bugs/v1.24.0-*`, `docs/retro/`,
> `docs/issues/`, and git history (`git log --follow memory-bank/`).

## Current focus — v1.25.0 scope queued on clean release branch

The clean `v1.25.0` branch is based on merged `main` (`fd281c85`). Its queued scope now contains three
implementation-grade plans: `docs/plans/v1.25.0-e2e-verification-harness.md`,
`docs/plans/v1.25.0-e2e-observability-path-a.md`, and
`docs/plans/v1.25.0-dependabot-automerge-observability.md` (event-driven Dependabot auto-merge
monitoring with Grafana/Alertmanager visibility), plus
`docs/plans/v1.25.0-status-output-contract.md` (concise color-coded `make status` with failed-service
health/HTTP codes, `SERVICE=<name>` focused diagnostics, full and JSON modes). Implementation is not started.
The mistaken `docs/argocd-login-smoke-diagnosis` branch was closed/deleted and is not part of v1.25.0.

## Current focus — v1.24.0 CODE-COMPLETE + LIVE-VERIFIED; release complete

**v1.24.0 = platform hardening (D+E+F+#18).** All code committed + pushed to
`origin/k3d-manager-v1.24.0`, Claude-verified on origin. CHANGELOG + README + `docs/releases.md`
written. **Next: PR gate → merge → tag → reapply ApplicationSets (hub + ACG) → confirm
`argocd_check_values_branch`.**

| Slice | Commit(s) | State |
|---|---|---|
| D — webhook auth fail-closed + Slack allowlist enforcement | `3fddcf3e`; hostinger truncation `8eb8cc34` | live; py_compile + webhook.bats 53/53 |
| F — Istio ambient / hostinger CNI drift reconcile onto release branch | `357edf52` | shellcheck + YAML pass |
| E — Prometheus weak-default removal + ArgoCD/Prometheus rotators + 4 live-verify bugfixes | `e1256d0a`, `3db193cb`, `84232cc0` | LIVE-VERIFIED (see below) |
| #18 — CVE promoter persists to git | `3df62fbf` | dry-run verified live (see below) |
| agy headless analyze fix | `69e21e15` | live-smoked (real analysis text) |
| show-service-passwords ArgoCD reads Vault | `33e42905` | shown password logs in |

### Live-verify state (release-ops, done 2026-08-11)

- **E ArgoCD rotator DEPLOYED + verified live:** rotator manifest applied + Vault `argocd-rotation`
  policy/role created via `deploy_argocd_platform_ops`; one-shot Job rotated → `argocd-secret` mtime
  advanced, stored bcrypt clean/valid, new Vault password → ArgoCD `/api/v1/session` **LOGIN SUCCESS**
  (wrong pw rejected as control). Prometheus host-side launchd agent installed + rotate regenerated a
  strong bcrypt on `ubuntu-hostinger`. **The live ArgoCD admin password is now the ROTATED value**
  (old bcrypt `$2y$10$AgfGS5Vm…390Uqy.` retained as manual restore net; new plaintext in Vault
  `secret/argocd/admin`). ⚠️ **Restore-on-failure path is code-present (trap) but not fault-injected**
  (avoided breaking the live credential).
- **#18 promoter git-persist DRY-RUN verified live:** exercised `_git_persist_promotion`'s exact path
  non-destructively — clone release branch via `x-access-token:` URL (exit 0), real `set_image_digest.awk`
  on `services/shopping-cart-order/kustomization.yaml` (appended `images:` block correctly),
  promoter-author local commit, `git push --dry-run origin HEAD:k3d-manager-v1.24.0` → exit 0
  (**token authenticates WRITE**). Remote untouched.
  - ⚠️ **INTERIM TOKEN — MUST REPLACE before in-cluster promoter use.** Keychain
    `platform-ops-git-writer`/`k3dm` currently holds `gh auth token` (`repo` scope) — acceptable ONLY
    for the local dry-run (runs as the user). Before the promoter runs **in-cluster** (token lives in
    a cluster Secret), replace with a dedicated **fine-grained `contents:write`-only PAT** on
    `wilddog64/k3d-manager`, then re-run `argocd_sync_git_writer_secret platform-ops`. The full E deploy
    already brought the promoter code live with `GIT_WRITE_TOKEN` `optional:true` (safe live-patch fallback).

### Follow-up (non-blocking)

- Update auto-memory `reference_trivy_critical_upstream_image_noise` "still errors" note once a real
  `wilddog64/*` TrivyCritical analyze is observed posting real text via the `69e21e15` fix.

## Pending releases (forward scope)

- **v1.25.0 = Stripe/Go live acceptance + hostinger capacity (G, BLOCKED, cross-repo).** Merge
  order-repo `0e3feb9` schema fix (`order_items.total_price NOT NULL`) + promote image → rerun Stripe
  live E2E (2/4 now). **Live deadlock stopgapped 2026-08-10** (`docs/issues/2026-08-10-hostinger-rollout-deadlock-maxsurge-on-2cpu-node.md`):
  order/basket wedged mid-rollout — `maxSurge=1` needs 2× CPU on a 95%-full 2-CPU node → `FailedScheduling`;
  live-patched both to `maxSurge=0/maxUnavailable=1`, converged. **Durable fix = this workstream:** commit
  `maxSurge=0` into app git manifests (ArgoCD may selfHeal the live patch away) OR bump node CPU.
  **+ E2E verification harness (plan doc #1 `v1.25.0-e2e-verification-harness.md`):** enable the disabled
  e2e suite on ephemeral substrates — Tier 1 vCluster (per-candidate blocking, `OAUTH2_ENABLED=false`) +
  Tier 2 ACG sandbox (periodic full-stack, real ingress/OIDC, runs Stripe live E2E). Substrate-agnostic
  (needs basket/catalog/order URLs + oauth flag); new `scripts/plugins/e2e.sh`; `workflow_call` on
  `shopping-cart-e2e-tests`. Exit-code + JSON-summary contract seeds the v1.26.0 gate.
  **+ e2e observability (plan doc #2 `v1.25.0-e2e-observability-path-a.md`):** reuse the CVE exporter seam
  — harness writes a `k3dm.k3d.io/e2e-result=true` ConfigMap; extend `vulnerability-inventory-exporter.py`
      to emit `e2e_*` gauges; new `grafana-dashboard-e2e.yaml` + `E2EVerificationFailing/Stale` rules; deploy
      via `argocd.sh`. No new component, no Tempo (span tracing = separate forward theme).
      **+ Dependabot auto-merge observability (plan doc #3 `v1.25.0-dependabot-automerge-observability.md`):**
      signed GitHub PR/check/workflow events plus 15-minute read-only reconciliation feed bounded
      Prometheus metrics, Grafana panels, and owned Alertmanager Slack alerts. Monitor never merges or
      changes branch protection; implementation not started.
- **v1.26.0 = image signing + attestation — close the CVE loop (SCOPED, not started).** Spec
  `docs/plans/v1.26.0-image-signing-cve-loop-closure.md`. cosign sign + Trivy vuln/SBOM attest at build;
  `cosign verify` at promotion (promoter gate) AND admission (Kyverno, staged Audit→Enforce, app
  namespaces only, upstream/`tier:upstream` excluded). Key-based, private key in Vault + Keychain backup,
  pub via ESO (LOCKED, not keyless). Multi-repo: k3d-manager `signing.sh`/Kyverno/ClusterPolicy/promoter
  gate + shopping-cart `{order,payment,basket,frontend,product-catalog}` CI. CI key delivered as GH
  secrets seeded from Vault (runners can't reach Vault). Slots after v1.25.0. See
  [[project_image_signing_cve_loop]].

## Backlog / queued (not release-gated)

- **Secure Vault remote access (QUEUED — start after v1.24.0 release).** Expose the **Vault UI** via the
  existing laptop cloudflared as `vault.3ai-talk.org → http://localhost:18200`, gated by **Cloudflare
  Access** with **MFA = Google IdP** (TOTP). Two gates: Access (identity+MFA) then Vault login
  (userpass/OIDC — NOT root token). **Non-negotiable build order:** create the Access application +
  default-deny allow-only-me policy FIRST, THEN add cloudflared ingress + proxied DNS; verify an
  anonymous request redirects to Access before trusting. Enable a Vault audit device; root token
  laptop-only (break-glass). Vault today has NO public path (reverse-tunnel loopback only). Filing
  (decision pending): `docs/howto/secure-vault-remote-access-cloudflare-access.md`. No changes made yet.
  See [[project_secure_vault_remote_access]].
- **Jenkins DEPRECATED in docs — DONE 2026-08-10, code KEPT.** Built-in but unused (no live pods, opt-in
  `ENABLE_JENKINS=1` only, not in roadmap; real CI/CD = GHA+ArgoCD). Marked deprecated in current-state
  docs; historical docs untouched. Earlier code-retirement plan **cancelled**. See
  [[project_jenkins_deprecation]].
- Dashboard parts (b)+(c) — spec `v1.23.0-cve-dashboard-parts-bc-*` superseded by the Codex 1:1 dashboard;
  re-scope before executing. `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`
  carry; the observability.sh E per-hunk carry was **VACUOUS** (empty diff) → dropped.
- Shopping-cart Dependabot backlog (Go builder-image bumps, majors held) — `project_backlog.md`.
- rabbitmq-client-java NPE fix `36ed860` — JAR publish + pom update pending.

## Recently shipped (pointers only — detail in CHANGELOG + retro)

- **PR #113 Copilot follow-up (2026-08-11):** six actionable review threads addressed and resolved in
  `be29b5a0` (credential exposure, portability, launchd PATH, and test dependency). CI is green; PR
  remains review-gated pending an approving reviewer.

- **v1.23.0** RELEASED — CVE observability + remediation lifecycle (B+C). PR #112 `7253ece4`, tagged;
  platform-ops deployed live (alert-noise split active), retro `docs/retro/2026-08-09-v1.23.0-retrospective.md`.
- **v1.22.0** RELEASED — OpenLDAP bitnami→Symas migration. PR #111 `1bbb74b0`, tagged.
- **v1.21.0** RELEASED — webhook security hardening. PR #110 `f68bdee1`, tagged.
- **v1.20.0** RELEASED — CVE auto-patch-loop hardening. PR #109 `9da73458`, tagged.
- Stripe checkout A–F all MERGED to main across the 5 shopping-cart repos (2026-08-02); payment side
  live on hostinger. Remaining live-acceptance work = v1.25.0 (workstream G).
