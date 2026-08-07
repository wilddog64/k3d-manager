# Active Context — k3d-manager

> **Compressed 2026-08-07.** This file holds only the *live* focus + carried-forward
> blockers. Completed-work detail lives in `CHANGELOG.md`, `docs/retro/`, `docs/issues/`,
> `docs/plans/release-split-intent-map.md`, and git history (pre-compression versions of
> this file are recoverable via `git log --follow memory-bank/activeContext.md`).

## Current focus — v1.22.0 OpenLDAP release (PR #111)

- **PR #111 OPEN → main — CI GREEN, prepare-and-stop for user go on merge.**
  https://github.com/wilddog64/k3d-manager/pull/111 · head `204b82f8` · base main `f68bdee1`.
  Theme: migrate OpenLDAP off the retired `bitnamilegacy` image (66 criticals) to the Symas
  `jp-gouin/openldap-stack-ha` chart 4.3.3; service/ports pinned (`openldap.identity.svc:389`)
  so the cutover is transparent. Delimiter-safe (hex) chart passwords; durable Vault-seeded
  platform users; Keycloak/Jenkins/ArgoCD/rotator reconciled. Live-verified (Symas running,
  `developer` login through Keycloak, Jenkins LDAP auth). `ldap_chart_passwords` BATS 2/2,
  shellcheck clean. Copilot tagged — review outcome pending at time of writing.
- **Branch is the clean OpenLDAP-only re-cut.** The old 142-commit integration branch is
  archived intact at `origin/archive/k3d-manager-v1.22.0-integration` (`03ed9ad6`) — verified
  byte-identical before the `--force-with-lease` that replaced `origin/k3d-manager-v1.22.0`
  with the 5-commit re-cut. Nothing lost. Split rationale + file map: `docs/plans/release-split-intent-map.md`.
- **⚠️ Note for v1.23.0:** `origin/k3d-manager-v1.23.0` already exists and carries a *duplicate*
  OpenLDAP commit (`b30f7898`). It collapses away once v1.22.0 merges to main and v1.23.0 is
  rebased. Not a v1.22.0 concern; flag when cutting task #7.
- **After merge:** `/post-merge` (tag `v1.22.0`, re-enable enforce_admins, retro), then cut v1.23.0.

## Pending releases (from the integration split — see intent map for files + full detail)

- **v1.23.0 = CVE observability + remediation lifecycle (workstreams B+C).** Carried blockers:
  apply CVE dashboard v18 live (Hub tunnel `127.0.0.1:57780`); close out payment `manual_review`
  digest-mismatch event (verify or document as expected). `observability.sh` needs per-hunk split
  from workstream E. Also carries the `app-cve-scan` nonzero-exit/pod-label spec
  (`docs/bugs/2026-08-01-app-cve-scan-nonzero-exit-and-missing-pod-labels.md`).
- **v1.24.0 = platform hardening (D webhook + E credential rotation + F istio/hostinger + unseal watchdog).**
  Carried blocker: recurring rotation automation exists ONLY for LDAP+Grafana — ArgoCD/Prometheus/
  Alertmanager were rotated once by hand; per-service automation NOT built.
- **v1.25.0 = Stripe/Go live acceptance + hostinger capacity (workstream G, BLOCKED, cross-repo).**
  Carried blockers: merge order-repo `0e3feb9` schema fix (`order_items.total_price NOT NULL`) +
  promote image → rerun Stripe live E2E acceptance (currently 2/4, Stripe cases fail on schema);
  hostinger 2-CPU capacity expansion (right-sizing is a stopgap).

## Recently shipped (pointers only)

- **v1.21.0** RELEASED — k3dm-webhook security hardening. PR #110 merged `f68bdee1`, tagged. (CHANGELOG)
- **v1.20.0** RELEASED — CVE auto-patch-loop hardening. PR #109 merged `9da73458`, tagged. (CHANGELOG + retro)
- **Stripe checkout A–F** all MERGED to main across the 5 shopping-cart repos (2026-08-02); enablement
  PRs (#47/#66) merged; payment side live on hostinger. Remaining *live acceptance* work is workstream
  G above (v1.25.0). Deep saga detail is in git history + `docs/issues/2026-08-02-*`.
- Branch-protection approval count restored (`0→1`) on shopping-cart-infra #89 + order #63 (task #4, done).
