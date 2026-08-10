# Active Context — k3d-manager

> **Compressed 2026-08-09.** Live focus + carried-forward blockers only. Shipped detail lives in
> `CHANGELOG.md` (v1.23.0 section), `docs/retro/`, `docs/issues/`, `docs/bugs/`,
> `docs/plans/release-split-intent-map.md`, and git history (`git log --follow memory-bank/`).

## Current focus — v1.23.0 RELEASED; now on `k3d-manager-v1.24.0`

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

- **Order remediation `ready_pod_digest_mismatch` — needs a design decision (task #18).** The
  promoter (`app-cve-scan.sh:289`) deploys the patched image by patching the **live ArgoCD
  Application** `spec.source.kustomize.images`, not git → ephemeral (any appset reconcile wipes it).
  order's override is EMPTY and its promotion event has `candidate`/`to_tag`/`from_digest` all empty →
  the promoter never resolved a clean immutable `sha-*` candidate for order (order is bare-tag /
  `IfNotPresent`). Two durable fixes to weigh: (a) persist promotions to git; (b) close order's
  rebuild→clean-image loop. product-catalog + payment work; order is the outstanding case.
- **Dashboard parts (b)+(c) superseded.** Spec
  `docs/plans/v1.23.0-cve-dashboard-parts-bc-cveid-and-remediation-target.md` (CVE-ID panel + KSM
  `metricLabelsAllowlist` job-target labeling) was written before the full revert to Codex 1:1
  (`06a0416e`). Re-scope against the Codex dashboard before ever executing; not part of this release.
- **Leftover carry:** `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`;
  `observability.sh` per-hunk split from workstream E — both → v1.24.0.

## Pending releases (from the integration split — files + detail in the intent map)

- **v1.24.0 = platform hardening (D webhook + E credential rotation + F istio/hostinger + unseal
  watchdog).** ⚠️ SKIP the Grafana rotation slice (shipped early in v1.23.0). Remaining E = recurring
  rotation automation for **ArgoCD / Prometheus / Alertmanager** (only LDAP + Grafana automated;
  the rest were hand-rotated once).
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
