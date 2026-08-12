# Progress — k3d-manager

> **Compressed 2026-08-11.** Shipped-release detail lives in `CHANGELOG.md` + `docs/retro/`; per-incident
> detail in `docs/issues/` / `docs/bugs/`. Pre-compression history is in git (`git log --follow memory-bank/`).

## Releases

| Version | Theme | State |
|---|---|---|
| v1.24.0 | platform hardening (D+E+F+#18) | **CODE-COMPLETE + LIVE-VERIFIED; release path in progress** — all SHAs pushed + Claude-verified on `origin/k3d-manager-v1.24.0`; CHANGELOG/README/releases.md written; PR gate → merge → tag → reapply ApplicationSets next |
| v1.23.0 | CVE observability + remediation lifecycle (B+C) | RELEASED — PR #112 `7253ece4`, tagged; platform-ops deployed live, `enforce_admins` restored |
| v1.22.0 | OpenLDAP bitnami→Symas migration | RELEASED — PR #111 `1bbb74b0`, tagged |
| v1.21.0 | k3dm-webhook security hardening | RELEASED — PR #110 `f68bdee1`, tagged |
| v1.20.0 | CVE auto-patch-loop hardening | RELEASED — PR #109 `9da73458`, tagged |
| v1.18.0 | first-mile CVE gap closure | RELEASED — PR #108 `85742ef7`, tagged |

(v1.19.0 was a shopping-cart-only Dependabot milestone — no k3d-manager tag.)

## v1.24.0 shipped commits (2026-08-11)

| Work item | Commit | Verify |
|---|---|---|
| Webhook auth fail-closed + Slack allowlist enforcement (D) | `3fddcf3e` | py_compile + webhook.bats; live 401/403 |
| Hostinger status report head/tail truncation (D) | `8eb8cc34` | webhook.bats 53/53 |
| Istio ambient / hostinger CNI drift reconcile (F) | `357edf52` | shellcheck + YAML |
| Prometheus weak basic-auth default removal (E) | `e1256d0a` | weak-hash grep empty, 13 observability BATS |
| Monthly ArgoCD + host-side Prometheus rotators (E) | `3db193cb` | argocd/observability BATS, shellcheck, plist |
| ArgoCD rotator bcrypt/sidecar + Prometheus launchd path (E bugfix, 4 live-verify defects) | `84232cc0` | argocd.bats 17/17, observability.bats 14/14 |
| Git-persisted CVE remediation promoter (#18) | `3df62fbf` | shellcheck/POSIX/YAML; dry-run verified live |
| agy headless analyze fix | `69e21e15` | webhook.bats 53/53; live real-analysis smoke |
| show-service-passwords ArgoCD reads Vault | `33e42905` | shown password logs in |

**LIVE-VERIFIED 2026-08-11:** E ArgoCD rotator deployed via `deploy_argocd_platform_ops` (Vault
`argocd-rotation` role created); one-shot Job → `argocd-secret` mtime advanced, clean bcrypt, new password
→ ArgoCD LOGIN SUCCESS; Prometheus host launchd installed + rotate regenerates strong cred. #18 promoter
git-persist dry-run end-to-end (clone → awk-pin → `push --dry-run` authenticates), remote untouched.
⚠️ Interim git-writer token (`gh auth token`, `repo` scope) must be replaced with a fine-grained
`contents:write`-only PAT before the promoter runs in-cluster — see `activeContext.md`.

**PR #113 review follow-up 2026-08-11:** Copilot's six actionable threads were fixed and resolved in
`be29b5a0`; local BATS/shellcheck/static parse gates passed and GitHub CI is green. PR is mergeable but
still requires an approving review.

**Diagnosis 2026-08-11:** filed `docs/issues/2026-08-11-argocd-login-smoke-stale-initial-secret.md`;
ArgoCD health is 200, but login smoke uses the stale bootstrap Secret after `argocd-secret` rotation.
Live ESO/Vault reconciliation completed 2026-08-12; smoke code now prefers the rotated admin Secret.

**Product-catalog rollout 2026-08-12:** fixed the Hostinger CPU deadlock in the overlay with
`maxSurge: 0/maxUnavailable: 1`; documented in
`docs/issues/2026-08-12-product-catalog-rollout-cpu-deadlock.md`.

## Pending releases (forward scope — detail in activeContext.md)

- [ ] **v1.25.0** — Stripe/Go live acceptance + hostinger capacity (G, BLOCKED, cross-repo). Merge
      order-repo `0e3feb9` schema fix + promote image → rerun Stripe live E2E (2/4 now); hostinger capacity
      (durable `maxSurge=0` in git OR bump node CPU — issue `2026-08-10-hostinger-rollout-deadlock-*`).
      **+ E2E verification harness** (plan doc #1) + **e2e observability** (plan doc #2) — enable disabled
      e2e on ephemeral substrates (Tier 1 vCluster blocking + Tier 2 ACG sandbox periodic); exit-code +
      JSON-summary contract seeds the v1.26.0 gate.
- [ ] **v1.26.0** — image signing + attestation, closing the CVE loop (SCOPED, not started). Spec
      `docs/plans/v1.26.0-image-signing-cve-loop-closure.md`. cosign sign + attest at build; `cosign verify`
      at promotion + admission (Kyverno, staged Audit→Enforce). Key-in-Vault, pub via ESO. Multi-repo.
      Slots after v1.25.0. `project_image_signing_cve_loop`.

## Backlog (not release-gated)

- [x] **Jenkins DEPRECATED in docs (DONE 2026-08-10) — code KEPT.** Verified unused; earlier removal item
      cancelled. `project_jenkins_deprecation`.
- [ ] **Secure Vault remote access (QUEUED — after v1.24.0 release)** — expose Vault UI via laptop
      cloudflared `vault.3ai-talk.org` behind Cloudflare Access + MFA (Google IdP / TOTP);
      Access-app-before-ingress ordering; Vault audit device on; root token laptop-only. Filing
      `docs/howto/secure-vault-remote-access-cloudflare-access.md` (decision pending). No changes made yet.
      `project_secure_vault_remote_access`.
- [ ] Dashboard parts (b)+(c) — superseded by the Codex 1:1 dashboard; re-scope before executing.
- [ ] `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md` carry.
- [ ] Shopping-cart Dependabot backlog (Go builder-image bumps, majors held) — `project_backlog.md`.
- [ ] rabbitmq-client-java NPE fix `36ed860` — JAR publish + pom update pending.
