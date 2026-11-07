# Progress — compressed operational log

- 2026-11-07: verified disk-metrics-scutil (pass). Grafana error-page stack: no supported setting in 11.4 (findings 0afa2504, pending land, operator decision). CVE empty-tables spec cited (5d8f4d8e), redispatched v2.
- 2026-11-07: disk fix landed d70047d5; filed cve-autopatch-empty-tables and grafana-error-page-stack-trace (P3); tier spec corrected; 4 dispatches.
- 2026-11-07: matcher fix landed 73120c90; filed disk-metrics-scutil, hermes-e2e-null-counts, e2e-results-never-reach-m5-hub, security-findings-tier-column; watchdog Job deleted.
- 2026-11-07: operator `make hub-sync` on M5: 3 docs-only commits pulled (8bab7807..8e483765), restarts and platform-ops correctly skipped, appsets-check ran (8 sets on v1.43.14). Hub catch-up E4 docs-only path PASS; code-commit path still waits for a code commit. `make restart-webhook` reloaded 03:55:52 PST; fan-out cap E2 waits for a multi-alert group. Hermes is a 300s StartInterval job, last exit 0.
- 2026-11-07: operator gave the dispatch go for the Bugs dashboard matcher P1; dispatched to Luna as `bugs-dashboard-matcher`.
- 2026-11-07: live check of `dc5f6bb0` found the Bugs dashboard crashing: tile 19 override uses frame matcher `byRefId`, field override needs `byFrameRefID` (Grafana 11.4.0 `ids.ts`). Filed P1 `docs/bugs/2026-11-07-hub-code-behind-tile-unknown-matcher-crashes-bugs-dashboard.md`, waiting on dispatch go. Hub catch-up E3 tile half fails until fixed.
- 2026-11-07: M5 pulled to `8bab7807` (operator ran `git pull`, so no code left behind). Hermes restarted 03:50 PST; `k3dm_hub_checkout_code_commits_behind` = 0 matches M5 rev-list 0, on_newest_release = 1. Hub catch-up E3 zero case passed; nonzero case and E4 wait for the next code commit. Payment pinned by promoter `8bab7807`, app Synced/Healthy.
- 2026-11-06: `s1-version-resolve` landed `7d7cd7bd`, verify PASS (37 tests, 5 mutants). `p0-s1-dispatcher` verify PASS recorded. Live checks and S1 E8 open.
- 2026-11-06: hub catch-up landed `dc5f6bb0`, verify PASS; live E3/E4 open. Verify PASS recorded for Run sort, Status guard, CVE timeout and S1 metrics. S1 dispatcher held on `s1-version-resolve`, filed and dispatched to Luna. Status convention added to `CLAUDE.md`.
- 2026-11-06: all three workers exited 0 (S1 dispatcher, S1 metrics, Run sort); not yet reviewed or landed. Operator agreed landed bugs read Fixed: four Status lines corrected (dashboard open counts and D3 Part B to VERIFIED; EC2 key and acg_extend to LANDED); sudoers P1 stays open, stale text fixed. Filed P2 `2026-11-06-app-cve-scan-trivy-timeout-reported-as-execution` (operator go; payment candidate rescanned clean), P3 `2026-11-06-bug-status-first-word-not-enforced` (operator go) and P2 `2026-11-06-hub-code-lag-invisible-and-no-catch-up-step` (operator go; dispatch after S1 lands, shares the Makefile). Corrected finding: Hermes reads doc text from fetched origin in about 5 minutes; only code and dashboards wait on the M5, 58 commits behind.
- 2026-11-06: Hermes Slack post seen by the operator (`k3dm-notices`, 07:26 PST) after the Keychain copy. Handoff written; M4 reboot next for tunnel E4.
- 2026-11-06: Hermes Slack item confirmed revoked (404 no_service); analyzer posts traced to the M5 plist having no status channel and no URL. New bug filed, recurrence added to the webhook migration bug; hand fixes with the operator.
- 2026-11-06: `make argocd-hermes-token` got 401 on the M5; second defect added to the token bug (target ignores Vault `secret/argocd/admin`, rotated 2026-11-01).
- 2026-11-06: hub-cutover P3 landed `c151bcb1`, verification recorded (independent 12/12; 6 red pre-fix `2394272d`; 5 mutants killed); live E2 open. P2 live E2 passed on the M5. Tunnel fix live E3 passed from the M4; E4 needs an M4 reboot.
- 2026-11-06: filed six post-cutover bugs and four notes on existing docs from read-only M5 evidence (`1ed620c7`); none dispatched. Slack test post and ArgoCD token re-mint are with the operator.
- 2026-11-06: P2 hub-cutover stopped-cluster fix landed `03f40c0a`, verification recorded (independent 20/20; 7 red pre-fix; 7/7 mutants). Live E2 open. Luna's other reds: webhook suite passes outside her sandbox; ESO wiring smoke fails on the base tree too (looks like `docs/bugs/2026-10-15-webhook-bats-load-module-removed-in-python-3-15.md`, unconfirmed); 4 pytest reds not rerun. `k3dm-hermes status` on the M5 exits 0 but reports `unknown` (cluster status source unavailable), not investigated.
- 2026-11-06: lib-foundation PR #76 merged `b5e40f7` (operator), subtree synced `a4c44e62` (tree equals lib main). v0.5.5 not tagged. Operator approved the four dirused tab choices.
- 2026-11-06: operator renamed diruse to dirused and required one GUI tab per UNC path; plan is now `docs/plans/dirused-windows-disk-usage-tool.md`. Operator gave the dispatch go for the P2 and P3 hub-cutover bugs and the lib-foundation v0.5.5 PR.
- 2026-11-06: tunnel rollout blocked on the M5. Filed P2 `docs/bugs/2026-11-06-hub-cutover-verify-fails-forever-after-old-cluster-is-stopped.md` and P3 `docs/bugs/2026-11-06-hub-cutover-verify-ignores-old-host-in-report.md`; dispatch pending. Operator ran ssh-copy-id: the M5's `id_ed25519` (created 2026-10-31 12:05:52) was not trusted by the M4; cause of the key change unknown; old `xaXR…` entry still on the M4.
- 2026-11-06: VM installers LANDED on lib-foundation `feat/install-vagrant-virtualbox` `fc3bda0`, verify PASS (independent suite 22/22, 15 red on pre-fix, 10 of 11 mutants red, the survivor loses only a warning); live E2 passed on the M4. Lib PR needs the operator's go, then subtree pull.
- 2026-11-06: P1 browser log fix LANDED `9ae2698c`, verify PASS (independent suite 19/19, 14 red on pre-fix, 14 of 16 mutants red, 2 equivalent for M3). Live E2 open until a root-owned log appears or the next hub rebuild. The verifier wrote its suite to the repo root after a failed cd; moved out before any commit.
- 2026-11-06: tunnel fix LANDED `8e5f8831`, verify PASS (independent suite 25/25, 20 red on pre-fix, 13 mutants red; N4c strict excluded as beyond the spec). Live E3, E4 open.
- 2026-11-06: M5 frontend back: log owner `cliang`, agent running, listener on 127.0.0.2:18082, public URL 200. P1 log bug dispatched; correction 1 sent (GNU stat abort, double glob, unreachable message, false capture comment, missing tests).
- 2026-11-06: correction: commit `b30226b3` and these notes claimed the installers were specced here and dispatched; the copy had failed and the dispatch was refused. Spec copied here now (`docs/plans/lib-foundation-v0.5.5-install-vagrant-virtualbox.md`) and dispatched on lib-foundation `feat/install-vagrant-virtualbox`.
- 2026-11-06: P1 log fix correction 1 back from Luna: focused bats 10/10 and shellcheck rerun by Claude outside her sandbox; independent verifier next.
- 2026-11-06: diruse renamed `docs/plans/diruse-windows-disk-usage-tool.md`: own repo, M1 in a gap, main work after v1.46.1, VM on the M4; operator holds a Windows 11 Pro licence.
- 2026-11-06: diruse scoped (`docs/plans/diruse-windows-disk-usage-tool.md`, roadmap candidate; not scheduled).
- 2026-11-06: filed P1 `docs/bugs/2026-11-06-browser-agent-exits-78-on-root-owned-log-after-relay-install.md`; M5 frontend 502 until the operator runs chown + kickstart. Tunnel fix: Luna exited, Correction 1 sent after review.
- 2026-11-06: tunnel fix dispatched to Luna (forward-only key). Operator reports the M5 commands ran; live checks next.
- 2026-11-06: P1 hub-cutover LANDED 76f34498, verify PASS (13 tests from Acceptance; 11 red pre-fix; 6 mutants red). Live E3 open. Tunnel fix (P2) now unblocked.
- 2026-11-06: P1 hub-cutover first attempt reviewed; Correction 1 (re-run records, disabled+loaded, rollback on new hub, plan text) and M6-M10 added; resumed Luna.
- 2026-11-06: filed P3 undeclared overlaps tile out of sight (not dispatched; operator picks the time). Empty 30-day panel not filed: waits on platform-ops, live E4 of bug-open-history.
- 2026-11-06: chrome-cdp removed from the M4 (operator go). Tunnel fix option 1 chosen. P1 hub-cutover spec extended and dispatched to Luna.
- 2026-11-06: Part B gap landed 632ac235; independent verify PASS recorded. Live E4 on the M5 open.
- 2026-11-06: Part B gap attempt 2 passed the independent verifier (29/29); commit refused by _agent_audit (16 if lines, limit 8). Correction 2 sent to Luna: two helpers, no allowlist entry.
- 2026-11-06: P0 S1 spec written in the P0 plan (Slice S1, Files, Acceptance) with fixtures in scripts/tests/fixtures/dispatch-gates; not dispatched. Part B gap attempt 2 under independent verification and full gates.
- 2026-11-06: Part B gap dispatched to Luna (first attempt refused: no Files section). Review of attempt 1: _err exit aborts refresh before cloudflared; issuance uses current context. Correction 1 added, Luna resumed.
- 2026-11-06: M4 `hub-vault-profile` reset to `laptop` (operator). Keychain worktree confirmed abandoned and archived; remote branch kept.
- 2026-11-06: payment E1 PASS, independent verify recorded (fix 0 CRITICAL, pre-fix control red with 3 new). Bug marked FIXED; `make platform-ops` pending.
- 2026-11-06: filed Part B gap spec (P1, dispatch go given) and hub tunnel auth P2: launchd's SSH agent is empty after a reboot, so M4 metrics and logs stop reaching the M5.

- 2026-11-06: 12 more M4 agents disabled and stopped with the operator's go, each confirmed; one connector, routes answer. Kept: `chrome-cdp`, the Pushgateway and Loki forwards (two exit 255, cause unchecked). M4 profile not reset.

- 2026-11-06: 14 remaining hub singletons disabled and stopped on the M4 with the operator's go (15 with the tunnel), each confirmed; routes unaffected. M4 `hub-vault-profile` not reset. P1 fix approved to start after `/clear`. M5 reboot on hold until Claude says go (not rebooted; has not pulled Part B). Part B gap found by reading the code: the Hostinger path does not write the ArgoCD and Keycloak browser agents (Correction 4, not fixed).

- 2026-11-06: M4 reboot for Part B E5 restarted old hub agents. Second tunnel connector caused public 502s (frontend, Keycloak, Grafana, ArgoCD); operator booted out and disabled the M4 agent, routes back. M4 `vault-failover` flipped its local profile to `hostinger` at 03:56:01Z; seed aborted before any write, store not repointed, Hostinger Vault unsealed, 20/20 ExternalSecrets Ready. P1 filed: `docs/bugs/2026-11-06-hub-cutover-old-hub-agents-return-on-reboot.md`; not dispatched. Part B E5 PARTIAL on the M4. Payment main CI run 42157751676 success; E1 pending.

- 2026-11-03: CA trust Phase B offline containment suite independently passed 89/89, including the actual caller warning and continuation after a controlled hung process held stdout/stderr. Phase B test committed to task branch `f08a3775`; see `docs/issues/2026-11-03-ca-trust-phase-b-containment.md`. Await operator review before Phase C; no live verification or landing.

- 2026-11-03: CA trust Phase A completed with inconclusive live root cause. Fake sudo/security and inherited-pipe fixtures produced the expected distinct process states; the current webhook writes output to a file rather than capturing a pipe. Full output and live-capture guidance: `docs/issues/2026-11-03-ca-trust-phase-a-diagnosis.md`. Await operator review before Phase B.

- 2026-11-02: Expanded CA trust hardening remains in progress. Luna hit a usage limit; partial draft preserved in task worktree. Independently ran supervisor BATS 5/5 and ShellCheck/diff check clean, but old timeout and arbitrary root LaunchDaemon authorization remain unresolved; no verified fix or landing. See latest activeContext handoff and docs/issues/2026-11-02-find-similar-docs-prior-art.md.

- 2026-11-02: Operator approved expanding CA trust fix scope to harden pre-existing sudoers rules and dependent listener flows. Proceed to implement and verify offline; live verification deferred.

- 2026-11-02: CA trust supervisor review found existing policy routes that defeat a protected helper (sudoers self-update, install traversal, user-controlled system LaunchDaemon). Built-in sudo timeout misses pre-command setup and does not guarantee detached process termination. Focused worker suite 81 passed, 4 failed; asked operator about expanding scope to harden affected policy and listener flows. Fix not landed; live verification deferred.

- 2026-11-02: Operator approved preserving automatic headless trust using a narrowly scoped privileged supervisor and new sudoers permission. Continue until implemented, offline verified and landed; live verification deferred. P2 bug scope updated; no host configuration changes authorized.

- 2026-11-02: Operator requests the CA trust task continue until landed. Luna resumed and confirmed detached-child regression remains failing (75 pass, 1 fail). Asked operator to choose headless skip with warning versus privileged-supervisor investigation; response pending at time of note. No landing. See latest activeContext handoff.

- 2026-11-02: CA-trust Luna dispatch worker exited successfully but reported a blocker: isolated detached-child regression left a delayed scratch side effect after timeout (focused BATS 75 pass, 1 fail); privileged descendant termination also unproven. Unstaged patch is not verified or landed. Latest handoff in activeContext; details in docs/issues/2026-11-02-find-similar-docs-prior-art.md.

- 2026-11-02: Operator requests a handoff in `activeContext.md` after each completed, verified task before they `/clear`. CA-trust Luna continuation reported 75 focused tests passed; staged audit and independent verification remain pending. Review identified that same-user process tests do not prove a sudo-owned descendant can be stopped; Luna resumed again (resume 3). No landing or live cluster-up.

- 2026-11-02: CA-trust Luna first run focused BATS 73 passed; broad suites reported tripwire-related failures. Review found missing explicit interactive/non-Darwin and elapsed timeout tests; Luna resumed (resume 2). Not landed or verified. See docs/issues/2026-11-02-find-similar-docs-prior-art.md.

- 2026-11-02: P2 headless CA trust stall DISPATCHED to gpt-6-luna (slug `2026-11-02-acg-up-stalls-at-system-keychain-trust`, spec commit `204d8e81`); running when checked outside sandbox. M5 vector search found relevant trust and cleanup prior art; M4 retrieval unavailable. No live retry. See docs/issues/2026-11-02-find-similar-docs-prior-art.md.

- 2026-11-02: M5 Slack /cluster-up job c38c3855 failed after 3300s, last output System Keychain CA trust; CloudFormation had succeeded, cleanup removed connections only. Operator clarified run was before today's pull. M5 now at remote release head 8d9f5f0f, default hub-role file absent; sudoers existed before the job and current noninteractive CA-trust policy check succeeded, CA verify fails, exact blocking process unknown (unified log shows three sudo true password-required checks, no add-trusted-cert entry). AWS DescribeStacks returned InvalidClientTokenId, so current stack status unknown. Filed docs/bugs/2026-11-02-acg-up-stalls-at-system-keychain-trust.md and docs/issues/2026-11-02-acg-up-job-c38c3855.md. No retry or live mutation.

- 2026-11-01: lib-foundation PR #74 merged `339a713`; local upstream main fast-forwarded and k3d-manager subtree synced to that exact tree in `c22646e1` (173 staged files matched upstream). BATS 178 passed / 1 skipped (179 cases), ACG Jest 53/53, ShellCheck and staged audit passed; no live sandbox used. Main is not tagged v0.5.5 and excludes the pushed duplicate-key fingerprint follow-up and planned brace-expansion bump. Operator notes prior M5 /cluster-up succeeded; recorded success `cdff3cea` preceded the merged duplicate-key fix, and live duplicate-path proof is pending the next normal sandbox session. See docs/issues/2026-11-01-foundation-subtree-sync-339a713.md.

- 2026-11-01: lib-foundation PR #73 merged `bb7f1f28`. Copilot fingerprint finding reproduced: new branch `fix/acg-key-fingerprint` pushed (`bac3238`, `f79f45c`, notes `eb2a136`), clean-env BATS 154/154 then final ACG 37/37, shellcheck and staged audit passed; AWS RSA documentation differs and live proof remains pending. PR #74 changelog conflict resolved by merge `25678b7`, pushed; clean-env BATS 157/157, shellcheck and audit passed, GitHub CI green (shellcheck, bats, acg node) and PR #74 mergeable; previous Copilot review predates the update. Details: docs/issues/2026-11-01-lib-foundation-pr73-fingerprint-followup.md. No new PR created.

- 2026-11-01: agent-instruction-files-refresh LANDED `43c2b364`. Scratch agy probe reported both AGENTS.md and GEMINI.md markers (language server 1.4.12); focused checks 8/8, agent-rigor BATS 11/11, curated BATS 1,979 cases/0 failures/20 skips on Python 3.13.6, non-external pytest 1,764 passed/4 skipped/5 deselected; landing fast gate passed. Python 3.15 BATS failure and promtool-dependent exclusions are recorded in docs/issues/2026-11-01-agent-instruction-refresh-verification.md. Claude review and next-dispatch E3 pending; no verification pass claimed.

- 2026-11-01: resume-reason task LANDED `2c7fc95c` and fixture isolation `22110d0c`, operator approved scope. Focused dispatcher BATS 94/94, metrics 169 passed, dashboard BATS 38/38, landing fast gate passed (promtool query tests skipped: unavailable). Pre-fix metrics classification 4 failed/2 passed against old exporter; complete verifier evidence and live check pending. Agent instruction refresh remains unlanded. Local backlog review: 23 candidate open bugs without matched dispatch starts (7 P2, 16 P3), including items needing triage or later releases; not a dispatch-ready count. See docs/issues/2026-11-01-dispatch-review-pending-verification.md.

- 2026-11-01 Codex dispatch review PARTIAL: role guard landed/pushed `bd3002db`, focused BATS 157/157 and landing/pre-push fast gates passed; pre-fix and live checks pending. Resume task focused BATS 94/94, metrics pytest 169 and dashboard BATS 38/38 passed, but fast gate exposed a hub-data shared TMPDIR collision; isolated fix `8614ebb4` remains on task branch pending scope approval. Agent instruction refresh remains unlanded: broad tests and agy loading unverified. See docs/issues/2026-11-01-dispatch-review-pending-verification.md.

## 2026-11-06 evening landings

- [x] Landed: S1 dispatcher `58a15947`, S1 metrics `04a6e7d2`, Run sort `49765821`, Status guard `f832a140`, CVE timeout `6da25436`.
- [x] S1 E6 and E7 pass.
- [ ] Independent verifiers (S1, Run sort, Status guard, CVE timeout) running.
- [ ] Hub catch-up with Luna.
- [ ] Live checks after all fixes, one at a time.

## 2026-11-06 late verification and S1 revision

- [x] `bug-open-history-from-git` LIVE-VERIFIED: E4 30/30 dates.
- [x] S1 spec revised after the second review; `v1.43.16-prompts-by-model` filed.
- [x] Waiting-on spec revised: `Open P*` tile descriptions dropped, `Waiting since` not shown.
- [x] S1 third check landed; three gaps fixed by Claude.
- [x] Waiting-on independent verify PASS; lines on 26 open docs; convention in `CLAUDE.md`. Live E5/E6 open.
- [ ] S1 dispatcher (Luna) and metrics (Flash 3.8) running.
- [ ] P3 Run column sort: Flash 3.8 running.
- [x] Waiting-on corrected and landed `6d42c201`.
- [ ] Waiting-on independent verify, plan-metrics part of E4, doc lines, `CLAUDE.md` convention.
- [x] `agent-instruction-files-refresh` LIVE-VERIFIED.

## 2026-11-05 security + telemetry filings

- [x] P1 sudoers passwordless root escalation: CLOSED 2026-11-05 (reinstalled on all 3 Macs). LANDED `4c4f7dd1`. Independent verify PASS (recorded). install-sudoers: M4 and M5 OK; M2 blocked by bash 3.2 (P2 filed). E4 PASS live on the M4; the M2 is pending (Homebrew bash workaround or the P2 fix).
- [ ] P1 sudoers LaunchDaemon/exec wildcards: design pending.
- [ ] P2 dispatch resume ignores task model: Acceptance pending.
- [ ] P2 agy no-data: root cause recorded; Fix direction is to read agy transcripts.
- [ ] Plan v1.43.16 lead-model-activity-dashboard: PROPOSED.

## 2026-11-01 v1.43.13 release prep

- Landed: pushgateway, vault list-kubeconfig, billable warning, run-outcome labels, cleanup env pin, webhook bot thread, machine-setup EC2 key, fast-gate skip `ce0f3f25`.
- Docs audit applied `dbf62261`; deferrals recorded in `docs/roadmap.md`.
- M5 appsets reapply/check + platform-ops done; PR #155 CI green at 63ba9b22, Copilot resolved.
- [x] PRs merged: #155 `abcde772`; tag + GitHub release `v1.43.13`; enforce_admins restored. Dependabot #154 closed (subtree lockfile; bump goes upstream first).
- [ ] Three fixes have no stored verifier evidence (P1 pre-push gate, P2 hub-migration Slack config, P2 TTY hang); their verify events were withdrawn. Re-verify with evidence in v1.43.14.

## 2026-11-01 v1.43.14 opened

- [ ] P1 verify-evidence DISPATCHED to Luna (spec corrected 90380e17). Then verify with an evidence-backed independent verifier and land.
- [ ] Fleet-host plan: temperature added (pmset alert + macmon °C). macmon via lib-foundation `_install_macmon` (v0.5.5 spec 9758f5f). Before dispatch: v0.5.5 subtree pull, then a real macmon capture.
- [x] P1 verify-evidence LANDED `6fe94bda`, VERIFIED offline with ledger evidence. [ ] E3 live after M5 `make platform-ops`.
- [ ] lib-foundation `_install_macmon` DISPATCHED to Luna (slug lib-foundation-v0.5.5-install-macmon). LANDED lib `db56238` (pushed), VERIFIED offline with ledger evidence. lib PR #74 open (operator merges when green). CI flake (vcluster test) rerun; P3 race bug filed.
- [ ] DISPATCHED: plan agent-instruction-files-refresh; P2 dev-node role gate; P2 resume-reason. Then next wave: bug-open-history-from-git, claude-context-cost-per-turn, control-node-role. [ ] v0.5.5 tag + subtree pull, then E2 live on M4. Then verify, land on feat/install-macmon, open a lib PR, and include it in v0.5.5.
- [x] Dev-node P2 scope widened to hub release targets (operator approval recorded 90380e17).

- Cut from `abcde772`. Carried: P1 verify-evidence bug, four open P2 docs retargeted (resume reason, extend guard, hub EC2 key, dev-node acg-up), lib-foundation #73 → v0.5.5 + brace-expansion bump + subtree pull.
- [x] M5 appsets-reapply (hub 5/5, app-cluster 8/8) + appsets-check PASS on v1.43.14, from the operator's pasted output (2026-11-01). The first rerun went to the M4/retired hub by mistake (no change).
- [x] `make platform-ops` on the M5 for v1.43.14 (operator paste 2026-11-01). The Keychain was locked, so the 4 DR secret syncs were skipped; the existing Secrets are intact. Rerun it before the PR if v1.43.14 changes platform-ops.


Compressed 2026-11-07. Entries before 2026-11-01 (v1.43.14 open) are in `memory-bank/archive/progress-2026-11-07.md`.
