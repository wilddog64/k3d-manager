# Active context — k3d-manager-v1.43.5

This file was compressed on 2026-10-19 because the active memory-bank exceeded 700 KB and was approaching the repository's 200K-token context-compaction boundary. Older detail is summarized in `memory-bank/archive/2026-10-07-to-2026-10-16-compressed.md`; the pre-compression files remain recoverable from git history.

## Current branch and operating rules

- Branch: `k3d-manager-v1.43.5`, tracking `origin/k3d-manager-v1.43.5`.
- Current remote HEAD before the current push: `dc906243`; documentation review commit is `ef058487` locally and pending push.
- Do not create PRs; finish scoped work at commit + push + memory-bank update.
- Live verification is operator/Claude-owned; Codex may perform read-only diagnostics when explicitly requested.
- Release plan cap: v1.43.5 has five plan slots; do not add another plan without splitting/releasing.
- Required completion evidence: remote commit SHA, relevant BATS output, shellcheck, and `_agent_audit`.

## Latest live investigations and records

- Slack job `8417cf04`, E2E run `1792410757-29778`: preflight passed, but the 420-second hub-app gate failed with frontend `Synced/Degraded` and product-catalog `OutOfSync/Healthy`. Read-only diagnosis found frontend Nginx exiting because `product-catalog.shopping-cart-apps.svc.cluster.local` did not exist when frontend started. Product-catalog later became healthy, but frontend remained `CrashLoopBackOff`. Detailed evidence: `docs/issues/2026-10-19-e2e-sandbox-provision-frontend-upstream-race.md`; dashboard-facing bug: `docs/bugs/2026-10-19-e2e-sandbox-provision-frontend-upstream-race.md` (P2 OPEN).
- PR Checks dashboard: panel 5/6 populated-table transformation issue is recorded in `docs/bugs/2026-10-19-pr-checks-grafana-tables-misaligned-populated-state.md` (P3 OPEN).
- PR Checks dashboard: panel 8 Check duration legend clipping is recorded in `docs/bugs/2026-10-19-pr-checks-check-duration-legend-clipped.md` (P3 OPEN). No dashboard implementation change has been authorized.
- Documentation review commit `ef058487` converted current non-archive flow/architecture diagrams to Mermaid, corrected Cloudflare relay drift, and labeled the legacy ingress path. Review record: `docs/issues/2026-10-19-docs-architecture-diagram-review.md`.
- Remote pull verified: `fa472803` added the PR Checks bug doc; `09dff92e` changed the product-catalog image pin. They were not two Markdown docs.

## Recent completed work

- `dc906243`: documented the clipped PR Checks legend, cross-linked it to the populated-table bug, and pushed the update.
- `e3a6d040`: added the canonical dashboard bug record for the e2e frontend upstream race.
- `a43f0b58`: merged the two remote branch commits without rebasing or force-pushing.
- `94810283`: recorded the full e2e upstream-race investigation.
- PR Checks shopping-cart repository coverage fix `10b49424` is landed; hub Hermes live rollout remains pending.
- PR Checks empty-table display fix `248558d7` is LIVE-VERIFIED.
- e2e sandbox settle-wait fix is LIVE-VERIFIED by run `1792355973-27075`; the later `8417cf04` failure is a distinct startup-order race.

## Open / pending

- E2E frontend/product-catalog bootstrap-order fix: scope and implementation not approved.
- PR Checks table transformation fix: investigation/fix pending.
- PR Checks panel 8 legend layout fix: investigation/fix pending.
- Frontend Cloudflare cache TTL: origin is 5m but Cloudflare browser TTL was 14400; operator must set “Respect Existing Headers” and recheck.
- P1 register-app-cluster role-lookup fix `a70e52a4`: live E2 rerun pending.
- Hostinger Vault watchdog and several teardown/dashboard items have their live follow-ups recorded in the bug docs and recent progress below.

## Verification from latest work

- `bats scripts/tests/plugins/e2e_sandbox_preflight.bats`: 34/34 passed.
- `shellcheck scripts/plugins/e2e.sh`: clean.
- `_agent_audit`: passed.
- PR Checks/bug dashboard tests: 66 passed.
- Documentation checks: `make check-doc-links` passed (`2218 file(s) OK`); targeted `bats scripts/tests/lib/bats_negation_lint.bats` failed on its existing assertion at line 6; no shell files were changed.

Use the bug docs for acceptance criteria and the archive for historical context; do not re-derive old decisions silently.
