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

## Pending (integration-split releases — full file map + blockers in the intent map)

- [ ] **v1.24.0** — webhook + credential rotation + istio/hostinger ops + unseal watchdog (D+E+F).
      Blocker: recurring rotation automation for ArgoCD/Prometheus/Alertmanager (only LDAP+Grafana done).
- [ ] **v1.25.0** — Stripe/Go live acceptance + hostinger capacity (G, BLOCKED, cross-repo). Blockers:
      merge order-repo `0e3feb9` schema fix + promote image → rerun Stripe live E2E (2/4 now);
      hostinger capacity expansion.

## Done — recent (pointers) — cont.

- [x] **Grafana `show-service-passwords` unblock (2026-08-07).** `make show-service-passwords`
      was reading Grafana from the stale k8s secret after the live credential rotation. Pulled the
      Makefile Grafana hunk forward from workstream E (`40c8b08e`) onto v1.23.0 (`31db9732`); now
      reads `secret/data/observability/grafana` from Vault. Intent map updated: v1.24.0 E carve-out
      skips this hunk. Nothing was lost/overridden — full E work stays parked on
      `archive/k3d-manager-v1.22.0-integration` for v1.24.0.

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
