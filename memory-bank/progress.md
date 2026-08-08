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

## Pending (integration-split releases — full file map + blockers in the intent map)

- [ ] **QUEUED bug — Grafana rotation never reaches the DB + status false-green (task #11).** Spec
      `docs/bugs/v1.23.0-bugfix-grafana-rotation-db-not-applied.md`. Rotator updates Vault/ESO/secret
      but not Grafana's sqlite DB → stored password 401s after each monthly rotation; `bin/k3dm-webhook`
      hub Grafana smoke reads app-cluster `acg-kube-prometheus-stack-grafana` (absent on hub) →
      false-green. Live stopgap `reset-admin-password` applied 2026-08-07 (not in git; re-breaks next
      rotation). Needs design (exec+RBAC vs admin API) + LIVE-VERIFY. Not handed off.
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
      Not yet pushed.
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
