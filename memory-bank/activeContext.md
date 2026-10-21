# Active context — k3d-manager-v1.43.5

This file was compressed on 2026-10-19 because the active memory-bank exceeded 700 KB and was approaching the repository's 200K-token context-compaction boundary. Older detail is summarized in `memory-bank/archive/2026-10-07-to-2026-10-16-compressed.md`; the pre-compression files remain recoverable from git history.

## Current branch and operating rules

- Branch: `k3d-manager-v1.43.5`, tracking `origin/k3d-manager-v1.43.5`.
- Latest relevant release commits: `63d604dd` (dispatch missing-telemetry exporter), `611bc1f8` (Slack smoke target selector), and `4a8aeaae` (dispatch telemetry LIVE-VERIFIED evidence). Both dispatch bugs are LIVE-VERIFIED from operator screenshots/jobs on 2026-10-20; Slack selector job `c4a9465f` passed 2/2 with `ARGOCD_APP_PREFIX=ubuntu-hostinger-`. Replay fix live-verified from job `3198fa72`.
- Do not create PRs; finish scoped work at commit + push + memory-bank update.
- Live verification is operator/Claude-owned; Codex may perform read-only diagnostics when explicitly requested.
- Release plan cap: v1.43.5 has five plan slots; do not add another plan without splitting/releasing.
- Required completion evidence: remote commit SHA, relevant BATS output, shellcheck, and `_agent_audit`.

## Latest live investigations and records

- Slack job `8417cf04`, E2E run `1792410757-29778`: preflight passed, but the 420-second hub-app gate failed with frontend `Synced/Degraded` and product-catalog `OutOfSync/Healthy`. Read-only diagnosis found frontend Nginx exiting because `product-catalog.shopping-cart-apps.svc.cluster.local` did not exist when frontend started. Product-catalog later became healthy, but frontend remained `CrashLoopBackOff`. Detailed evidence: `docs/issues/2026-10-19-e2e-sandbox-provision-frontend-upstream-race.md`; dashboard-facing bug: `docs/bugs/2026-10-19-e2e-sandbox-provision-frontend-upstream-race.md` (P2 OPEN).
- PR Checks dashboard: panel 5/6 populated-table transformation issue is `LIVE-VERIFIED` after the operator's Safari-private and Chrome screenshots confirmed the fix at deployed revision `f2063dba`.
- PR Checks dashboard: panel 8 Check duration legend layout fix is landed as `a5edc7ac`, offline-verified (focused BATS 5/5), and operator-confirmed LIVE-VERIFIED in Grafana after sync at revision `6385c3c6`.
- Documentation review commit `ef058487` converted current non-archive flow/architecture diagrams to Mermaid, corrected Cloudflare relay drift, and labeled the legacy ingress path. Review record: `docs/issues/2026-10-19-docs-architecture-diagram-review.md`.
- README Hermes documentation commit `bb4a2f64` adds the guide, Phase 1/2 scope links, and a focused Mermaid lifecycle diagram.
- README architecture-index follow-up `e9d1fddb` adds Hermes to the visible Architecture list shown with the other architecture documents.
- Dispatched P3 dashboard bug `bug-dashboard-verification-tile-labels-clipped`; implementation landed via dispatcher as `5819e236`, with 22/22 dashboard BATS and link checks passing. Operator live-verified the full `Verified` and `Live-verified` labels on the hub `k3dm-bugs` dashboard on 2026-10-19.
- Dispatched P2 e2e sandbox frontend upstream race; implementation landed via dispatcher as `4ebaaec5`. It performs one bounded frontend rollout restart after product-catalog is `Synced/Healthy` while frontend remains `Synced/Degraded`. Offline verification passed: focused BATS 35/35, shellcheck, and `_agent_audit`. Operator-confirmed Slack job `f8ea6d69` completed E2E run `1792450928-16408` with 4/4 passed and exit code 0; bug is now `LIVE-VERIFIED`.
- Dispatched Slack Make-log lookup fix from the canonical empty-output bug; implementation `d5e7b7f5` writes the Make target marker for thread-created jobs so shared retrieval selects `make.log`. Relevant BATS passed 14/14, focused Python tests 17/17, compile and `_agent_audit` passed. Bug is `VERIFIED`; operator Slack live verification remains pending.
- Dispatched explicit Slack `logs <job-id>` lookup fix `177ba541`; it honors the requested authorized child ID, rejects cross-thread IDs, and makes bare `logs` prefer the newest non-anchor job. Focused Python tests passed 25/25, relevant BATS 14/14, syntax validation and `_agent_audit` passed. Operator live-verified the Slack-originated child job `26f2035e`; E2E run `1792455493-30189` passed with exit code 0. Bug is now `LIVE-VERIFIED`.
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

- Dispatch queue (2026-10-20): `2026-10-19-grafana-bug-dashboard-links-empty-branch-and-stem` exited successfully in its isolated worktree; focused BATS passed 21 tests with one release-branch skip, dashboard JSON validation and `git diff --check` passed. Changes remain unlanded; live link clicks remain pending. The Slack `k3dm help` bug now has an explicit `## Files` allowlist, pending commit/push before dispatch. Hostinger outage remains a read-only evidence review; no live host/provider action is authorized by this queue.

- E2E frontend/product-catalog bootstrap-order fix `4ebaaec5`: bug is `LIVE-VERIFIED` from Slack job `f8ea6d69`, E2E run `1792450928-16408`, with 4/4 tests passed.
- Slack Make-log lookup fix `d5e7b7f5`: bug is `VERIFIED`; operator must run a live Slack Make command and then `logs <job-id>` to confirm the transcript is returned.
- Slack explicit job-ID lookup fix `177ba541`: bug is `LIVE-VERIFIED` from operator Slack job `26f2035e` and E2E run `1792455493-30189` (exit code 0 / result pass).
- PR Checks table fix `1a1c33d8` had a remaining panel 6 unit-formatting defect: the panel-wide seconds unit rendered PR numbers as durations. Dispatched fix `9787ce98` scopes seconds formatting to the `Duration` field; independent focused BATS passed 4/4, ShellCheck clean, and dispatcher landing gate passed. Operator screenshots in Safari private browsing and Chrome confirmed populated rows now show numeric PR identifiers and durations in their proper columns; canonical bug is `LIVE-VERIFIED` at deployed revision `f2063dba`.
- Dispatch task `pr-checks-table-unit-fix` completed in scope and was landed/pushed to `origin/k3d-manager-v1.43.5` as `9787ce98`.
- Dispatched P3 PR Checks table misalignment as `pr-checks-table-misalignment`; isolated worktree `/Users/cliang/.local/share/k3d-manager/worktrees/v1.43.5/pr-checks-table-misalignment` is created and implementation is pending.
- PR Checks panel 8 legend clipping bug: dispatcher task `pr-checks-legend-clipped` landed as `a5edc7ac`; focused BATS 5/5 and ShellCheck passed. Operator screenshot confirms the side legend is readable after sync; bug is LIVE-VERIFIED.
- Frontend Cloudflare cache TTL: origin is 5m but Cloudflare browser TTL was 14400; operator must set “Respect Existing Headers” and recheck.
- P1 register-app-cluster role-lookup fix `a70e52a4`: LIVE-VERIFIED 2026-10-20 from Slack job `05f2be6c`, E2E run `1792538358-29202` (4/4, exit 0); log confirms cluster Secret applied and read-only hub check confirms fresh creation timestamp plus `app-cluster` role. Offline BATS 41/41 and ShellCheck clean.
- P2 Slack Make job-ID notice bug: fix landed at `abb0a526` with progress/failure regression follow-up `cb7f37dc`; pytest 26/26, BATS 10/10, Python syntax, `_agent_audit`, and diff checks pass. Operator live-verified job `c30366d6`: queued, started, progress, and terminal-failure notices showed the same ID, and screenshot confirms `logs c30366d6` returned matching output. Bug is LIVE-VERIFIED. The `make test-all` run separately ended rc 2 (1,747 cases, 56 failed); the known macOS `sha256sum` fixture failure recurred and 55 other failures were not triaged. Evidence: `docs/issues/2026-10-20-slack-make-job-id-live-verification-still-omits-ids.md`.
- Existing OPEN P2 `docs/bugs/2026-10-19-hub-data-bats-fixture-sha256sum-missing-on-macos.md` reproduced in `c30366d6`; affected hub-data tests fail at fixture setup because stock macOS lacks `sha256sum`. The 55 other test-all failures span separate areas and remain untriaged; do not track them as one assumed root cause.
- Slack smoke diagnostics follow-up `slack-smoke-target-diagnostics` landed as `36dfb1e2`; it surfaces bounded `[TARGET]` diagnostics and candidate context. Independent BATS passed 11/11, ShellCheck clean, `_agent_audit` passed. Operator live-verified the reporting fix with Slack job `a3d1097b`; the smoke command correctly refused to guess between Hostinger and k3s targets. Explicit Slack selector support landed as `611bc1f8`; unittest passed 39/39 and cloud-bridge pytest passed 83/83, including the dispatcher landing gate. Operator live-verified `/k3dm smoke ARGOCD_APP_PREFIX=ubuntu-hostinger-` with Slack job `c4a9465f` (2 passed, 0 failed); bug is LIVE-VERIFIED. Replay acknowledgment landed as `fd1b40b0` (pytest 34/34, webhook BATS 68/68); operator verified exact thread command `k3dm e2e-replay RUNNER=m2`: queued, started, and succeeded notices all used job `3198fa72`, ending `published=0 still_pending=0`. Replay bug is LIVE-VERIFIED. Evidence: `docs/issues/2026-10-21-slack-live-verification-results.md`.
- Dispatch dashboard rows for `slack-explicit-job-logs` and `slack-make-log-selection` show valid elapsed time but missing Codex tokens/exit metrics: their ledger has only `start` and `land`, no `codex_exit`. These are pre-`2de716d8` historical records; displayed zero runs/time means missing telemetry, not no work. Evidence: `docs/issues/2026-10-21-dispatch-dashboard-legacy-task-metrics-missing.md`.
- Filed P3 `docs/bugs/2026-10-21-dispatch-dashboard-missing-codex-telemetry-renders-zero.md` to stop treating missing Codex exits as zero usage; landed as `63d604dd`. Focused pytest 12/12 and dashboard BATS 7/7 passed, including the dispatcher landing gate. Operator screenshot on 2026-10-20 confirms elapsed times 1.60/4.98 minutes and blank tokens/time/runs; bug is LIVE-VERIFIED.
- Hostinger Vault watchdog and several teardown/dashboard items have their live follow-ups recorded in the bug docs and recent progress below.

## Verification from latest work

- Added and pushed v1.43.7 plan `docs/plans/v1.43.7-dispatch-vendor-coordinator-model-telemetry.md` (plan 2/5) in `da4761b3`: vendor/model provenance per worker attempt plus separate primary coordinator identity; attribution only, no model-routing changes. `make check-doc-links` and focused documentation tests passed.

- `bats scripts/tests/plugins/e2e_sandbox_preflight.bats`: 34/34 passed.
- `shellcheck scripts/plugins/e2e.sh`: clean.
- `_agent_audit`: passed.
- PR Checks/bug dashboard tests: 66 passed.
- Documentation checks: `make check-doc-links` passed (`2218 file(s) OK`); targeted `bats scripts/tests/lib/bats_negation_lint.bats` failed on its existing assertion at line 6; no shell files were changed.

Use the bug docs for acceptance criteria and the archive for historical context; do not re-derive old decisions silently.

## Dispatcher P1 investigation (2026-10-20)

- Root cause of dead dispatch workers confirmed: `_dispatch_start`/`_dispatch_resume` background the worker in the launcher's process group/session; the agent harness's cleanup kills it (SIGHUP observed; `nohup`/`trap '' HUP` do not survive a group SIGKILL; a new session or double-fork does). Full evidence is in `docs/bugs/2026-10-20-codex-dispatch-background-process-lost-no-terminal-status.md` (section "Investigation findings — 2026-10-20").
- Operator approved implementing the fix via Codex dispatch (flat-rate, no API token calls). PR Checks Grafana fix is deferred until the dispatcher is fixed. Verified-but-unlanded Grafana candidate: `r4` tree `5e1f59ce05f71d5d8ed78429f12796dcfe059fc4` plus `max by (__join[, state])` wrapping the second query of panels 5 and 6 (simulation scripts in the Antigravity scratch dir `gfsim`).

## Dispatcher P1 fix landed and live-verified (2026-10-20)

- `2de716d8` detaches Codex dispatch workers (perl double-fork + setsid), writes `start`/`exit` markers before bookkeeping, adds `supervisor.log` and `terminated unexpectedly` status. 42/42 BATS (`env -i`), shellcheck clean, `_agent_audit` rc=0. Review fixed a ledger `return 1` regression and added the missing SIGHUP/group-SIGKILL survival tests.
- Live E2: a real Codex CLI session ran `start` and ended; worker stayed `running` (PPID 1, own PGID), then `exited successfully`, exit 0 (smoke task `live-smoke-codex-cli`, abandoned; run dir kept). Bug doc `docs/bugs/2026-10-20-codex-dispatch-background-process-lost-no-terminal-status.md` is now `LIVE-VERIFIED` with run evidence recorded.
- Next: operator dispatches the PR Checks Grafana fix from Codex CLI using the fixed dispatcher. Candidate fix = `r4` tree `5e1f59ce05f71d5d8ed78429f12796dcfe059fc4` plus `max by (__join[, state])` around the second query of panels 5 and 6; `r5`/`r6`/`e2e-sandbox-live-verify` run dirs kept as evidence.

## Hostinger multi-service P1 read-only investigation (2026-10-20)

- Incident-time M4 frontend and Pushgateway port-forward logs show repeated TCP/6443 timeouts; frontend forwarding resumed around 21:26 UTC. Evidence favors a transient M4-to-Hostinger API path interruption, but does not identify the failing network segment.
- Hostinger remained up since 2026-10-17, k3s was active, and no incident-window OOM/link/disk journal matches were found. Current read-only checks showed API `/readyz=ok`, node/app/data workloads ready, Vault and `vault-backend` Ready, and public frontend/products HTTP 200.
- Fresh Hostinger status job `dc9e4089` had 20 OK / 1 fail: only ArgoCD direct password login unavailable; ArgoCD SSO succeeded. Operator `make status` screenshot reported HEALTHY; its hub snapshot was stale, not a live-service failure.
- Canonical Hostinger incident record is OPEN at P2 (downgraded from P1 after recovery); root cause remains unconfirmed and ArgoCD direct-login has an SSO workaround. No runtime changes performed. See `docs/bugs/2026-10-20-hostinger-multi-service-502-kubernetes-api-timeouts.md`.
