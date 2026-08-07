# Active Context — k3d-manager

> **Compressed 2026-08-07.** This file holds only the *live* focus + carried-forward
> blockers. Completed-work detail lives in `CHANGELOG.md`, `docs/retro/`, `docs/issues/`,
> `docs/plans/release-split-intent-map.md`, and git history (pre-compression versions of
> this file are recoverable via `git log --follow memory-bank/activeContext.md`).

## Current focus — v1.23.0 CVE observability + remediation lifecycle (workstreams B+C)

- **Branch cut fresh off main (`1bbb74b0`).** `origin/k3d-manager-v1.23.0` was 50 commits
  diverged (merge-base at v1.20.0), predating the v1.21.0 + v1.22.0 squash-merges and carrying
  a duplicate OpenLDAP commit (`b30f7898`) plus superseded verbose memory-bank state. Re-cut
  clean (same playbook as v1.22.0): old branch archived intact at
  `origin/archive/k3d-manager-v1.23.0-integration` (`48148c0d`); only the two genuinely-new
  artifacts carried forward — the CVE dashboard spec and the v1.22.0 retro (commit `f7105dc5`).
  ⚠️ The re-cut still needs a **`--force-with-lease`** to replace the diverged remote branch
  (hard-blocked in this env → user runs it). Nothing lost — verified via tree diff before archive.
- **Spec:** `docs/plans/v1.23.0-cve-autopatch-dashboard-observability.md` — make the CVE
  Auto-Patch Grafana dashboard show *what* and *where* (namespace/image/CVE/remediation target),
  not just aggregate counts. Three parts: (a) dashboard query change (no cluster reconfig);
  (b) enable `trivy_vulnerability_id` export + CVE-ID table panel; (c) label `cve-auto-*` Jobs
  with their target + allowlist in kube-state-metrics + remediation-by-target panel. Parts (b)/(c)
  have runtime-label names confirmable only *after* config applies.
- **Carried blockers (from the integration split):**
  - Apply CVE dashboard v18 live (Hub tunnel `127.0.0.1:57780`).
  - Close out payment `manual_review` digest-mismatch event (verify or document as expected).
  - `observability.sh` needs a per-hunk split from workstream E (E lands in v1.24.0).
  - Carries `docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`.

## Pending releases (from the integration split — see intent map for files + full detail)

- **v1.24.0 = platform hardening (D webhook + E credential rotation + F istio/hostinger + unseal watchdog).**
  Carried blocker: recurring rotation automation exists ONLY for LDAP+Grafana — ArgoCD/Prometheus/
  Alertmanager were rotated once by hand; per-service automation NOT built.
- **v1.25.0 = Stripe/Go live acceptance + hostinger capacity (workstream G, BLOCKED, cross-repo).**
  Carried blockers: merge order-repo `0e3feb9` schema fix (`order_items.total_price NOT NULL`) +
  promote image → rerun Stripe live E2E acceptance (currently 2/4, Stripe cases fail on schema);
  hostinger 2-CPU capacity expansion (right-sizing is a stopgap).

## Recently shipped (pointers only)

- **v1.22.0** RELEASED — OpenLDAP bitnami→Symas migration. PR #111 merged `1bbb74b0`, tagged v1.22.0
  (2026-08-07). enforce_admins restored on main. Retro: `docs/retro/2026-08-07-v1.22.0-retrospective.md`. (CHANGELOG)
- **v1.21.0** RELEASED — k3dm-webhook security hardening. PR #110 merged `f68bdee1`, tagged. (CHANGELOG)
- **v1.20.0** RELEASED — CVE auto-patch-loop hardening. PR #109 merged `9da73458`, tagged. (CHANGELOG + retro)
- **Stripe checkout A–F** all MERGED to main across the 5 shopping-cart repos (2026-08-02); enablement
  PRs (#47/#66) merged; payment side live on hostinger. Remaining *live acceptance* work is workstream
  G above (v1.25.0). Deep saga detail is in git history + `docs/issues/2026-08-02-*`.
- Branch-protection approval count restored (`0→1`) on shopping-cart-infra #89 + order #63 (task #4, done).
