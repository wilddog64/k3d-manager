# Progress — k3d-manager

> **Compressed 2026-08-09.** Shipped-release detail lives in `CHANGELOG.md` + `docs/retro/`; the
> integration-split carry-forward in `docs/plans/release-split-intent-map.md`; per-incident detail in
> `docs/issues/` / `docs/bugs/`. Pre-compression history is in git (`git log --follow memory-bank/`).

## Releases

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

- [ ] **Order remediation promoter — needs decision (task #18).** Promoter live-patches the ArgoCD
      Application (ephemeral, not git); order's override is empty and the promoter never resolved a
      clean immutable `sha-*` candidate (bare-tag/`IfNotPresent`). Fix options: (a) persist to git;
      (b) close order's rebuild→clean-image loop. See `activeContext.md`.
- [ ] Dashboard parts (b)+(c) — spec `v1.23.0-cve-dashboard-parts-bc-cveid-and-remediation-target.md`
      superseded by the Codex 1:1 revert; re-scope before executing.
- [ ] `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md` +
      `observability.sh` per-hunk split from E → v1.24.0.

## Pending releases (integration-split — full file map + blockers in the intent map)

- [ ] **v1.24.0** — webhook + credential rotation + istio/hostinger ops + unseal watchdog (D+E+F).
      ⚠️ SKIP the Grafana slice (shipped in v1.23.0). Remaining E = recurring rotation automation for
      ArgoCD / Prometheus / Alertmanager (only LDAP + Grafana automated).
- [ ] **v1.25.0** — Stripe/Go live acceptance + hostinger capacity (G, BLOCKED, cross-repo). Merge
      order-repo `0e3feb9` schema fix + promote image → rerun Stripe live E2E (2/4 now); hostinger
      capacity expansion.

## Backlog (not release-gated)

- [ ] Shopping-cart Dependabot backlog (Go builder-image bumps, majors held) — auto-memory
      `project_backlog.md`.
- [ ] rabbitmq-client-java NPE fix `36ed860` — JAR publish + pom update pending.
