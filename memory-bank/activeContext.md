# Active Context — k3d-manager

> **Compressed 2026-08-09.** Live focus + carried-forward blockers only. Shipped detail lives in
> `CHANGELOG.md` (v1.23.0 section), `docs/retro/`, `docs/issues/`, `docs/bugs/`,
> `docs/plans/release-split-intent-map.md`, and git history (`git log --follow memory-bank/`).

## Current focus — v1.23.0 PR #112 OPEN, gates passed, awaiting user merge

- **PR [#112](https://github.com/wilddog64/k3d-manager/pull/112) is OPEN and merge-ready**
  (head `9c55e81a`). All gates passed: CI green, Copilot's 3 findings fixed + threads resolved
  (0 unresolved), Copilot re-review of the folded-in alert-noise commit clean. **`enforce_admins`
  is DISABLED** — user can merge. Do NOT auto-merge. Copilot findings (all fixed `9f319630`):
  Vault token off `curl` argv → mktemp header file; exporter `/tmp` emptyDir for ro-rootfs; vault.sh
  `mount_path` `printf %q`. Findings doc `docs/issues/2026-08-09-copilot-pr112-review-findings.md`.
- **Folded into PR #112 (`9c55e81a`): TrivyCritical upstream-CVE noise fix.** Live hub: 39 firing
  `TrivyCriticalVulnerabilityDetected`, only 1 (`wilddog64/shopping-cart-payment`) auto-remediable;
  38 third-party images the app-cve-scan loop can't rebuild flooded Slack. Split the alert by image
  ownership — only `wilddog64/*` keeps `remediation: cve-auto-patch`; upstream gets a `tier: upstream`
  rule routed to a new `k3dm-quiet` blackhole receiver (still on the dashboard, no Slack). Also fixed
  the analyze Slack title (`labels["name"]` → empty; now `app`/`image_repository` fallback). Spec
  `docs/bugs/v1.23.0-bugfix-trivy-critical-upstream-image-alert-noise.md`. ⚠️ namespace is NOT a usable
  discriminator — exporter attributes every image to `platform-ops`. **Follow-up (v1.24.0):** headless
  `_call_gemini` analyze still posts "no output produced — command permission auto-denied" for the
  surviving ours-alert; needs an agy no-tools/permission decision.

- **Original scope** off `k3d-manager-v1.23.0`. Scope = workstreams **B** (CVE inventory dashboard + `vulnerability-inventory-exporter`)
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

### Post-merge checklist (Claude-owned)
- Reapply platform-ops durably: `argocd.sh deploy_argocd_platform_ops` (the prometheusrule /
  alertmanager-config / verify-script CM were applied **directly** for verification only — inert on
  the branch until deployed). Dashboard ApplicationSets (`grafana-dashboards-hub`/`-acg`) already
  track `k3d-manager-v1.23.0`; confirm with `argocd_check_values_branch`. Hub ArgoCD ns = **`cicd`**.
- Tag `v1.23.0`, restore `enforce_admins`, write retro, cut `k3d-manager-v1.24.0`.

## Deferred — NOT v1.23.0-gating (carry forward)

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

**Dashboard cleanup promoted 2026-08-13:** `02128101` is now on the ArgoCD-tracked
`k3d-manager-v1.23.0` branch. A hard refresh advanced `hub-grafana-dashboards` to that revision;
the live ConfigMap contains Current CVE Remediation Status and Remediation History (audit) panels.
Follow-up investigation: the remaining order failure targets old `sha-05ce65...@sha256:a8813e...`,
while live order runs `sha-564ccfd...`; its current inventory has only UNKNOWN findings. This is a
historical failed promotion with no applied event, not the current image. See
`docs/issues/2026-08-13-order-remediation-current-row.md`.
The exporter refinement is now live: order is classified `deployment_advanced` and payment remains
`applied` in the current-status metrics; no audit events were deleted.
Dashboard remediation tables now hide repeated Prometheus scrape metadata and use concise headers:
`CVEs`, `Affected service`, `Image`, `Requested`, `Applied`, `State`, and `Reason`.
Platform and shopping-cart CVE inventory tables also hide repeated scrape metadata (`Service`,
`container`, `endpoint`, and exported labels) so only actionable vulnerability fields remain.
