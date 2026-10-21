# Progress — compressed operational log

## 2026-10-21 review of two Slack command bugs

- Reviewed P3 `docs/bugs/2026-10-15-slack-find-similar-docs-free-text-q-parsing.md`: confirmed it covers both thread free-text parsing and slash-command Q validation/acknowledgment, including the shell-injection boundary. Operator authorized dispatch; added a bounded `## Files` scope for parser/relay/validation, Make invocation, tests, and help docs.
- Dispatched P3 `slack-find-similar-docs-free-text-q` in isolated worktree `/Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/slack-find-similar-docs-free-text-q`. Worker exit 0; worker-reported final gates: relay Node tests 47/47, focused pytest 124 passed plus 97 subtests, and webhook/slash-command BATS 76 passed / 6 skipped. Initial pytest had one `Q=$(x)` safety-test failure, subsequently reported green. `scripts/lib/webhook/lifecycle.py` was changed outside the original file scope because it implements the safe Make argv boundary; this file was added explicitly to the canonical scope after review. Candidate is not independently reviewed or landed. Worker `_agent_checkpoint` created local commits `a0c5f01b` and `4caf1b6b` despite the prompt's Git restriction; no push occurred. Dispatcher initially reported `terminated unexpectedly` while its log continued, then eventually reported `exited successfully`; details in `docs/issues/2026-10-21-slack-find-similar-docs-dispatch-status-and-scope.md`.
- Reviewed P3 `docs/bugs/2026-10-15-e2e-slack-runner-interface-inconsistent.md`: implementation is explicitly a v1.46.0 candidate subject to release prioritization; no v1.46.0 branch exists, while this checkout is v1.43.5. Operator directed to hold it for v1.46.0 triage; no dispatch created.

## 2026-10-21 MinIO status observability gap

- Filed `docs/bugs/2026-10-21-hermes-minio-upload-status-not-visible.md` as an OPEN P3 observability bug, separate from the fixed MinIO uploader runtime-install bug. Code review confirmed the webhook's `Data layer` result is based on four StatefulSet readiness checks and Hermes reports the aggregate, not the upload hook's last result. Acceptance covers explicit success/failure/unknown, timestamped and sanitized evidence, and failed-to-successful alert recovery. Implementation approval remains pending.
- `make check-doc-links` and staged `_agent_audit` passed; no application code changed.

## 2026-10-21 MinIO verification and cart-badge dispatch follow-up

- Marked the MinIO uploader fix LIVE-VERIFIED: `shopping-cart-infra` main contains `83e8880d6dba22ebe3ffda36f052d7ce870887d7`; focused BATS passed 8/8. Live evidence combines the recorded successful PostSync Jobs and storefront images with operator screenshots showing ArgoCD Synced/Healthy and Hermes data-layer 4/4 ready/no superseded failed Jobs. Operator could not locate the historical resolved notification; the unrelated `ubuntu-k3s/trivy-system` notification was excluded, and this evidence limitation is explicit in the canonical bug.
- Confirmed the cart-badge dispatch candidate remains in `/Users/cliang/.codex/worktrees/bdce/shopping-cart-frontend` (session `01a15e8a-082b-71a1-a06f-d2792259984b`), with 37/37 Vitest tests and lint passing. The build is still blocked by missing `@tailwindcss/postcss`; it has not been committed or landed. Details: `docs/issues/2026-10-21-cart-badge-dispatch-build-dependency-missing.md`.

## 2026-10-21 MinIO and cart-badge bug review/dispatch

- MinIO image-upload bug was already implemented in `shopping-cart-infra` main at `83e8880d6dba22ebe3ffda36f052d7ce870887d7`; no duplicate dispatch was created. Current PostSync uploader manifest has no runtime `pip install`, and `bats scripts/tests/bin/minio-image-upload-job.bats` passed 8/8. Live hook success and product images were recorded earlier; resolved-alert evidence is still outstanding in the bug doc.
- The cart-badge bug was not already fixed: `Header.handleLogout` only called `signoutRedirect`, and persisted `itemCount` was not keyed to an identity. Dispatched an isolated Codex implementation in `/Users/cliang/.codex/worktrees/bdce/shopping-cart-frontend`, session `01a15e8a-082b-71a1-a06f-d2792259984b`. Candidate changes are limited to Header/useCart and their tests; user-owned untracked documents in the main frontend checkout were left untouched.
- Independent candidate validation: focused Vitest 11/11, full `npm test` 37/37, `npm run lint` passed, and `git diff --check` passed. `npm run build` failed because the existing dependency installation cannot resolve `@tailwindcss/postcss`; no network install was attempted. Candidate remains uncommitted/unlanded pending full build validation and review. Exact output/follow-up is in `docs/issues/2026-10-21-cart-badge-dispatch-build-dependency-missing.md`.

## 2026-10-21 Grafana bug dashboard hard refresh

- Applied `kubectl --context k3d-k3d-cluster -n cicd annotate application hub-grafana-dashboards argocd.argoproj.io/refresh=hard --overwrite`; output: `application.argoproj.io/hub-grafana-dashboards annotated`. Verified Argo consumed the annotation; reconciliation at `2026-10-21T12:23:22Z`, `sync=Synced`, `health=Healthy`, `operation=Succeeded`. No sync or manifest change was requested.

## 2026-10-21 Slack thread actor live verification

- Operator replied `k3dm fix-list` in a bot thread. Job `4148ca73` succeeded and its start notice displayed `started by slack-thread:U4C9LDQP2`. This proves the thread-started job records the Slack user rather than only the role. Updated `docs/bugs/2026-10-18-slack-thread-jobs-record-role-not-user.md` to LIVE-VERIFIED; fix commit `bc1399eb`.

## 2026-10-21 dispatch outbound lifecycle thread-context bug

- Updated existing P3 `docs/bugs/2026-10-15-cluster-up-progress-slack-thread-missing.md` with current operator screenshot evidence, explicit dispatch authorization, and file/scope allowlist. Scope is async outbound lifecycle thread preservation; the cloud-bridge Make incident and incoming `thread_broadcast` issue are excluded. `make check-doc-links` passed (`2267 file(s) OK`); `_agent_lint` and `_agent_audit` passed. Pushed scope commit `89514d35`.
- Dispatched as `cluster-up-progress-thread-context`. The worker finished with two allowed out-of-scope changes (bug evidence and regression tests); reviewed the patch and independently verified it. Focused pytest passed 74/74, webhook BATS had 68 passing cases including 6 environment-gated skips, Python AST and diff-check passed, and `_agent_audit` passed. ShellCheck is inapplicable to the Python webhook entrypoint. Committed as `c681227d`, land gate passed, and pushed as `6b324441` on `origin/k3d-manager-v1.43.5`. Canonical bug is VERIFIED offline; operator live Slack confirmation is next. No AWS or cluster lifecycle operation was run.
- Closeout workflow recorded in `activeContext.md`: independently verify dispatch results, commit unfinished worker changes, land/push, mark VERIFIED offline, then proactively hand off exact live-verification steps; only operator live evidence can advance to LIVE-VERIFIED.
- One unprivileged post-land webhook BATS attempt was blocked by localhost binding (`curl` connection failures; test helper status assertions failed). Re-running the same suite with approved local-server permission passed all cases. Details are recorded in `docs/issues/2026-10-21-webhook-bats-sandbox-localhost-bind.md`.
- Operator live verification: Hostinger `cluster-resume` job `6cb1f04b` showed queued, started, and succeeded messages in the same Slack thread, all with the same job ID. Marked the bug LIVE-VERIFIED. Since this job completed in 0 minutes, it did not exercise a live timed-progress post; the cluster-up progress timer is covered offline.

## 2026-10-21 Slack help live verification and landing

- Landed the dispatched fix for `2026-10-15-slack-k3dm-help-no-response-during-cluster-up` as `61230daa` on `k3d-manager-v1.43.5` and pushed it to origin. Verification: canonical webhook BATS `1..68` passed (5 expected skips); focused pytest `29 passed`; ShellCheck, diff check, `_agent_lint`, and `_agent_audit` passed. Initial sandboxed BATS attempts could not bind the temporary localhost server; rerunning through the approved elevated path passed, with tripwire blocking 74 credential-tool calls.
- Operator screenshot live-verifies `/k3dm targets` returning while AWS `cluster-up` is still running. It also shows lifecycle progress as a top-level notification rather than a thread reply; this is a distinct existing P3, `docs/bugs/2026-10-15-cluster-up-progress-slack-thread-missing.md`, and remains OPEN.

## 2026-10-21 documentation bug dispatch queue

- Reviewed P3 bugs for README/Hermes duplication, the monolithic Grafana guide, and CVE/Trivy GitHub rendering failure; pushed the authorization/scope update as `b05ccf6c`.
- Dispatched sequentially: `readme-hermes-operations-deduplicate` and `grafana-dashboard-guide-split` exited successfully, were independently reviewed, and pushed as `2c32ad31` and `802c21c8`. Each dispatcher landing gate passed `make check-doc-links` (2248 files). README now has only one Hermes entry in Guides, with the diagram and scope navigation retained in `docs/guides/hermes.md`; Grafana now has a short index, 14 dashboard-specific guides, and shared operations guidance. Grafana's intended child Markdown files triggered the dispatcher's literal-directory scope warning; paths were reviewed against the bug spec and landed with the documented `--allow-out-of-scope` option. Operator screenshots confirmed both GitHub-rendered layouts on 2026-10-21; both bugs are LIVE-VERIFIED. The networked `cve-guide-github-render-investigation` exited successfully; GitHub returned HTTP 200 for the examined pages, but the operator's browser check is pending. Scope findings: `docs/issues/2026-10-21-docs-dispatch-scope-and-spec-edit-findings.md`.
- The operator clarified that the CVE-title issue is the Grafana Bug Tracking row click returning a GitHub 404 (`docs/bugs/.md`), not the architecture guide failing to render. Offline fix `2036253f` plus test follow-up `7cea0f18`; operator now live-confirms one Bug Tracking row opens its GitHub Markdown document without a 404. Existing P2 `2026-10-19-grafana-bug-dashboard-links-empty-branch-and-stem` is marked LIVE-VERIFIED; second distinct row from the original E2 criterion was not evidenced. The separate guide-render investigation returned GitHub HTTP 200 and was the wrong issue to focus on. Focused dashboard tests also exposed an unrelated stale default Release value (`v1.43.4` vs branch `v1.43.5`); see `docs/issues/2026-10-21-grafana-bug-dashboard-release-default-stale.md`. Scope findings: `docs/issues/2026-10-21-docs-dispatch-scope-and-spec-edit-findings.md`.
- Operator authorized a scoped offline implementation dispatch. Task `grafana-bug-dashboard-links-live-repro-fix` started in-scope after retrying the dispatcher fetch with approved network access; the worker itself is non-networked and cannot deploy live Grafana changes.
- Independently reviewed and landed its test-only follow-up as `7cea0f18`. `bats scripts/tests/plugins/grafana_dashboard_bugs.bats`: 21 passed, 1 expected release-branch-only skip on the task branch. ShellCheck, `_agent_audit`, and `git diff --check` passed. Dashboard manifest unchanged; P2 remains OPEN for live ArgoCD/Grafana sync and row-click verification.

## 2026-10-20 Hostinger provider evidence and investigation verification path

- Operator supplied Hostinger support's control-plane review: no customer stop/reboot was recorded at 2026-10-17 17:46:15 UTC; Hostinger attributed the shutdown to a platform-initiated emergency security-patch maintenance restart. No internal actor or job ID was exposed.
- This agrees with the guest journal's `qemu-ga: guest-shutdown called` at 17:46:15 UTC and orderly poweroff. Added an explicit typed live-investigation evidence format and tests without weakening fix-commit evidence checks; marked the incident `LIVE-VERIFIED`. Memory pressure remains a pre-event observation, not a proven cause.

## 2026-10-20 dispatch queue and stale PID recovery

- Dashboard Bug Tracking links: dispatched task `2026-10-19-grafana-bug-dashboard-links-empty-branch-and-stem` exited successfully. Focused BATS was 21 passed with 1 release-branch skip; dashboard JSON and `git diff --check` passed. Worktree remains unlanded; live row clicks remain required.
- Slack help: task `2026-10-15-slack-k3dm-help-no-response-during-cluster-up` had no terminal marker after its worker PID was reused. Root cause: resume used `kill -0` only, unlike status which checks recorded process-start identity. Fixed resume guard and added regression test; commit `e12b9d87` is pushed. The task resumed and exited successfully. The three BATS failures were Python 3.15 incompatibilities from removed `SourceFileLoader.load_module()` calls; the scoped BATS test snippets were updated to modern loader APIs. Independent verification: three targeted BATS cases passed, full webhook BATS 68 passed / 5 expected skips, focused pytest 29/29, `shellcheck`, `git diff --check`, `_agent_lint`, and `_agent_audit` passed. Bug marked VERIFIED offline; implementation remains uncommitted/unlanded in the task worktree, and the operator must run the live Slack check after landing/deployment. Details: `docs/bugs/2026-10-15-slack-k3dm-help-no-response-during-cluster-up.md`.
- Hostinger node outage: added an offline-only dispatch scope/report path, then dispatched it. Task `2026-10-17-hostinger-node-unresponsive-then-rebooted` exited successfully and produced `docs/issues/2026-10-20-hostinger-node-outage-evidence-review.md`. No live SSH, Hostinger panel/API, cluster access, or infrastructure changes. Operator hPanel activity log for 2026-10-17 17:45–18:11 UTC remains necessary to identify who initiated the power-off.

## 2026-10-20 independent verification and live handoff

- Grafana Bug Tracking links: independently reran `bats scripts/tests/plugins/grafana_dashboard_bugs.bats` (21 passed, 1 release-branch-only skip); `shellcheck -S warning -x` and `git diff --check` were clean. Dispatcher land gate passed; fix landed/pushed as `2036253f`. Marked bug VERIFIED offline; two live GitHub row clicks remain.
- Slack k3dm help: independently reran focused pytest (29 passed; pytest emitted a cache permission warning) and `bats scripts/tests/lib/webhook.bats` (59 passed, 6 skipped, 3 failed: tests 25, 66, 67). Kept bug OPEN and changes unlanded; appended exact output to its bug record. No live Slack message sent.
- Hostinger outage: independently reviewed the offline evidence report; `make check-doc-links` passed (2246 files) and report was landed/pushed as `a0c4e6da`. Marked incident classification VERIFIED offline, but the initiating actor is unconfirmed; operator hPanel activity evidence is required for live attribution.

## 2026-10-20 queued bug dispatches

- The Grafana Bug Tracking link task exited successfully in its isolated worktree. Focused `grafana_dashboard_bugs.bats` passed 21 tests (one release-branch-only skip); dashboard JSON validation and `git diff --check` passed. The task changes remain unlanded pending independent review; live URL clicks are still needed.
- Added the missing `## Files` allowlist to `docs/bugs/2026-10-15-slack-k3dm-help-no-response-during-cluster-up.md` so it can be safely dispatched after this scope update is committed and pushed.
- The Hostinger node outage bug remains an investigation-only queue item. No SSH/hPanel access or infrastructure action will be performed without explicit operator direction.

Compressed 2026-10-19. Detailed history before 2026-10-17 is summarized in `memory-bank/archive/2026-10-07-to-2026-10-16-compressed.md`; the prior full file remains recoverable from git history.

## 2026-10-21 dispatch vendor/model attribution plan

- Added `docs/plans/v1.43.7-dispatch-vendor-coordinator-model-telemetry.md` as v1.43.7 plan 2 of 5. It specifies vendor/model provenance per worker attempt and separately for the primary coordinator, backward-compatible unknown handling, bounded dashboard metrics, and regression coverage. It explicitly excludes model routing or automatic selection and establishes this telemetry as a prerequisite to the broader v1.45.1 routing proposal.
- No runtime code or dashboard was changed. `make check-doc-links` passed (3 changed/new files); `python3 -m pytest -p no:cacheprovider scripts/tests/bin/test_check_doc_links.py` passed 24/24; commit `da4761b3` was pushed to `origin/k3d-manager-v1.43.5`.

## 2026-10-21 dispatched bug verification and landing

- `dispatch-dashboard-missing-codex-telemetry` landed as `63d604dd`; focused pytest passed 12/12 and Agent Dispatch dashboard BATS passed 7/7, including the landing gate. Commit-hook `_agent_audit` passed. It was initially marked VERIFIED pending operator confirmation.
- `slack-smoke-target-override` landed as `611bc1f8`; focused unittest passed 39/39 and cloud-bridge pytest passed 83/83, including the landing gate. Commit-hook `_agent_audit` passed. Marked its bug VERIFIED; webhook rollout and explicit-target Slack smoke confirmation remain with the operator.
- Neither live verification was claimed or performed.

## 2026-10-20 dispatch telemetry live verification

- Operator's Grafana screenshot shows the two historical rows retaining elapsed-to-land values (**1.60 mins** and **4.98 mins**) while Codex tokens, time, and run counts are blank. Updated `docs/bugs/2026-10-21-dispatch-dashboard-missing-codex-telemetry-renders-zero.md` to LIVE-VERIFIED. No Slack selector live test was included in this screenshot; that bug remains VERIFIED offline.

## 2026-10-20 Hostinger multi-service P1 investigation

- Read-only diagnosis found repeated M4 frontend/Pushgateway port-forward TCP/6443 timeouts around the outage, followed by forwarding recovery. This supports a transient M4-to-Hostinger Kubernetes API path interruption but does not establish the responsible network segment.
- VPS boot time remained 2026-10-17; k3s was active and no incident-window OOM, link, disk, or I/O kernel journal matches were found. Current API readiness, node/app/data workloads, Vault/ESO readiness, frontend public endpoint, and product API were healthy.
- Fresh Hostinger status job `dc9e4089` completed with 20 OK / 1 fail. The sole failure was ArgoCD direct password login; ArgoCD SSO passed. Operator `make status` screenshot was overall HEALTHY; its Hub snapshot was 270 minutes old and is separate from live service status.
- No runtime recovery action was taken. Canonical P1 remains OPEN pending confirmation of the API-path fault domain and separate ArgoCD direct-login triage. Evidence and exact timeline are recorded in `docs/bugs/2026-10-20-hostinger-multi-service-502-kubernetes-api-timeouts.md`.
- After service recovery, downgraded the canonical record from P1 to P2: current degradation has an SSO workaround, but the outage's API-path root cause remains unknown. The original incident severity is retained as historical context in the bug doc.

## 2026-10-20 Slack Make job-ID notices

- Operator reported inconsistent job-ID visibility during Slack E2E run `05f2be6c`. The queued, started, and progress notices omitted the ID; bare `logs` returned the transcript under `05f2be6c`. Source review found the direct Make webhook created its queued notice before generating the job ID and the shared worker notices omitted it.
- Filed P2 `docs/bugs/2026-10-20-slack-make-job-id-missing-from-status-notices.md` and dispatched task `slack-make-job-id-notices`. Independently reran pytest (26/26), focused BATS (10/10), Python syntax compilation, and `git diff --check`; `_agent_audit` passed. Added deterministic progress and failure notice ID assertions after review found those paths were not directly exercised.
- Fix landed on `k3d-manager-v1.43.5` as `abb0a526`; test follow-up is `cb7f37dc`. Bug is VERIFIED offline; awaiting operator Slack live verification after webhook rollout. No live E2E or infrastructure action was performed.
- Operator Slack live attempt `/make test-all`, job `be53f685`, showed queued, started, progress, and terminal failure notices without IDs; `logs` returned the transcript with the job ID. The command ended rc 2: 1,747 tests, 56 failed. Test 1171 reproduced the tracked macOS `sha256sum` fixture failure; the other failures were not triaged. LaunchAgent plist points at the updated checkout, but process state is unconfirmed. Kept the bug VERIFIED (not LIVE-VERIFIED), updated `docs/bugs/2026-10-20-slack-make-job-id-live-verification-still-omits-ids.md` and the related macOS fixture bug. The plist diagnostic accidentally emitted stored Slack credentials into tool output; values were not copied into the repo, and rotation is recommended.

## 2026-10-20 Slack Make test-all follow-up

- Slack job `c30366d6` completed. Queued, started, progress, and terminal-failure messages consistently included the ID; operator screenshot then confirmed `logs c30366d6` returned the matching transcript. Marked the notice/log-correlation bug LIVE-VERIFIED. The run separately ended rc 2 (1,747 cases, 56 failed); the tracked macOS `sha256sum` fixture failure recurred and 55 other failures were not triaged. Evidence is in `docs/issues/2026-10-20-slack-make-job-id-live-verification-still-omits-ids.md`.
- Confirmed the recurring hub-data `sha256sum` test-fixture failure is already tracked as OPEN P2 in `docs/bugs/2026-10-19-hub-data-bats-fixture-sha256sum-missing-on-macos.md`; appended `c30366d6` reproduction output there. Did not create an umbrella bug for the remaining 55 failures because they span distinct test areas and have not been triaged.

## 2026-10-20 Slack bug dispatch attempt

- Added file scopes and verification gates to the two existing Slack P2 bug specs; pushed as `3e7a2358`.
- Dispatched `slack-smoke-health-diagnostics` and `slack-thread-e2e-replay-ack` as separate non-network tasks. An early status check transiently reported `terminated unexpectedly`; both later completed with exit 0 and final messages. Smoke BATS 10/10 and ShellCheck clean; replay pytest 34/34. No live replay was triggered and neither task was landed. Preserved their worktrees/logs and recorded the timing/status discrepancy in `docs/issues/2026-10-20-slack-bug-dispatch-workers-terminated-unexpectedly.md`.
- Operator requested cleanup of stale dispatch slugs `e2e-sandbox-live-verify`, `pr-checks-table-misalignment-r5`, and `pr-checks-table-misalignment-r6`. Confirmed all worktrees were clean and no matching remote branches existed, then removed the three local worktrees/branches; run directories/logs were retained.

## 2026-10-20 Slack bug verification and landing

- Smoke diagnostics task `slack-smoke-health-diagnostics` landed as `30236df8`; independent BATS passed 10/10, ShellCheck was clean, and `_agent_audit` passed in the commit hook. Bug status is VERIFIED pending operator live Slack check.
- Replay acknowledgment task `slack-thread-e2e-replay-ack` landed as `fd1b40b0`; focused pytest passed 34/34, Python AST syntax validation passed, `_agent_audit` passed, and `scripts/tests/lib/webhook.bats` passed 68/68 with Python 3.14 after obtaining permission for its localhost test-server bind. ShellCheck is not applicable to the Python entrypoint; the environment/tooling details are recorded in `docs/issues/2026-10-20-slack-dispatch-verification-environment.md`. Bug status is VERIFIED pending operator live test; no replay or report publication was triggered.

## 2026-10-21 Slack live verification follow-up

- Operator's Slack `/make smoke` failed (rc 2) and output `diagnostics_unavailable`. The captured cluster-health log shows `[TARGET] expected exactly one shopping-cart target, found 2` with both destinations. The reporter only extracts `[FAIL]` lines, so this live test disproves completion of the diagnostics fix. Reopened the smoke bug; no implementation change made. Full output is in `docs/issues/2026-10-21-slack-live-verification-results.md`.
- Operator's initial `/make e2e-replay RUNNER=m2` completed successfully with `published=0 still pending=0`, but used the direct Make route. Operator then sent bare `k3dm e2e-replay RUNNER=m2` in the E2E thread; queued, started, and succeeded notices all referenced job `3198fa72`, with terminal output `published=0 still_pending=0`. Updated replay bug to LIVE-VERIFIED.
- Dispatched and landed the smoke `[TARGET]` diagnostic follow-up as `36dfb1e2`. It includes `[TARGET]` lines and indented context while keeping output bounded/redacted. Independent BATS passed 11/11, ShellCheck clean, `_agent_audit` passed. Bug is VERIFIED offline; operator must restart the webhook and repeat `/make smoke` for live verification.

## 2026-10-21 Slack smoke target selection

- After webhook restart, operator Slack job `a3d1097b` showed the `[TARGET] expected exactly one shopping-cart target, found 2` diagnostic with both candidate apps and destinations. This live-verifies the reporting fix; the smoke gate correctly remains failed because it must not choose a cluster implicitly.
- Filed P2 `docs/bugs/2026-10-21-slack-smoke-target-override-not-allowlisted.md`: Slack initially permitted only `SMOKE_ONLY` for smoke, preventing an explicit `ARGOCD_APP_PREFIX` selection. Fix landed as `611bc1f8`, then operator live-verified `/k3dm smoke ARGOCD_APP_PREFIX=ubuntu-hostinger-` with job `c4a9465f`; output reported offline PASS, cluster PASS, and 2 passed / 0 failed / 0 skipped. Bug is LIVE-VERIFIED. Evidence status commit `4a8aeaae` recorded the other dispatch bug; this live evidence is being recorded now. No default target behavior changed.

## 2026-10-21 Dispatch dashboard historical metrics

- Investigated screenshot rows `slack-explicit-job-logs` and `slack-make-log-selection`. Ledger contains only `start` and `land` for each; no `codex_exit`. Their elapsed values (96 seconds / 1.60 minutes and 299 seconds / 4.98 minutes) are valid, but tokens are unavailable and zero runs/time are exporter defaults for absent terminal events, not evidence of no Codex work.
- These runs predate `2de716d8`, which added terminal status markers and `codex_exit` events. No telemetry was backfilled and no dashboard changes were made. Findings: `docs/issues/2026-10-21-dispatch-dashboard-legacy-task-metrics-missing.md`.
- Filed P3 `docs/bugs/2026-10-21-dispatch-dashboard-missing-codex-telemetry-renders-zero.md`; scoped to exporter semantics and regression tests only. Dispatched as `dispatch-dashboard-missing-codex-telemetry`; it landed as `63d604dd` and is now LIVE-VERIFIED. Spec was pushed in `fb4b1bb8`.

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
- 2026-10-20: independently reran `argocd_register_role_label.bats` and `argocd.bats` (41/41) plus `shellcheck -x scripts/plugins/argocd.sh` (clean). Updated the canonical bug to VERIFIED; Slack-originated operator live E2 remains pending, so it is not LIVE-VERIFIED.
- 2026-10-20: operator Slack job `05f2be6c` completed E2E run `1792538358-29202`; saved summary reports pass, 4/4, exit code 0. Job log confirms app-cluster registration applied the Secret and set its role label. Read-only hub check shows Secret creation timestamp `2026-10-20T23:26:40Z` and role `app-cluster`. Updated `docs/bugs/2026-10-18-register-app-cluster-role-lookup-exits-silently.md` to LIVE-VERIFIED.
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
- Dispatcher P1 is `LIVE-VERIFIED` from the real Codex CLI smoke run (`2de716d8`; run `live-smoke-codex-cli`, E2 recorded in the bug doc). PR Checks table correction is tracked below as `LIVE-VERIFIED` from Safari-private and Chrome screenshots.

## 2026-10-20 PR Checks table unit correction

- Dispatched `pr-checks-table-unit-fix` for the remaining populated Checks per PR display defect. Panel 6 applied seconds formatting to every numeric field, so PR numbers such as 62 and 56 rendered as `1.03 mins` and `56 s`. Commit `9787ce98` moves the seconds unit to a `Duration` field override.
- Independent verification: `bats scripts/tests/plugins/grafana_dashboard_pr_checks.bats` passed 4/4; `shellcheck -x scripts/tests/plugins/grafana_dashboard_pr_checks.bats` exited 0; dispatcher land gate reran the BATS suite and passed. Pushed to `origin/k3d-manager-v1.43.5` as `9787ce98`. The operator later confirmed the populated table in Safari private browsing and Chrome at deployed revision `f2063dba`; bug status is `LIVE-VERIFIED`.

## 2026-10-20 PR Checks live verification and legend follow-up

- Operator screenshots from Safari private browsing and Chrome show PR identifiers (`62`, `56`) in the PR column and durations in the Duration column after deployment revision `f2063dba`. Updated the PR Checks table bug to `LIVE-VERIFIED`; the no-open-PR behavior was retained from its separately live-verified fix.
- Operator confirmed panel 8's Check duration legend is still clipped. Updated the existing P3 bug with the latest evidence, recorded implementation authorization, and scoped its dispatch to the dashboard YAML and its BATS test.
- Dispatched `pr-checks-legend-clipped`; the task configures panel 8's legend as a right-side list without changing its query or legend format. Focused `bats scripts/tests/plugins/grafana_dashboard_pr_checks.bats` passed 5/5; `shellcheck -x` and `git diff --check` were clean. Dispatcher land gate passed and landed `a5edc7ac` on `k3d-manager-v1.43.5`. Updated the bug to `VERIFIED`; live Grafana confirmation remains for the operator.
- Operator then supplied a post-sync Grafana screenshot showing the multi-series Check duration legend fully readable at the right of the plot. Confirmed Argo CD revision `6385c3c6` had synced and the live ConfigMap carried `legend=right/list`; updated the bug to `LIVE-VERIFIED`. The zero- and one-series layouts were not separately observed.
# 2026-10-21 P2 bug dispatch preparation

- Added dispatcher scope and approval boundaries for six open P2 records shown by the operator. Three are offline implementation tasks; three are read-only diagnosis tasks. No task has been landed or live-verified as part of preparation.
- `git diff --check` and `make check-doc-links` pass (2277 files). The checkpoint helper failed in zsh because `status` is readonly; Bash avoids that. Bash then could not write `.git/index.lock` under the managed sandbox, so changes remain unstaged/uncommitted; exact output and next step are in `docs/issues/2026-10-21-dispatch-preflight-shell-and-git-permission.md`.
- Dispatcher created isolated worktrees for five tasks. DR freshness diagnostics and cluster-up recurrence triage exited successfully; independent review/landing remains pending. The recurrence report found no task-local metadata. Hub-data, Slack multi-job and ACG read-only network workers report unexpected termination with unlanded isolated changes. Hostinger triage was rejected because the network lock still considers ACG active. Nothing is landed. See `docs/issues/2026-10-21-p2-bug-dispatch-worker-exits.md`; resolve worker recovery and network lock state before retrying.
- Landed DR freshness fix `c20d90cd` after independent focused BATS 7/7, ShellCheck, Bash syntax, diff check, doc links, and `_agent_audit`; marked VERIFIED offline. Installed data-repo copy/workflow remains unchanged pending operator-approved live verification. Landed cluster-up triage report `8b70f1a4`; safe host metadata supports a routing/context defect, but the underlying bug remains OPEN because the records do not identify the specific failure-analysis notification or establish Slack-rendered placement. Evidence remains in `docs/issues/2026-10-21-two-dispatch-task-verification.md`.
