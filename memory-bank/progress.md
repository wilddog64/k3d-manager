# Progress — compressed operational log

Compressed 2026-10-19. Detailed history before 2026-10-17 is summarized in `memory-bank/archive/2026-10-07-to-2026-10-16-compressed.md`; the prior full file remains recoverable from git history.

## 2026-10-19

- Investigated Slack job `8417cf04` / E2E run `1792410757-29778`. ACG credentials and both Kubernetes APIs passed preflight. The 420s hub-app gate failed on frontend `Synced/Degraded` and product-catalog `OutOfSync/Healthy`.
- Read-only cluster diagnosis: frontend pod `frontend-bfb7667c-698wr` was `CrashLoopBackOff`; Nginx logged `host not found in upstream "product-catalog.shopping-cart-apps.svc.cluster.local"`. Product-catalog synced/healthy later, leaving frontend degraded. No live mutation performed.
- Filed detailed evidence issue plus canonical P2 dashboard bug record; pushed through `dc906243`.
- Operator reported PR Checks panel 8 “Check duration” legend clipping. Filed P3 `docs/bugs/2026-10-19-pr-checks-check-duration-legend-clipped.md`, linked it to the populated-table bug, and made no dashboard change.

## 2026-10-18

- v1.43.4 merged/tagged/released; v1.43.5 branch cut and appsets reapplied. Platform-ops rollout and dashboard work continued on v1.43.5.
- PR Checks shopping-cart repository coverage landed at `10b49424`; live Hermes rollout/E3 remains pending. Empty PR table display fix `248558d7` is LIVE-VERIFIED.
- e2e-sandbox-provision preview landed and was LIVE-VERIFIED at `8de20c0b`.
- Slack confirm-keyword fix landed at `aef07289`; thread broadcast fix landed at `93d8cf77`; thread actor fix at `bc1399eb`.
- P1 register-app-cluster role-lookup defect was found in live e2e job `f5e6229f`, approved, and fixed at `a70e52a4`; live E2 rerun remains pending.
- Frontend cache TTL fix was deployed; operator still needs Cloudflare “Respect Existing Headers” and an E2 check.

## 2026-10-17 and earlier active decisions

- e2e sandbox provisioning and settle-wait fixes are landed and independently tested; the current failure is a separate app bootstrap ordering problem.
- Hostinger Vault watchdog, AWS teardown, dependency-token automation, image-pin drift, live-evidence recording, and dashboard lifecycle work are tracked in their respective `docs/bugs` / `docs/plans` records.
- v1.43.5 plan cap is reached. v1.43.6/v1.43.7 work is planned separately; do not add new release plan files without operator direction.
- Historical DR, hub-data export/recovery, ACG, provider, and release details are in the compressed archive and repository history.

## Required next checks

1. Operator chooses a bounded fix for the frontend/product-catalog startup race and runs a fresh live E2E.
2. Investigate the PR Checks table transformation issue using actual Grafana frames before modifying JSON.
3. Investigate panel 8 legend sizing/layout and verify with a live screenshot after any approved fix.
4. Re-run the relevant acceptance tests and update bug statuses only after evidence exists.
