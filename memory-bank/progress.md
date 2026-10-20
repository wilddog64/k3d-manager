# Progress — compressed operational log

Compressed 2026-10-19. Detailed history before 2026-10-17 is summarized in `memory-bank/archive/2026-10-07-to-2026-10-16-compressed.md`; the prior full file remains recoverable from git history.

## 2026-10-19

- Investigated Slack job `8417cf04` / E2E run `1792410757-29778`. ACG credentials and both Kubernetes APIs passed preflight. The 420s hub-app gate failed on frontend `Synced/Degraded` and product-catalog `OutOfSync/Healthy`.
- Read-only cluster diagnosis: frontend pod `frontend-bfb7667c-698wr` was `CrashLoopBackOff`; Nginx logged `host not found in upstream "product-catalog.shopping-cart-apps.svc.cluster.local"`. Product-catalog synced/healthy later, leaving frontend degraded. No live mutation performed.
- Filed detailed evidence issue plus canonical P2 dashboard bug record; pushed through `dc906243`.
- Operator reported PR Checks panel 8 “Check duration” legend clipping. Filed P3 `docs/bugs/2026-10-19-pr-checks-check-duration-legend-clipped.md`, linked it to the populated-table bug, and made no dashboard change.
- Reviewed non-archive `docs/` architecture and flow diagrams against the current tree. Converted boxed/ASCII diagrams to Mermaid, corrected Cloudflare relay `/ask-docs` and 31-target claims, and marked the Istio ingress page as a legacy path. Commit: `ef058487`; review record: `docs/issues/2026-10-19-docs-architecture-diagram-review.md`.
- Added a dedicated Hermes operations section to `README.md` with direct guide/scope links and a Mermaid observe→correlate→report→approve→repair lifecycle. Commit: `bb4a2f64`; `make check-doc-links` passed.
- Added an explicit Hermes entry to the README Architecture index after confirming the rendered list was missing it. Commit: `e9d1fddb`; `make check-doc-links` passed.
- Filed and dispatched `docs/bugs/2026-10-19-bug-dashboard-verification-tile-labels-clipped.md`; dispatcher task completed and landed `5819e236`. Verification: 22/22 `grafana_dashboard_bugs.bats`, `check-doc-links: 2220 file(s) OK`; operator live-verified the full `Verified` and `Live-verified` labels on the hub `k3dm-bugs` dashboard.
- Filed and dispatched `docs/bugs/2026-10-19-e2e-sandbox-provision-frontend-upstream-race.md`; dispatcher task landed `4ebaaec5`. The fix restarts `deployment/frontend` once after product-catalog becomes `Synced/Healthy` while frontend remains `Synced/Degraded`. Offline verification passed: focused `e2e_sandbox_preflight.bats` 35/35, shellcheck, and `_agent_audit`. Operator-confirmed Slack job `f8ea6d69` completed E2E run `1792450928-16408` with 4/4 passed and exit code 0; canonical bug is now `LIVE-VERIFIED`.
- Dispatched the canonical Slack Make-log lookup fix from `docs/bugs/2026-10-06-cloud-bridge-make-job-status-empty-output.md`; `d5e7b7f5` records the target marker in Slack-thread Make job directories so `make.log` is selected. Relevant BATS passed 14/14; focused Python tests passed 17/17; compile and `_agent_audit` passed. Bug is `VERIFIED`; live Slack verification remains operator-owned.
- Dispatched the existing explicit Slack job-ID mismatch bug after live reproduction `d5261dfb` (thread anchor) versus `26f2035e` (Make child with `make.log`). Fix `177ba541` honors explicit IDs, rejects cross-thread access, and selects the newest non-anchor for bare `logs`. Focused Python tests passed 25/25; relevant BATS 14/14; syntax validation and `_agent_audit` passed. Operator then ran the Slack-originated E2E flow: job `26f2035e` completed successfully and E2E run `1792455493-30189` returned `exit_code=0` / `result=pass`. Bug is now `LIVE-VERIFIED`.
- Dispatched P3 `docs/bugs/2026-10-19-pr-checks-grafana-tables-misaligned-populated-state.md` as `pr-checks-table-misalignment`; dispatcher created the isolated worktree and implementation remains pending.
- Corrected the dispatch spec's test path to `scripts/tests/plugins/grafana_dashboard_pr_checks.bats`; non-network retry `pr-checks-table-misalignment-r5` was created but its worker exited before writing Codex output, leaving implementation pending.
- Dispatched the corrected PR Checks bug through the repaired dispatcher. Codex changed the two dashboard table panels and regression test; independent focused BATS and the land gate passed 4/4, ShellCheck and `_agent_audit` passed. Commit `1a1c33d8` landed on `k3d-manager-v1.43.5`; bug is `VERIFIED`, with live Grafana verification still pending.
- Operator live screenshot after `1a1c33d8` showed panel 6 still misaligned: durations under `PR`, `No open PRs — no checks to show` under `State`, and `Value #A` visible. Reopened the canonical bug; no follow-up implementation made.

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
5. Push and verify documentation review commit `ef058487`; Mermaid rendering was unavailable locally because `mmdc` is not installed.

## 2026-10-20 dispatcher investigation

- Confirmed the process-group cleanup root cause of silent dispatch worker loss and recorded the evidence in the P1 bug doc; Codex dispatch of the fix is the next step. Grafana table fix is on hold behind it.
- Dispatcher P1 is `LIVE-VERIFIED` from the real Codex CLI smoke run (`2de716d8`; run `live-smoke-codex-cli`, E2 recorded in the bug doc). PR Checks table correction is tracked below as `VERIFIED` pending live dashboard confirmation.

## 2026-10-20 PR Checks table unit correction

- Dispatched `pr-checks-table-unit-fix` for the remaining populated Checks per PR display defect. Panel 6 applied seconds formatting to every numeric field, so PR numbers such as 62 and 56 rendered as `1.03 mins` and `56 s`. Commit `9787ce98` moves the seconds unit to a `Duration` field override.
- Independent verification: `bats scripts/tests/plugins/grafana_dashboard_pr_checks.bats` passed 4/4; `shellcheck -x scripts/tests/plugins/grafana_dashboard_pr_checks.bats` exited 0; dispatcher land gate reran the BATS suite and passed. Pushed to `origin/k3d-manager-v1.43.5`. Bug status is `VERIFIED`; live Grafana check remains pending.
