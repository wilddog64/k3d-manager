# Progress — k3d-manager

> Compressed 2026-09-17 (v1.34.0 Grafana/observability block closed → collapsed to pointers).
> Full pre-compression detail: `memory-bank/archive/progress-2026-09-17.md`.
> Settled work lives in `CHANGELOG.md`, `docs/releases.md`, `docs/retro/`, `docs/issues/`,
> `docs/bugs/` and git history. This file tracks what is still open.

## Open items

- [ ] **HTTP/2 failure-rate observability** — deferred until Tier 2 E2E coverage publishes bounded protocol/version labels. Current dashboard intentionally does not claim HTTP/2-specific failure rates; see `docs/issues/2026-09-16-http2-failure-rate-tier2-dependency.md`.

- [ ] **Hermes scheduled `make status` sensor + triage — IMPLEMENTED `e3e37f96`, live acceptance pending.** Spec `docs/plans/v1.34.0-hermes-scheduled-status-triage.md`. Runs `bin/cluster-status --json` on a ~40 min gate inside the existing 300s Hermes poll, classifies reds by check id, notifies on state change only, files bugs via the e2e worktree path. No new launchd agent, no new REPAIRS entry, no auto-execution (proposal + Slack approval only). Offline gates green (Hermes pytest 106, status-summary BATS 8/8). **The schedule defaults off**: set `K3DM_HERMES_STATUS_ENABLED=1` only after the Prometheus authenticated-probe dependency is verified, or the first run pages on a false red. Corrections and findings: `docs/issues/2026-09-16-hermes-status-triage-review.md`.

- [ ] **Hook fix PR (step 2 of 3)** — branch `fix/keycloak-reconcile-pipefail-ldap-federation`
  @ `a5838c19`, one commit ahead of the new main. Conflict pre-check (previously blocked
  by the auto-mode classifier) now RUN against merged main: `git merge-tree origin/main
  <branch>` → exit 0, merged tree `6678e606`, no conflict section = merges cleanly.
  Needs: own CHANGELOG entry (deferred to avoid colliding with #96's), Copilot review, CI.

- [ ] **lib-foundation: ACG session-check false-green — bug filed, Codex assigned.**
  Spec `docs/bugs/2026-09-12-acg-session-check-false-green-on-signed-out-page.md`
  (commit `ecfc15f`, pushed on `fix/acg-prism-monogram-selector`). Removes the two
  page-CONTENT selectors (`text=/Cloud Sandboxes/i`, `text=/Open Sandbox/i`) from
  `LOGGED_IN_SELECTORS`, adds `SIGNED_OUT_SELECTORS` + `pageLooksSignedOut` /
  `urlLooksSignedOut` as a negative gate, and makes `acg_session_check.js` say out loud
  when the `k3dm-acg-pluralsight` Keychain item is missing. Handed to Codex via
  `codex exec`. **IMPLEMENTED `308bb3c`** (Codex authored; Codex could not write `.git`,
  so Claude re-ran every gate and committed). Gates Claude ran, not taken on trust:
  `npm run check` clean, jest 25/25 across 7 suites, `make lint`, `make shellcheck-lib`,
  132 BATS — all green. CHANGE.md `[Unreleased]` entry added by Claude; still collides
  with lib-foundation #49, rebase whichever lands second.
  Files in scope: `pluralsight_login.js`, `acg_session_check.js`,
  `tests/providers/pluralsight_login.test.js`. Operator action still required before the
  live gate can pass: create Keychain item `k3dm-acg-pluralsight` (username+password) OR
  sign in once manually in `~/.local/share/k3d-manager/pw-profile`. MFA accounts can only
  use the manual path.

- [ ] **Portability Phase 3 inventory recorded** in
  `docs/bugs/2026-07-07-app-cluster-vault-portability.md` (24 `--context ubuntu-k3s`
  sites in `shopping_cart.sh`, 3 functions, resolver already present). Still needs the
  decision-#1 re-scope + swallowed-failure fix before a spec.

- [ ] **2026-09-14 — `/k3dm` Slack make-target command** — spec `docs/plans/v1.34.0-slack-k3dm-make-command.md` (`d8a2c8d8`); implemented + verified `cfbdddde`; webhook restarted; worker deploy pending user `make deploy-worker` (GH `CLOUDFLARE_API_TOKEN` secret missing → CI deploy fails); Slack app `/k3dm` registration pending user

- [ ] **v1.28.0-platform-zero-downtime-rollouts — QUEUED, hardware-gated** (deferred 2026-09-04).
  No CPU headroom on the M4 Air 24GB hub for 2+ replicas of the stateless tier (hub CPU-starves at
  single replicas). Gated on the Mac Mini M5 upgrade (Oct 2026). Spec stays on disk; do NOT implement
  until the hardware lands.

- [ ] Keep all new work within the five-plan milestone limit (at 5/5 — split before a 6th).

- [ ] **Hub control-plane saturation/public 502 incident (2026-09-02):** API `/readyz` reports
  etcd failures while k3s server reaches ~880% CPU; Grafana port-forward flaps and ArgoCD public
  OAuth URL drifted to the local hostname. Bug recorded in
  `docs/issues/2026-09-02-hub-control-plane-saturation-causing-public-502.md`; workload-level
  mitigation and durable URL/status fixes remain pending.

- [ ] **Argo identity drift + stale dashboard route (2026-09-02):** Git Keycloak Service renders
  valid ports but Argo strategic merge still produces duplicate `http`; Grafana dashboard links
  include a stale route. Bug: `docs/issues/2026-09-02-argocd-identity-drift-and-dashboard-502.md`.

- [ ] **E2E observability follow-up:** M2 result ConfigMaps publish correctly, but the live
  Prometheus deployment currently has no `e2e_run_info` series and the `Recent runs` Grafana
  panel shows duplicate exporter/application service columns plus blank legacy totals. Bugs:
  `docs/issues/2026-08-25-e2e-grafana-table-raw-labels.md` and the contract-mismatch issue above.
  Dashboard source fix `cfe925fc` is pushed; it uses `exported_service` as the canonical service
  filter, hides exporter `service`, and renames table fields. E2E client fix `0c2505b` is pushed
  on `shopping-cart-e2e-tests:feat/e2e-image-multiarch`; full repo `tsc` remains red only on
  pre-existing unrelated test strictness/type errors.

- [ ] **CVE remediation event panels empty (2026-08-24) — ROOT-CAUSED 2026-08-25.**
  NOT a durability bug (Codex RC wrong). Durable source (event ConfigMaps) exists; 0 series
  is correct because 0 events exist. Real RC: Keychain `platform-ops-app-rebuild/k3dm` absent
  → secret never synced → `app-cve-scan` pod wedged in `CreateContainerConfigError` → requester
  never runs. Fix = user stores scoped PAT + re-run `argocd_sync_app_rebuild_secret` + delete
  wedged job `cve-auto-1787541034`; then hardening (fail-loud + bounded backoff) + dashboard
  no-data annotation. Corrected diagnosis in `docs/issues/2026-08-24-cve-remediation-panels-empty.md`.

- [ ] **Image signing / CVE-loop closure** (`docs/plans/v1.27.0-image-signing-cve-loop-closure.md`)
  — cosign sign+attest, Kyverno Audit→Enforce, promoter verify gate. Multi-repo, heavy.

- [ ] **Frontend inline attest — spec WRITTEN 2026-08-31, Codex NOT dispatched.** `shopping-cart-frontend` inlines its
  own build/sign in `ci.yml` `publish` job (no reusable-workflow `uses:`) — signs but no attestation. Spec
  `docs/plans/v1.27.0-image-signing-frontend-inline-attest-codex-task.md`: insert 3 steps (trivy `cosign-vuln` +
  `spdx-json` predicates by digest → `cosign attest --type vuln`/`--type spdxjson`) after `Sign image by digest`, trivy
  pin reused `v0.36.0`, branch `feat/frontend-inline-attest`, exact msg `ci: attest frontend image (vuln + SBOM) inline by digest`.

- [ ] TWO-CLOUD (hostinger as 2nd registered cluster) NOT yet done — this run was k3s-aws only; hostinger node up but not registered into hub.
- Note (follow-up, unfiled): two LDAP instances in identity ns (openldap-0 StatefulSet + stray ldap
  Deployment) — confirm Keycloak federation binds openldap-0, not the stray, before v1.28.0 PR.
# 2026-09-09 — Hermes Kine guard in progress

## Shipped in v1.34.0 (detail in CHANGELOG `[Unreleased]` and the linked issues)

- [x] **Hermes Status Grafana dashboard** (`60a04c19`, label fix `6a58f77f`, stat rendering `7fa75dd6`,
  scrape-metadata hiding `025a0d41`, target scopes `1cb69566`). Hermes publishes a redacted snapshot of
  every sensor finding; regular sensors publish even while `status_checks` is off.
  `docs/issues/2026-09-17-hermes-grafana-visibility.md`.
- [x] **E2E Grafana drill-down** — failure groups `6c8b834d` (exporter normalization `8c80aeb9`),
  test-level details `facf30fa`, owning-service labels `dece8c63`/`2830b32c`, cross-service
  classification `c691eb92`. Live backfill evidence:
  `docs/issues/2026-09-16-live-e2e-failure-groups-empty.md`.
- [x] **E2E Grafana trends** — trend/cause/spec panels `3c33103a`, placement + owning-service column
  cleanup `387f019e` (verified live; stale-layout note in
  `docs/issues/2026-09-16-e2e-grafana-dashboard-stale-layout.md`), failure ratio `5b8a90fc` →
  `455b87ac` → `afff9ae0`, column ordering `d63a5753`…`7e7ec231`.
- [x] **Dashboard responsiveness** — E2E refresh/row caps `5202feb1`/`9866d119`, CVE tables bounded to
  `topk(500, ...)` over 7,409 series `5a788cf3`, CVE Service column dropped `d42fc601`.
  `docs/issues/2026-09-17-cve-dashboard-freeze.md`.
- [x] **Webhook/status credential recovery** — configured Cloudflare token key `2991cc23`, empty-token
  recovery `2ba24c74`, stale-token fallback `6e86ad43`, bounded liveness probe `916d1a0b`, keychain
  auth diagnosis `85a05c7e`. `docs/issues/2026-09-16-status-webhook-health-timeout.md`.
- [x] **Live SSO + remote E2E recovery** — the Keycloak PostSync hook failed because
  `quay.io/keycloak/keycloak:24.0` ships no `awk`; ArgoCD public OIDC URL aligned `c219eab7`.
  `docs/issues/2026-09-16-live-sso-e2e-recovery.md`.
- [x] **Two dashboards diagnosed as no-data-by-design, not broken** — checkout load-test
  (`docs/issues/2026-09-17-checkout-loadtest-dashboard-no-data.md`) and k3dm deployment
  (`docs/issues/2026-09-17-k3dm-deployment-dashboard-no-data.md`); both await a publisher, not a fix.

## Release ledger

Canonical: `docs/releases.md` (full history) and the README releases table (3 most recent).
Per-release detail: `CHANGELOG.md` and `docs/retro/`.

## Process (standing rules — do not archive)

- Every implementation updates this file and `activeContext.md` with the real commit/PR SHA.
- Unexpected live failures get a dated `docs/issues/YYYY-MM-DD-*.md` record with verbatim evidence.
- Historical specs/issues are archived only when superseded or unreferenced; files are never deleted.
- Keep all new work within the five-plan milestone limit. **v1.34.0 is at 5/5 — the next spec opens v1.35.0.**
- Reapply the ApplicationSets (hub and ACG) every release, then run `argocd_check_values_branch`.
