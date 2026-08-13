# Progress — k3d-manager

> **Compressed 2026-08-09.** Shipped-release detail lives in `CHANGELOG.md` + `docs/retro/`; the
> integration-split carry-forward in `docs/plans/release-split-intent-map.md`; per-incident detail in
> `docs/issues/` / `docs/bugs/`. Pre-compression history is in git (`git log --follow memory-bank/`).

## Releases

| Version | Theme | State |
|---|---|---|
| v1.23.0 | CVE observability + remediation lifecycle (B+C) | **PR #112 OPEN, merge-ready** — head `9c55e81a`; CI green, Copilot 3 findings fixed+resolved, `enforce_admins` DISABLED, awaiting user merge |
| v1.22.0 | OpenLDAP bitnami→Symas migration | RELEASED — PR #111 `1bbb74b0`, tagged |
| v1.21.0 | k3dm-webhook security hardening | RELEASED — PR #110 `f68bdee1`, tagged |
| v1.20.0 | CVE auto-patch-loop hardening | RELEASED — PR #109 `9da73458`, tagged |
| v1.18.0 | first-mile CVE gap closure | RELEASED — PR #108 `85742ef7`, tagged |
| v1.17.0 | real login verification in health smoke | RELEASED — PR #107 `b5d401b6`, tagged |

(v1.19.0 was a shopping-cart-only Dependabot milestone — no k3d-manager tag.)

### Dashboard cleanup promotion (2026-08-13)

Commit `02128101` promoted the current-versus-history exporter/dashboard fix to the tracked
`k3d-manager-v1.23.0` branch. ArgoCD hard refresh reached revision `02128101`, Synced/Healthy, and
the live dashboard now contains both remediation panels.
- [x] Order remediation row investigation (2026-08-13): failed event targets retired `sha-05ce65...`,
      while live order runs `sha-564ccfd...`; current findings are UNKNOWN severity. Recorded as a
      historical deployment-advanced case; future exporter refinement queued in the issue doc.
- [x] Deployment-advanced classification (2026-08-13): exporter compares failed remediation targets
      with current inventory images; live metrics show order `deployment_advanced` and payment `applied`.
- [x] Remediation table labels (2026-08-13): hidden repeated scrape metadata and renamed the visible
      fields to concise user-facing headers (`CVEs`, `Affected service`, `Image`, `Requested`, `Applied`,
      `State`, `Reason`).
- [x] CVE inventory table cleanup (2026-08-13): removed repeated exporter scrape columns from platform
      and shopping-cart tables; source commit `91b13fe3`.
- [ ] **v1.27.0 platform availability queued:** plan `docs/plans/v1.27.0-platform-zero-downtime-rollouts.md`
      covers stateless replicas/probes/PDBs/rolling updates, capacity gates, and stateful failover design.

## In flight — v1.23.0 (PR pending)

All B+C code + the pulled-forward Grafana slice is committed, pushed, and LIVE-VERIFIED end-to-end on
the hub. Full change list = `CHANGELOG.md` [1.23.0]. Shipped work (SHA pointers):

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

**Post-merge (Claude):** `argocd.sh deploy_argocd_platform_ops` (durable platform-ops apply — files are
inert on the branch until then); confirm dashboard appsets track v1.23.0 (`argocd_check_values_branch`);
tag `v1.23.0`; restore `enforce_admins`; retro; cut `k3d-manager-v1.24.0`.

## Deferred — NOT v1.23.0-gating

- [ ] **Order remediation promoter — needs decision (task #18).** Promoter live-patches the ArgoCD
      Application (ephemeral, not git); order's override is empty and the promoter never resolved a
      clean immutable `sha-*` candidate (bare-tag/`IfNotPresent`). Fix options: (a) persist to git;
      (b) close order's rebuild→clean-image loop. See `activeContext.md`.
- [ ] Dashboard parts (b)+(c) — spec `v1.23.0-cve-dashboard-parts-bc-cveid-and-remediation-target.md`
      superseded by the Codex 1:1 revert; re-scope before executing.
- [ ] `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md` +
      `observability.sh` per-hunk split from E → v1.24.0.
- [ ] Payment Trivy alert follow-up: current pod digest differs from the retired ReplicaSet reports;
      seven critical findings are documented. Forced refresh recreated the old report because the
      pod template and runtime image differ; image reconciliation plus Slack report/metric lookup
      are required.
      See `docs/issues/2026-08-12-payment-trivy-alert-stale-report-details.md`.

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
