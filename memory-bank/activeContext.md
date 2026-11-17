## Session 2026-11-17 (after handoff) — v1.44.2 opened

- 2026-11-17 ~18:40Z: dirused#14 CI on 90ce085: portable green, windows 54/55 — all 8 new tests pass; SummaryTests E2 Assert.Single broke on the footer (missed by run 1). Claude fixed the assertion (6f09162: 2 lines + footer prefix, not exact counts, since the runner volume is 79.9%). CI re-running; Argon review still on 90ce085 (delta is test-only).
- 2026-11-17 ~18:25Z: blind Argon review of dirused#14 dispatched (docs/plans/dirused-m2a-review.md, slug dirused-m2a-review, linked --role review to dirused-m2a-fullness-levels; not counted in WIP).
- 2026-11-17 ~18:20Z: dirused M2a LANDED as 90ce085 on m2a-fullness-levels (land --allow-out-of-scope: 3 Portable test files added to spec Files after runs 1-2, tools/PACKAGE-README.txt per Contract readers). Portable 37/37; mutation GetType gate → test 9 red (verified by Claude). PR wilddog64/dirused#14 (normal). Next: CI (windows job runs tests 1-8), Argon blind review, live E4 by operator at office. dirused checkout now on m2a-fullness-levels. WIP 2/3.
- 2026-11-17 ~18:00Z: dirused M2a run 2: Portable 36/36. Review found colour never shows (GetType()==StreamWriter vs Console.Out = TextWriter+SyncTextWriter, probed SDK 11.0.100). Spec gained test 9 (pure ShouldColor, Console.Out positive control) and recorded the Complete-required deviation; Luna resume 3 (correction).
- 2026-11-17: dirused M2a run 1 exited; production changes OK but tests/Dirused.Tests.Portable (CI's Linux suite) went 36/36 → 31/36 — footer line and JSON level, intended. Spec defect: Files table omitted the Portable project; amended, Luna resumed (resume 2, --reason correction).
- 2026-11-17: idea row added to docs/ideas.md — graph each Claude /clear in Grafana (hook log already exists, no reader). Inbox, grooming 2026-11-22.
- 2026-11-17 ~19:00Z: dirused M2a spec docs/plans/dirused-m2a-fullness-levels.md (/warn 85, /crit 90, [WARN]/[CRIT] tags + ConsoleColor, /summary footer, exit 4 over 3, JSON/CSV level) dispatched to Luna on new dirused branch m2a-fullness-levels (from main 3865f28). Still recorded under v1.44.2 until M1 lands. M2b (top 3 folders for red/yellow in /summary) and /html are next specs. WIP 3/3.
- 2026-11-17 ~18:30Z: operator "you can go ahead to write 2 specs and dispatch to Flash and Luna" (Stage 2 + OOB M1). Stage 2 spec docs/plans/vault-unseal-secret-follows-keychain-restore.md dispatched to Flash (agy gemini-3.8-flash-medium), running. OOB M1 spec docs/plans/v1.45.0-multi-project-m1-registry-dispatch.md (pulled forward to v1.44.2; spec stays in k3d-manager until M4's public-repo scan) dispatched to Luna; run 1 exited with NO changes (cited git pull vs read-only .git and parent plan's missing Acceptance) — resumed with clarification (resume 2), running. Operator can't hub-promote from office (memory). dirused fullness-colour spec next when a slot frees (WIP 2/3).
- 2026-11-17 ~18:45Z: operator "message sent to slack should not expose user info. use ~/ instead": stall-watch notice now prints ~/ (d2a72d35, test S1 red pre-fix, 12/12, bash 3.2+5); bug docs/bugs/2026-11-17-slack-messages-expose-home-directory-path.md (P3, other Slack senders unaudited). Installed watcher picks it up from the repo checkout only after the hub promote.
- **E5 run 2 2026-11-17 15:15Z** (watchdog paused 12 min, operator go; restored 15:27:30Z, safety timer stopped): vault_seal degraded 15:18:33Z; incident 15:25:15Z (eso + vault_seal) led with "Root cause: Vault sealed", approvals [] (no r7). Resolved message waits on 4 ExternalSecrets retrying (SecretSyncedError 15:25Z). E2 unexercised (no ArgoCDAppDegraded). Post-land Fable findings filed: docs/bugs/2026-11-17-vault-sealed-landed-review-findings.md (W1 stderr fail-open P2).
- 2026-11-17 17:15Z: teammate's dirused suggestions (fullness colours: /warn default 85, /crit default 90, both adjustable; top 3 per server; /html self-contained report with SVG charts) were wrongly put in docs/ideas.md; removed (OOB repo: straight to a dirused spec). Operator wants OOB project management settled: v1.45.0 plan 3 multi-project-records (DRAFT, intent approved, Acceptance not written).
- 2026-11-17 16:56Z: dirused PR #13 merged (3865f28, CI 4/4 on 83b9ca0); v0.0.4 tagged, Release run 44130794197 green, pre-release with win-x64 + win-arm64 zips and sha256. Waiting on operator office tests (B2 probe, E4 /timeout stop line, /file servers.list SVI system only).
- 2026-11-17 16:55Z: dirused M1h-b verified on VM (7/7; pre-fix 4 red; dir-row/depth/unextended/any-exception mutants each red; full 45/47 known VM reds; portable 36/36) and landed 83b9ca0 on #13. CSV reflection test kept (no stopped-scan seam via Program.Run). Next: CI green on 83b9ca0 -> merge #13 -> tag v0.0.4 (release.yml on v* tag) -> operator office tests.
- 2026-11-17 16:50Z: Argon delta review of #13 (a242be0..ae4b253): 5 findings, all verified by Claude (SVI 0 B dir row; SVI as target exits 0; \\?\ root mismatch; non-denied-error test gap; CSV test via reflection). Spec dirused-m1h-b-review-fixes dispatched to Luna. CI on ae4b253 green 4/4. v0.0.4 waits on M1h-b.
- 2026-11-17 16:40Z: dirused M1h verified on VM (targeted 4/4; any-depth + no-Win32 mutants red; renderer mutant red locally; .NET UNC parent check confirmed) and landed ae4b253 on m1g branch, pushed to #13. Gap: any-exception mutant survives (no test that a non-denied error on SVI stays INCOMPLETE). Argon delta review (a242be0..ae4b253) dispatched; then merge #13, tag v0.0.4.
- 2026-11-17 16:30Z: dirused A2 verified by Claude on VM (pre-fix red 2, 3 mutants red, targeted 5/5 green; full suite only the 2 known VM-only reds) and landed 7aa3fee on m1g branch, pushed to PR #13. M1h dispatched to Luna (gpt-6-luna confirmed) on m1g branch. Next: verify M1h on VM, land, Argon delta review of A2+M1h, merge #13, tag v0.0.4. Operator saw the 07:25 PST card = E5 test; it shows H5 (names ArgoCD), fixed in ebdd140a, live after promote.
- 2026-11-17 ~17:20Z: operator "go dispatch M1h": spec docs/plans/dirused-m1h-system-folder-not-counted.md (denied System Volume Information at volume root → systemOnly, scan stays complete). Queued behind A2 (both touch Scanner.cs, one dispatch per file); dispatch onto m1g branch when A2 lands, ships in v0.0.4 with #13.
- 2026-11-17 ~17:00Z: vault-sealed review fixes LANDED: webhook W1-W6 59dd12e5, Hermes H1-H3,H5 ebdd140a, guide H4 4ecee69c (Claude: pre-fix red 5/5 each, all 10 mutations red); findings doc LANDED, Waiting on live check (needs operator `make hub-promote` once CI green). Argon review of dirused#13 found 5, Claude verified all: stop line missing when cancel hits an empty/last folder or last file (high/medium), /csv stderr drops the path (low), tests lack Complete=false; spec docs/plans/dirused-m1g-a2-stop-line-gaps.md dispatched to Luna (--model gpt-6-luna). v0.0.4 waits on A2.
- 2026-11-17 16:05Z: hermes-vault-sealed E5 LIVE-VERIFIED (resolved 15:46:15Z after ESO recovered; no Withdrawn list since none pending). Sensor bug → LIVE-VERIFIED; r7 bug still waits on webhook E2 (never fired).
- 2026-11-17 ~16:00Z: operator chose fix-now for vault-sealed review findings ("dispatch two small ones"): specs webhook-vault-sealed-review-fixes (W1-W6) + hermes-vault-sealed-review-fixes (H1-H3,H5) dispatched to Codex (6169c3a1) — ran on gpt-6.1-terra, not Luna: started without --model (so did M1g Part A); left running; H4 guide by Claude. dirused v0.0.4 requested by operator (needs Argon review of #13, merge, tag); System Volume Information label idea (M1h) proposed, not yet filed.
- 2026-11-17 15:40Z: dirused M1g Part A verified by Claude on the VM (E1 green, pre-fix + 3 mutants red, live /timeout 2s names folder); committed a242be0, PR wilddog64/dirused#13 (CI 4/4 green on a242be0, incl. Windows; merge waits on blind Argon review). Part B still held on office probe B2.
- **dirused M1g spec 2026-11-17 ~15:35Z** (`docs/plans/dirused-m1g-timeout-names-folder-and-parallel-walk.md`; operator: "go ahead for that, and you can dispatch the tasks on you will"). Office run: all 4 agents TIMED OUT on d$ at 2m. Part A (stopped scan names the folder it was reading) dispatched to Luna. Part B (`/threads`, parallel walk inside one drive) held: VM loopback probe showed no gain (11.4s one walk vs 12.4s 8 processes); needs operator office probe B2.
- **E5/E2 live run 2026-11-17 15:01Z** (operator go): webhook restarted, vault-0 deleted, watchdog auto-unsealed at 15:05, ESO 9/9 True. vault_seal saw sealed once (debounced, healthy), never degraded; ArgoCDAppDegraded (for: 5m) never fired. E5 not met, E2 not exercised: needs a seal longer than one Hermes cycle (pause watchdog ~12 min, operator decision).
- **Promoted 44e06edd to deploy/hub 2026-11-17 ~14:20Z** (operator go; hub checkout fast-forwarded first). E4 live-verified: vault_seal healthy "unsealed: 1 pod(s)" in Hermes log and Prometheus. Remaining live checks: E5 (hermes) and E2 (webhook) at the next planned Vault restart, operator go.
- **Vault-sealed work LANDED 2026-11-17** on k3d-manager-v1.44.2: fadf8438 (Luna: vault_seal sensor, r7 gated, root-cause/Recommended/withdrawn card lines) and bea02b84 (Flash: webhook alert diagnosis reads Vault + ClusterSecretStore, sealed short-circuits Gemini). Claude verified both: hermes 416 green, routing 24 green, every new test red on pre-fix code (Luna 25/26 + 1 control-style pass, Flash 4/4), 4 mutations re-run independently all red. CHANGELOG [Unreleased] written. Audit markers added by Claude for test_slack_sensors.py:618 (authorised kwarg) and test_approvals.py guard removal. **Waiting on:** live check — promote (make hub-promote REF=bea02b84, appsets-check, platform-ops; operator tmux), then E4 dashboard row "unsealed: 1 pod(s)" (Claude read-only); E5/E2 at the next planned Vault restart (operator go).
- Spec fixes found while checking against code: sensor debounce must be `max(0, threshold-1)` (`_debounced` is `count > threshold`); r7 adds `vault_seal` to `reads` + `_evidence` (digest coverage); sensor test 8 reworded (r7 now reads vault_seal). External proof: vault-helm v0.30.1 raft config has `service_registration "kubernetes"`; hub runs HA+raft.
- Triage due (63 bug docs at operator decision) — announced.
- Alert emails checked live via hub pane work:1.0 (~12:45Z): K3dmPromoteWaiting 1c12925 = new P3 docs/bugs/2026-11-17-promote-waiting-stuck-on-squash-merged-release-branch.md (hub checkout still on merged v1.44.1 branch); KubeJobFailed x3 acg-expiry-check (2026-11-11) = Recurrence on 2026-11-06 watchdog KubeJobFailed bug; E2EVerificationStale product-catalog/vcluster = Recurrence on 2026-11-10 e2e-stale bug (clears after Wed run). Operator go given: hub checkout switched to k3d-manager-v1.44.2 at 666b27b7 (no local changes lost; deploy/hub unchanged), 3 failed acg-expiry-check Jobs deleted.
- hermes-vault-sealed review/split history: Argon + Fable both CHANGES, all folded, trial pair 4 logged; Luna resumed once (spec missed test_slack_sensors.py:618 contract reader — spec defect, note in next grooming). Flash run left no last-message report; verified from the diff alone.

## Handoff 2026-11-17 ~12:35Z — v1.44.1 SHIPPED; dirused v0.0.3 released — START HERE

**Objective next session:** open v1.44.2 (branch `k3d-manager-v1.44.2`, cut from main 666b27b7, pushed) and close dirused M1e with the office E4 check.

**Done this session (verified):**
- v1.44.1 merged 666b27b7 (PR #162), tag + GitHub release v1.44.1 (latest), enforce_admins restored, promoted to hub (deploy/hub 666b27b7, tag hub-promote/20261117T121641Z, no break-glass). Retro docs/retro/2026-11-17-v1.44.1-retrospective.md (342deb67).
- Containment bug LIVE-VERIFIED (E8 at that promote; ledger live_verified; 0b2da4d2). All v1.44.1 live checks done except Hermes CI page E3 (waits on a real ci unknown/degraded record; bug stays OPEN, Waiting on: live check).
- dirused #12 (M1e, hard links counted once via listing FileIds) merged 6c660229; enforce_admins re-enabled; v0.0.3 tagged, release run 44080730448 published a pre-release with win-x64 + win-arm64 zips + sha256.
- The Slack "Dispatch stalled: e8-toy-stall" message the operator saw at 19:16 PST was the 03:16Z E8 test notice (unread), not a new stall: no newer stall-* evidence.

**Waiting on the operator:**
1. dirused E4 (office): run the v0.0.3 build against one office agent; report wall time + the Windows row. Then mark M1e spec LIVE-VERIFIED (docs/plans/dirused-m1e-listing-file-ids.md) and decide the L7 vm-live warm-cache follow-up.
2. DONE 2026-11-17: both stale v1.44.0 review rows abandoned (open list empty).

**v1.44.2 scope (bug-fix patch; Branch lines name k3d-manager-v1.44.2):**
- `docs/bugs/2026-10-12-hermes-has-no-vault-sealed-sensor.md` — ships first; needs an Acceptance block + intent approval.
- `docs/bugs/2026-11-17-hermes-r7-signing-restore-offered-when-vault-sealed.md` — P2, intent approved; depends on the sensor (`vault_seal` record). One plan covering both (operator).
- Unseal watchdog stage 2: `docs/bugs/2026-11-15-vault-unseal-watchdog-secret-shard-rejected-errors-suppressed.md` — stage 2 spec to write (promote does not reapply the CronJob; live Secret already repaired).

**Other queue:** dirused M1f (backup privilege; VM proofs P1/P2 first, then spec + intent); dirused E3 timeout spec (intent pending); `_run_parallel` bug doc; stale trivy reports (cicd argocd-credential-rotator, platform-ops app-cve-scan, tag 1.31.4) await rescan; triage due (63 bug docs at operator decision); grooming 2026-11-22; 5 Argon P3s from #162 in docs/issues/2026-11-17-argon-pr162-review-findings.md.

**Notes:** Copilot capped until 2026-12-01 (Argon reviews release PRs). Bug docs going LIVE-VERIFIED need **Fix commit:** and a **Live evidence:** commit that contains it — after a squash merge cite the pre-merge hub commit (e.g. 6fe58dcb), not the main merge commit. MEMORY.md 8.3 KB, CLAUDE.md 10.5 KB (under budget).

**Next, in order:** 1) say "triage due" at start; 2) spec the Vault-sealed sensor + r7 plan (Acceptance, intent), then watchdog stage 2; 3) dirused E4 result → close M1e; 4) M1f proofs.

## 2026-11-17 ~02:25Z — v1.44.1 live checks (operator: "let's work on those 6 live verification")

- PASS: push-hook E3, release-column E3 (LIVE-VERIFIED); containment E9. Waiting: containment E8 (post-merge promote), Hermes E3 (next real ci page).
- Need go: root-token E5 (test_eso + test_vault on hub; test_vault rewrites auth/kubernetes/config with the same host + cluster CA, read before 02:12Z), stall-A E8 (make install-dispatch-stall-watch on M4 + toy frozen agy dispatch + Slack notice).
- Review gate: Copilot capped to 2026-12-01; Argon review of #162 covers code (delta docs/README only).

## 2026-11-17 ~00:20Z — v1.44.1 PROMOTED: deploy/hub 6fe58dcb, tag hub-promote/20261117T001751Z

- Operator ran hub-promote + appsets-check + platform-ops; Claude confirmed `make hub-promote-status` (deploy/hub 6fe58dcb).
  The 18 commits after 6fe58dcb are docs/memory-bank only (no code drift). The push-hook fix ran for real: the tag push went through cleanly.
- E3 flake: workers already use LongRunning (ScanRunner.cs:139; Claude first misread this). Remaining hypothesis: CancelAfter's timer callback
  queues to a starved thread pool. Spec docs/plans/dirused-e3-timeout-cancel-without-thread-pool.md (red-first; stop if not reproducible), intent pending.
- PR #162 opened (v1.44.1 release, f9248a48). Blind Argon diff review done: 7 findings, 3 refuted, 5 P3s captured (docs/issues/2026-11-17-argon-pr162-review-findings.md); no merge blocker. pgvector live E2 PASSED (91d11ef8). Live checks 1/10. v1.45.0 multi-project-records intent APPROVED (operator 2026-11-17).
- Next: live checks one at a time (pgvector E2 first); /create-pr can open now (live smoke gates merge, not creation); intent review of multi-project-records.

## Handoff 2026-11-17 ~00:30Z — v1.44.1 verified offline; dirused M1c-A PR #10 awaits office check — START HERE

**Objective:** finish v1.44.1 (live checks, then /create-pr) and close dirused M1c-A (operator office check, merge, tag).

**Evidence:**
- All 13 v1.44.1 fixes verified offline by Claude: each was red before the fix and green after. `verify` plus `offline_tested` marks are in the ledger; evidence is in `<run>/verify-evidence.txt` under `~/.local/share/k3d-manager/worktrees/v1.44.1/`. The CI-lint fix was recorded last (f20d1b2b).
- dirused PR wilddog64/dirused#10 (branch `m1c-summary-all-bugs`, head ef6c0d1). Tests-only commit 6a99c36 was red on CI exactly on E1 (portable) and E3 (Windows); CI is green at ef6c0d1 (windows 26/26, portable 24/24).
- Claude ran the live check on the dirused-dev VM and it passed: `docs/dirused/evidence/2026-11-16-m1c-a-live-vm.txt`.
- Package: release.yml workflow_dispatch run 43984077128 built the dirused-win-x64 and dirused-win-arm64 artifacts (they expire 2026-12-17).

**Decisions:**
- v1.45.0 plan 3 is now `multi-project-records` (DRAFT, intent pending); `service-password-tailnet-read` moved to backlog #1.
- dirused M1c Part A intent was approved ("approve dirused"). Part B still waits on proofs P1 and P2.
- wilddog64/dirused was made public (history scanned first); main protection was already on.
- Ideas captured: Hermes triages GitHub issues with Slack approval (sanitize first, issue -> docs/bugs, dedup before the card); the Bugs dashboard shows stage, owner and next step.

**Changed files (today):** docs/roadmap.md, docs/ideas.md, docs/plans/v1.45.0-multi-project-records.md, docs/plans/service-password-tailnet-read.md (renamed), docs/plans/dirused-m1c-*.md, docs/dirused/bugs/*, docs/dirused/evidence/, memory-bank/progress.md.

**Open questions:**
- dirused tag version: the operator said v0.1.2, but only v0.0.1 exists; Claude suggested v0.0.2. Ask after the office check.
- The FleetRunnerTests.E3 flake recurred despite #9 (bug doc reopened): add a product grace floor, or diagnose first?

**Verification status:** v1.44.1 is offline-verified for all fixes; live checks have not started (promote pending). dirused M1c-A is verified offline and on the VM; the fleet check is pending.

**Next, in order:**
1. Operator: office fleet check of the PR #10 package (`dirused /summary /file servers.list` shows all four hosts). If it passes, the operator merges #10, then Claude tags main (version per the open question) so release.yml publishes the pre-release; update the two dirused bug docs to LANDED / LIVE-VERIFIED.
2. Operator promote of v1.44.1: make hub-promote REF=6fe58dcb, then make appsets-check, then make platform-ops. Then Claude confirms `make hub-promote-status`.
3. Live checks one at a time: pgvector E2, alpine E2, stray guard E4 (delete the m4-air group first), unseal E0/E5, root-token E5, containment E4/E6, release-column E3, hermes E3, stall-A E8, push-hook E3.
4. /create-pr for v1.44.1.
5. Spec review of v1.45.0 `multi-project-records` (open questions are in the plan) and operator intent approval.
6. dirused M1c A3 (`/summary /top N`, approved) dispatch; Part B after proofs P1 and P2.
7. Decide the E3 flake fix; triage is due when captured bugs reach the threshold.

## 2026-11-16 ~21:00Z — v1.44.1 bug fixes: 10 of 12 landed

- LANDED: hermes CI unknown page c3642f8f (Flash; 2 red pre-fix, 390/390). Stray host guard 3b0def6b + coordinator fixture 5b308552
  (Flash; 2 red pre-fix, 28/28). The land gate caught repo_sync_promote_backlog.bats, a reader the spec missed; it was added to Files
  and landed with --allow-out-of-scope (the scope check uses the dispatch-time spec snapshot). Land does not push: push after land.
- New rule (operator, 2026-11-16): when triage picks a patch or carry, the bug doc gets Triage + Branch lines naming the target
  release (rules.md 92671d8e, /release-groom Step 0, memory).
- ~21:40Z: stall-A1 LANDED f3828ad9 (Luna; 16 red pre-fix, 34/34; pytest 2115 outside sandbox; live read-only probe clean).
  Agy step-count stalls need A2's watcher (sole writer of stall-watch.state). A2 dispatched (Luna, slug 2026-11-14-dispatch-stall-a2-watcher;
  land needs --superseding? no: different spec stage, same spec → land may need --superseding 2026-11-14-dispatch-stall-a-detector).
  Silent-running bug closes with A2 (M8-M11). push-hook LANDED 4476316a (live E3 at next promote). stall-A2 LANDED c91b4409 (+machine-manifest fixes 25d349c3, 16e6014f). Open 0/3. All v1.44.1 bugs landed.
- Next: verify push-hook, A2 → land; local CI shards; operator live checks one at a time; /create-pr.

## Grooming 2026-11-22 agenda
- Pull `docs/plans/v1.51.0-bug-count-query-translation.md` forward into the next open minor, displacing a not-started plan (operator 2026-11-17 "sounds good"); triage `docs/bugs/2026-11-17-ask-docs-list-wording-answers-old-release.md` with it.
- Ideas rows 2026-11-17 (Task Forest): dispatch-ledger reconcile + review-child folding; one "needs you" view.
- Ideas rows 2026-11-16/17: Claude-API reviewer, Claude-API Hermes writer.
- How to manage out-of-band repos (dirused and other work-environment tools): no ideas backlog, direct spec + dispatch for now; decide tracking, ledger and dispatch home (operator 2026-11-17).

## 2026-11-16 ~13:30Z — v1.44.1: fix the 10 groomed bugs before the release PR (operator)

- Correction: v1.44.1 holds 10 groomed bugs + the CI shard, not just the CI shard (docs/grooming/2026-11-15.md:54).
  Dashboard can't show them: Triage/Release lines ignored (P2 docs/bugs/2026-11-15-bug-release-column-ignores-triage-and-release-lines.md, v1.45.0).
- Operator plan: split dispatches evenly Flash (agy gemini-3.8-flash-medium) / Luna (codex); Claude verifies each; operator
  live-verifies one at a time; then the release PR. CHANGELOG [1.44.1] promotion was drafted and reverted (not committed).
- Proposed split. Flash: pgvector pin, alpine/k8s CVEs, hermes-ci unknown page, spec-intent flow-style, stray m4-air guard.
  Luna: stall-A (+silent-running), hub-promote containment respec, root-token argv, vault-unseal watchdog.
- RUNNING: Flash task/v1.44.1/2026-11-14-vectordb-pgvector-image-floating-tag. Sonnet spec drafts in progress (uncommitted
  edits in the bug docs) for the other 8; then Claude review → one intent-approval batch to the operator.
- 2026-11-16 ~15:10Z: all 9 intents APPROVED (operator). pgvector LANDED 74c8c7f3 (live E2 pending). Dispatch order: root-token(L)+alpine(F)+containment(L) → spec-intent(F) → stray guard(F) → hermes(F) → unseal stage 1(L) → stall-A(L, after containment: both touch Makefile). Then operator live-verifies one at a time, then release PR.

## 2026-11-16 ~12:30Z — v1.44.1 PROMOTED to hub: deploy/hub b5b931df, tag hub-promote/20261116T121447Z

- Operator ran hub-promote REF=b5b931df BREAK_GLASS=1 on m4-air.local; appsets-check, platform-ops, hub-promote-status OK.
- Live check (Claude, read-only, 2026-11-16): monitoring/grafana-dashboard-pr-checks contains the new panel-8 text.
- Hiccups: (a) m4 local k3d-manager-v1.44.1 pointed at old hub tip 50a42198 (ahead 392) → fixed with
  `git switch -C k3d-manager-v1.44.1 origin/k3d-manager-v1.44.1`; (b) tag push refused by pre-push hook tests that
  inherit REF/BREAK_GLASS from make → pushed with --no-verify. Captured: docs/bugs/2026-11-16-hub-promote-push-hook-inherits-make-vars.md (P2).
- Next: open v1.44.1 release PR (normal) → E4 pull_request-run half; Argon review. Ideas row candidate: hub-promote
  refuses when the checkout is not on origin's release tip.

## Handoff 2026-11-16 ~05:15Z — v1.44.1 CI shard LANDED (f20d1b2b), CI 22 → 7.0 min

- Objective: CI speed P2 (docs/bugs/2026-11-10-ci-job-named-lint-runs-the-full-test-suite.md). Status LANDED.
- Evidence: Claude reran tests + 2 real mutations red; union 264=264; push CI run 43806426493 wall 7.0 min, shards
  6.2/7.0/5.1/4.5, all 7 check-runs green. Pending: pull_request run on the v1.44.1 release PR (E4 second half).
- Changed: .github/workflows/ci.yml, Makefile (test-shard, test-shard-list), scripts/ci/test_shard.sh,
  scripts/tests/bin/test_test_shard.py, grafana-dashboard-pr-checks.yaml (panel 8 description).
- Next (operator, morning) — hub promote of b5b931df (CI 7/7 green, checked 2026-11-16). deploy/hub is 50a42198 and
  holds one uncontained docs-only commit f5c6cc79 (v1.43.15 plan Status lines); b5b931df already carries a newer text of
  both lines, so it is superseded, but `git cherry` flags it and a plain promote exits 1. Hence BREAK_GLASS=1, which
  also skips the CI-green gate, so step 1 re-checks green by hand:
    1. bin/k3dm-hub-promote is-green b5b931df   (exit 0 = green)
    2. make hub-promote-status                   (expect deploy/hub 50a42198, uncontained f5c6cc79 only)
    3. make hub-promote REF=b5b931df BREAK_GLASS=1   (typed confirmation)
    4. make appsets-check
    5. make platform-ops
    6. make hub-promote-status                   (expect deploy/hub b5b931df + new hub-promote/ tag)
  Then Claude: read-only live check (CI-shard change is CI-only; hub-side change = Grafana PR-checks panel 8
  description). Rollback: make hub-rollback. If the branch head moved, promote the newest head whose check-runs are all green.
- After promote: open the v1.44.1 release PR (normal, not draft) → E4 pull_request-run half; Argon review (Copilot quota out).
- Open questions still owed to operator: stale standing docs (copilot-instructions k3s-oci, functions.md v1.44.0,
  projectbrief), Dependabot low #16, stale review rows (deploy-hub-batch-review, test-hygiene-batch-review), xhigh P3
  (bin/k3dm-dispatch-metrics:752), dirused .sha256 CRLF P3. Owed live checks: Hermes card, vault-unseal, machine-setup N3,
  dirused /parallel fleet run.

## Current focus 2026-11-16 ~04:00Z — v1.44.0 MERGED, v1.44.1 open
- **v1.44.0 merged** (PR #161, `46ec5b36`, 2026-11-16 03:54Z by operator via admin override). Tag and GitHub release v1.44.0 created on `46ec5b36` (Latest). enforce_admins on main restored (enabled true; required reviews 1).
- **2026-11-16 ~04:30Z — v1.44.1 open.** v1.44.0 merged (#161, 46ec5b36), tagged, released; enforce_admins restored. **Tomorrow morning (operator): hub promote** of the merged release (operator deferred it on 2026-11-16 when leaving). CI speed P2 (`docs/bugs/2026-11-10-ci-job-named-lint-runs-the-full-test-suite.md`, option B lint split + 4 matrix shards, intents approved) DISPATCHED to Codex (task/v1.44.1/2026-11-10-ci-job-named-lint-runs-the-full-test-suite); Claude verifies + E4 live. Open for operator: standing-docs staleness (copilot-instructions lists k3s-oci; functions.md lacks v1.44.0 entries), Dependabot low #16, stale review rows deploy-hub-batch-review / test-hygiene-batch-review.
- **v1.44.1 open** on `k3d-manager-v1.44.1` (from `46ec5b36`). Holds the CI speed fix cherry-picked from `66b6f797` as `88128234`, plus retro `docs/retro/2026-11-16-v1.44.0-retrospective.md` (`72ee2cd3`).
- **First item:** CI speed bug `docs/bugs/2026-11-10-ci-job-named-lint-runs-the-full-test-suite.md` (P2; split lint job + matrix test shards, operator approved option B 2026-11-16).
- Open dispatch rows to review (not abandoned): `deploy-hub-batch-review`, `test-hygiene-batch-review`; dirused rows excluded (tracked separately).

## Handoff 2026-11-16 ~02:45Z — dirused P3s: both exited, verified, PRs #7/#8 open
- **DECISION (operator, 2026-11-15): dirused is tracked separately from k3d-manager** — not a k8s app; never assigned to a k3d-manager release or gate. Consequence: the dirused `/parallel` P1 should not block v1.44.0 / PR #161. Cause: bug-tally assigns a release from the k3d-manager branch that added the doc, so any doc under `docs/bugs/` lands in a release. Done: the 5 dirused bug docs moved to `docs/dirused/bugs/` (not scanned by bug-tally); v1.44.0 tally 65→60, no open P0/P1 from dirused. dirused plans stay in docs/plans (not release-counted).
- **2026-11-16 03:0xZ v1.44.0 live test:** operator promoted `deploy/hub` 0c0e3a44 → **50a42198** (last CI-green; tag hub-promote/20261116T025809Z); appsets-check pass (all apps on deploy/hub); platform-ops applied 50a42198. **PR #161 hub smoke PASS** (operator's m5 screenshot, read by Claude): `make status` Overall HEALTHY (ArgoCD/Frontend/Keycloak/Grafana/Pushgateway 200, Prometheus 401 auth enforced), zero ArgoCD apps not Synced/Healthy, PrometheusRule line 3236 = `Run: make hub-deploy REF=` (repo-sync alert text promoted — read-only batch prom-rules item). Hub snapshot 16h old. Claude cannot reach the hub from m4-air (no k3d-k3d-cluster context, m5 unresolvable). m5 checkout 84 behind origin — operator should pull. Remaining PR #161 gates: CI (lint running on 864791c2), Claude scope check. Remaining live: Hermes card (operator make deploy-worker), vault-unseal (event), machine-setup N3 (scheduled), rest of read-only batch.
- **SCHEDULED: v1.44.0 k3d-manager live testing at 18:57 PST 2026-11-15 (02:57Z 11-16)** — operator 2026-11-15. Session reminder at 18:50 (cron e68f182d, dies on exit). Keep the dirused VM idle from ~18:40; dirused `make vm-live` for #7/#8 only before then or after. Owed checks: PR #161 hub smoke, Hermes card, read-only batch, vault-unseal, machine-setup N3; confirm `make hub-promote-status` first.

- **PR #7 (1707, Flash):** 47d0572 test + 562de4a fix; offline verified: CI windows red on 47d0572 (run 43787406779, exactly the 3 new tests), fix green (run 43787367644); temp branch deleted. Next: Copilot, then make vm-live L2.
- **PR #8 (hung probe, Luna):** CI green run 43787368953. c9c59d6 tests + 588f0c2 fix on p3-timeout-hung-probe. Claude verified: E1/E2 red at b475154 (30 s / 2 min), 22/22 green, 5/5 reruns; MRES.Set-after-Dispose probe: no throw. Evidence scratchpad verify-hung-probe.md. Then make vm-live regression (E4).
- **Both:** CI + Copilot (review requested), fix findings, operator merges; then `mark --state offline_tested --sha <merge>` (verify refuses: no landed task). WIP 3 until merged/marked.

- **Operator approved all intents 2026-11-16.** Dispatched: `dirused-unreachable-1707` (agy gemini-3.8-flash-medium, branch p3-unreachable-1707, spec docs/dirused/bugs/2026-11-16-dirused-unreachable-node-error-1707-not-mapped.md) and `dirused-timeout-hung-probe` (codex gpt-6-luna, branch p3-timeout-hung-probe, spec docs/dirused/bugs/2026-11-16-dirused-timeout-cannot-bound-hung-volume-probe.md). Both branches created on origin at b475154. WIP = 3 (limit).
- **On exit verify from Acceptance only:** Bug 1 = test-only commit red on CI windows job, fix green, E3 make vm-live L2 pass. Bug 2 = new portable tests red at b475154 (run locally, TMPDIR=scratchpad), existing FleetRunner E3/E4 unedited, CI green, E4 vm-live regression. Then Claude opens PRs (normal, not draft), Copilot, operator merges, ledger mark offline_tested.

- **Specs written (Acceptance in the bug docs, per the error-64 precedent):** Bug 1 `docs/dirused/bugs/2026-11-16-dirused-unreachable-node-error-1707-not-mapped.md` (Flash, branch `p3-unreachable-1707`, E1/E2 Windows xUnit in RemoteTargetTests: TargetResolver is in Dirused.Core = Windows-only, so not portable; red proof = test-only commit on CI windows job; E3 live vm-live L2). Bug 2 `docs/dirused/bugs/2026-11-16-dirused-timeout-cannot-bound-hung-volume-probe.md` (Luna, branch `p3-timeout-hung-probe`; design: per-target background thread, wait Timeout + min(Timeout,2s) grace, abandon -> TIMED OUT, cap Parallel abandoned, beyond -> SKIPPED; E1/E2 portable, E3 existing tests unchanged, E4 live vm-live regression).
- **Both carry `**Intent approved:** pending — operator`**, so the spec_intent gate blocks dispatch until the operator approves the intents shown to them.
- **Next:** on approval, set the header, then `bin/k3dm-codex-dispatch start --spec <doc> --slug dirused-unreachable-1707 --agent agy --model gemini-3.8-flash-medium --repo ../dirused --branch p3-unreachable-1707` and `--slug dirused-timeout-hung-probe --agent codex --model gpt-6-luna --branch p3-timeout-hung-probe`. WIP then 3 (limit).

## Handoff 2026-11-16 ~01:30Z — dirused P3s approved; write specs and dispatch after /clear

- **Operator 2026-11-16:** "approve two P3 bugs and can dispatch to Flash and Luna after /clear", then clarified: "one for each". **Bug 1 (1707) → Flash** (`gemini-3.8-flash-medium` via agy); **Bug 2 (hung probe) → Luna** (`gpt-6-luna` via `make codex-dispatch`). Smaller fix to Flash, harder one to Luna. Routine P3 specs: no separate spec review needed. Claude verifies each (new tests red at b475154, `gh api`/CI, never trust the report), then runs `make vm-live` for live evidence (Gemini never does live checks).
- **Bug 1 (small, Flash):** `docs/dirused/bugs/2026-11-16-dirused-unreachable-node-error-1707-not-mapped.md` — add 1707 to the unreachable set in `TargetResolver.ErrorMessage` (`src/Dirused.Core/Targets/TargetResolver.cs:33`) + portable test. 1722 only if a capture proves it. Live red check: vm-live L2 (red at b475154).
- **Bug 2 (harder, Luna):** `docs/dirused/bugs/2026-11-16-dirused-timeout-cannot-bound-hung-volume-probe.md` — `/timeout` cannot bound a blocking summary volume probe; fix direction: ScanRunner abandons the worker at the deadline and reports TIMED OUT. Portable test with a blocking fake probe; must_not red at b475154.
- **Steps:** (1) write each as a spec with `## Acceptance` (must/must_not/evidence with intent, interface) + `**Intent approved:**` — show the intents to the operator; the bug-level approval above is not intent approval of evidence items they have not seen; (2) dispatch Bug 1 to Flash and Bug 2 to Luna — separate files (TargetResolver.cs vs ScanRunner.cs), so one per file holds.
- **WIP:** open rows = dirused-m1b0-modular-refactor (merged work, row still open, operator decision) + two `*-batch-review` rows (review children, do not count). Two new dispatches → 3, at the limit.
- **dirused state:** main b475154 (PR #6 merged). Release run 43785276977 artifacts (win-x64/arm64) for the operator's office test; expire 2026-12-16.

## Handoff 2026-11-16 ~00:45Z — dirused M1b 1a + 1b + P3 all MERGED; ledger offline_tested recorded — START HERE
- **Merged:** PR #5 (P3 unreachable codes) as eac2aa2 (00:21Z); PR #3 (1b fleet runner) as febe79d (00:34Z) after Update branch (486f219, CI green). Both merge trees identical to the CI-tested heads. Main CI at febe79d: run 43781208836 green. Copilot on #3 at e3a5e71: approval recommended, 3 threads resolved.
- **Ledger:** offline_tested at eac2aa2 for dirused-unreachable-codes; at febe79d for dirused-m1b1b-fleet-runner and dirused-parallel-threadpool-cap (evidence scratchpad offline-p3-merge.md / offline-1b-merge.md).
- **Bug docs:** threadpool + unreachable-codes now LANDED, Waiting on: live check. Hung-probe timeout P3 OPEN, waiting on operator decision.
- **Open item:** `open` still lists dirused-m1b0-modular-refactor (phase 0, merged 2dbd10d, offline_tested recorded) because it never got a `land` event; the only closer is `abandon`, which would miscount merged work. Left for operator decision.
- **Live tooling:** `make vm-live` (dirused PR #6, branch vm-live-check): vm-build + tools/vm-live.ps1 L1-L10, evidence .vagrant/live-evidence.md. First run 2026-11-16 at febe79d: 9 pass; L2 FAIL = new P3 docs/dirused/bugs/2026-11-16-dirused-unreachable-node-error-1707-not-mapped.md (NetShareEnum 1707 -> ERROR not UNREACHABLE). L1 passing = live proof for the unreachable-codes P3; L5/L7 = 1b live.
- **Office package:** PR #6 also adds .github/workflows/release.yml (workflow_dispatch -> win-x64/arm64 zips as 30-day artifacts; v* tag -> prerelease) and tools/live-check.ps1 (renamed; -Exe, -Targets fleet.txt adds F1/F2). Unzipped arm64 package tested on VM: L1, L3-L10, F1, F2 pass, L2 known 1707. One unexplained extra FAIL in the first of 9 runs (output truncated, id unknown) — watch for it in the office output.
- **PR #6 review:** Copilot (523ab13) 3 findings fixed in 585f2cd (L4 target guard, quoted cmd args, porcelain dirty flag), replied + resolved; 2nd review (585f2cd) 2 more: L5 BOM fixture (pwsh 7 Set-Content drops BOM; proven on VM 5.1 vs 7.6) fixed in 3d6e83a with byte assertion; PR body rename fixed; both resolved, 3rd review requested. Release workflow cannot run until #6 is on main (workflow_dispatch needs default branch) or a v* tag is pushed.
- **PR #6 MERGED** 2026-11-16T01:16Z as b475154 (tree identical to CI-green 3d6e83a; 3rd Copilot re-review request silently ignored by GitHub, operator merged). Release run 43785276977 green: artifacts dirused-win-x64 (sha256 f5ceb54a…, contents exe+live-check.ps1+README, commit b475154) and dirused-win-arm64, expire 2026-12-16.
- **Next:** (1) operator downloads win-x64 zip at office, runs live-check.ps1 -Targets fleet.txt; also `make vm-live` on the VM; then Claude marks live_verified (unreachable-codes from L1; m1b1b-fleet-runner from L5-L7; threadpool needs ACG fleet); multi-machine UNC still owed to ACG gate; (2) k3d-manager PR #161: CI, hub smoke, scope check; (3) PR Checks dirused waits on Hermes PAT scope.
- **Handoff rule:** the /clear hook injects the FIRST `## ` section — always write the new handoff at the top.

## Handoff 2026-11-16 ~01:15Z — dirused PR #5 clear to merge; PR #3 Copilot fixes pushed (e3a5e71), CI running — START HERE
- **PR #5** (P3 unreachable codes, 91d89ae): CI green, CLEAN, Copilot "Approval recommended, no open issues". Clear to merge; merge it first.
- **PR #3** (1b): Copilot (on 34102df) raised 3 findings. Fixed 2 in tests-first commits: 794eeba (tests, red at 34102df) + e3a5e71 (ScanRunner adds CANCELLED whenever ct is cancelled unless present; SummaryRenderer.Prepare lists every !Complete result as failed). Portable 20/20 at default and DOTNET_PROCESSOR_COUNT=2. Third (summary delegate ignores token) answered, not changed: one blocking Win32 call; captured as P3 docs/dirused/bugs/2026-11-16-dirused-timeout-cannot-bound-hung-volume-probe.md (waiting on operator decision). Reply: PR #3 comment 6903512685, plus in-thread replies on all 3 threads, all 3 RESOLVED (2026-11-16). Copilot re-review on e3a5e71: Approval recommended, no open issues, 3 resolved. CI on e3a5e71: portable green both runs; windows green on push run 43777417275, red on pull_request run 43777419628 only in UnreachableShareDoesNotStopOtherTargets (expected `(53)`, runner gave another code) = the exact flake PR #5 fixes. Merging #5 then Update branch on #3 clears it.
- **Next:** (1) operator merges #5; (2) "Update branch" on #3 (merge commit, no force-push), CI green, operator merges; (3) `mark --state offline_tested --sha <merge>` for dirused-unreachable-codes, dirused-m1b1b-fleet-runner, dirused-parallel-threadpool-cap; bug docs to LANDED; (4) close stale dirused-m1b0 row; (5) k3d-manager PR #161: CI, hub smoke, scope check.
- **Handoff rule:** the /clear hook injects the FIRST `## ` section — always write the new handoff at the top.

## Handoff 2026-11-16 ~00:30Z — dirused 1a merged + live-verified; P3 PR #5 green; PR #3 rebased, pushed, green — ready for operator merge — START HERE
- **Objective:** dirused M1b phases 1a + 1b, scan-only.
- **1a:** PR #4 MERGED as 245bedd (2026-11-15T23:29Z). Ledger: offline_tested (1a + unc-root slugs) and live_verified (1a) at 245bedd. E5 live 2026-11-16 on dirused-dev VM (BENTO, Win11 arm64): `dirused \\localhost` -> exactly C$ and D$ (no ADMIN$/IPC$), used/free/total equal Get-Volume byte-for-byte, exit 0. Multi-machine UNC still owed to the ACG gate.
- **P3 unreachable codes:** PR wilddog64/dirused#5 (m1b1a-unreachable-codes, 91d89ae) CI green; red at tests-only ebce3e1 (run 43775009024, exactly 51/64); verify pass recorded. Bug doc VERIFIED, waiting on operator merge.
- **1b rebase:** local m1b1b-fleet-runner rebased onto 245bedd: d302f65 (feat, conflicts resolved: Program.cs combines ResolveDetailed/RemoteScan with /summary + cts.Token; RemoteScan.Scan gains (resolved, ct) and (resolved, Func<string,ScanResult>) overloads; README keeps both paragraphs; E5 control badtarget -> `C:foo`), 33119f9 (LongRunning fix), 34102df (summary text renders all results at once — 1a's per-result loop broke SummaryRenderer volume dedup, caught by SummaryTests.E2 on the VM). Portable 18/18 at DOTNET_PROCESSOR_COUNT=2 and default; build clean. VM Windows suite: only env failures, all also fail on main 245bedd there (WinRM session is elevated with SeBackupPrivilege so deny-ACL tests can't go red; VM resolver returns non-53 for nosuchhost = the P3). **Force-push was blocked by the auto-mode classifier** — origin/m1b1b-fleet-runner still 4c1d83f.
- **Next, in order:** (1) DONE 2026-11-16: operator force-pushed rebased #3 (head 34102df); CI runs 43776043558 + 43776039258 green, mergeState CLEAN; (2) operator merges #5 (any order vs #3; both touch tests only lightly — rebase whichever is second if conflicted); (3) operator merges #3; (4) `mark --state offline_tested --sha <merge>` for 1b + threadpool slugs, and P3 slug after #5; (5) close stale dirused-m1b0 row; (6) k3d-manager PR #161: CI, hub smoke, scope check; offer dirused in pr_checks.py REPOS.
- **Handoff rule:** the /clear hook injects the FIRST `## ` section — always write the new handoff at the top.

## Handoff 2026-11-15 ~23:45Z — dirused M1b 1a/1b PRs open, both red on CI, PR #4 and #3 green, ready for operator merge (#4 first) — START HERE
- **Objective:** dirused M1b phases 1a + 1b, scan-only. Phase 0 merged (wilddog64/dirused#2, 2dbd10d).
- **1b:** landed 97a47fc on m1b1b-fleet-runner, PR wilddog64/dirused#3, verify recorded pass. CI `portable` RED: E4 peak concurrency 2 with /parallel 8 on 2-vCPU ubuntu (run 43771802268); Claude reproduced on Mac with DOTNET_PROCESSOR_COUNT=2 (peak 1). Cause: Task.Run + blocking scan delegate is capped by thread-pool injection. Bug doc docs/dirused/bugs/2026-11-15-dirused-parallel-capped-by-threadpool.md (P1, fix = LongRunning workers in ScanRunner.cs).
- **1a:** correction ab27363 verified (ScanRunner seam restored, RemoteScan.cs, invalid-target error, E1/E2/E3/E6 tests; portable 11/11, build ok, E4 grep clean), landed, PR wilddog64/dirused#4, verify recorded pass. CI `windows` RED: LoopbackMatches... VolumeProbeException 123 at VolumeProbe.cs:17 (run 43772219892). Cause: Path.GetPathRoot of UNC has no trailing backslash; GetVolumeInformation needs one. Bug doc docs/dirused/bugs/2026-11-15-dirused-unc-root-missing-trailing-backslash.md (P1, fix = VolumeProbe.cs only).
- **Dispatched 2026-11-15 ~23:55Z (operator approved intents):** slugs `dirused-unc-root-trailing-backslash` (base ab27363, branch m1b1a-remote-targets) and `dirused-parallel-threadpool-cap` (base 97a47fc, branch m1b1b-fleet-runner), codex/Luna. dirused main checkout now on main. Was: `**Intent approved:**` on both bug docs (spec_intent gate; landed slugs cannot `resume`, so each fix is a new `start --spec <bug doc> --repo ~/src/gitrepo/personal/dirused --branch <branch>` to Luna).
- **Worktrees:** 1a worktree removed by land? (1a branch is checked out in ~/src/gitrepo/personal/dirused); 1b worktree recreated at ~/.local/share/k3d-manager/worktrees/v1.44.0/dirused-m1b1b-fleet-runner on local m1b1b-fleet-runner — remove it before a new `start` if start wants to create its own.
- **Next, in order:** (1) DONE: fixes landed+pushed — 1a a9b4d78 (VolumeProbe trailing backslash), 1b 4c1d83f (LongRunning workers; verify pass recorded, red/green at DOTNET_PROCESSOR_COUNT=2). (2) DONE: both CI green; 1a fix verify recorded; Copilot #4 finding (O(n^2) lookup) fixed 505e3ab + thread resolved; #3 Copilot approved, no comments. New P3 docs/dirused/bugs/2026-11-16-dirused-unreachable-host-error-64-not-mapped.md (CI flake source). (3) verify, push, CI green both PRs; Copilot review (none posted yet on #3/#4), fix findings; (4) operator merges #4 then rebase #3 (README/Program.cs conflict; 1b E5 control "badtarget" -> e.g. `C:foo`); (5) `mark --state offline_tested --sha <merge>` for 1a/1b; (6) 1a E5 live on Vagrant VM when operator says free; (7) close stale dirused-m1b0 row.
- **k3d-manager PR #161 (v1.44.0):** 2 Copilot threads resolved this session; remaining: CI green, hub smoke, scope check. Offer: add dirused to pr_checks.py REPOS.
- **Handoff rule:** the /clear hook injects the FIRST `## ` section — always write the new handoff at the top.

## Previous handoff 2026-11-15 ~23:00Z — dirused M1b 1a/1b exited (superseded)
- **Objective:** dirused M1b phases 1a + 1b, scan-only. Phase 0 merged (wilddog64/dirused#2, 2dbd10d).
- **State (checked 2026-11-15):** `dirused-m1b1a-remote-targets` (codex/Luna, spec docs/plans/dirused-m1b-remote-targets.md) and `dirused-m1b1b-fleet-runner` (agy gemini-4-hydrogen-medium, spec docs/plans/dirused-m1b-fleet-runner.md) both **exited successfully**, changes uncommitted in worktrees under ~/.local/share/k3d-manager/worktrees/v1.44.0/. No PR open yet. Both touched README.md + src/Dirused.Cli/Program.cs (spec said no shared file) — expect a 1b rebase conflict after 1a merges; note for the Hydrogen trial.
- **Next:** verify each from its Acceptance block only (scope, `dotnet test tests/Dirused.Tests.Portable` with TMPDIR=scratchpad, new tests red on pre-fix), then commit, push, open a normal PR (CI `windows` job = Windows evidence), Copilot, fix findings, operator merges. **Merge 1a before 1b** (1b's /help names 1a's target forms). 1a E5 (live, Vagrant VM) only when operator says VM is free.
- **Ledger:** PR-merged dirused work can't `land`; use `mark --state offline_tested --sha <40-hex>`. Close stale `dirused-m1b0-modular-refactor` row if open.
- **dirused main protection:** required checks `windows` + `portable` (strict), PR required, enforce_admins.
- **k3d-manager PR #161 (v1.44.0):** lib-foundation#88 merged (f8025a26); subtree pulled 8f25545e (docs only: release-table rows). Next: resolve the 2 Copilot lib-foundation table threads, CI green, hub smoke, scope check. Post-merge: close deploy-hub-batch-review and test-hygiene-batch-review rows. Offer: add dirused to pr_checks.py REPOS.
- **Handoff rule:** the /clear hook injects the FIRST `## ` section — always write the new handoff at the top as `## Handoff ...`, never appended as `###` at the bottom.

## Open items (2026-11-17, carried at the memory-bank compression)

Source of truth for open work: `docs/bugs/` `**Waiting on:**` lines (2026-11-17: 66 live check, 63 operator decision, 13 dispatch, 3 scheduled run, 3 investigation), the dispatch ledger (`bin/k3dm-codex-dispatch open`), `docs/roadmap.md` and `docs/ideas.md`. Older handoffs: `memory-bank/archive/activeContext-2026-11-17.md`; their unchecked items are history, not a backlog.

- v1.44.1 PR #162: stall-A E8 running (toy dispatch e8-toy-stall, capture ~03:06Z); Hermes E3 waits for a real `ci` unknown record; containment E8 runs at the post-merge promote; then push, enforce_admins off, operator merges, `/post-merge` (prune MEMORY.md at that cut).
- Copilot capped until 2026-12-01: blind Argon review covers release PRs.
- `_run_parallel` bug: 0/300 repro in ubuntu:24.04; doc not updated yet; next run the real bats test in the CI image.
- r7 doc `Intent approved` line should end at the date; vault-sealed sensor bug needs Acceptance + intents (v1.44.2 prerequisite of r7).
- Watchdog stage-2 spec; stale trivy reports; dirused office fleet check.
- Triage due; grooming 2026-11-22 (agenda section below; new ideas: dispatch reconcile, needs-you view, dispatch split + rename to k3dm-agent-dispatch).

## Standing rules (current)

- Branch `k3d-manager-v1.43.14`, cut from v1.43.13 merge `abcde772` (2026-11-01). M5 is the hub; M4 is the dev node (its kube context is dead: query the M5 over ssh).
- Every fix: Claude reviews the diff, independent verifier from the Acceptance block only (no `cd`; repo `git status` before/after), land alone, then record. Record verify only from evidence captured now.
- Luna's sandbox has no network: put any upstream-source fact into the spec with its citation; never ask the worker to fetch.
- Sunday 2026-11-08 02:30: read the hub-snapshot result before touching that bug.

## Dispatcher task closeout — standing workflow

When the operator asks to dispatch a bug and verify/land it, carry the task through these steps without asking for separate prompts: (1) inspect the task's accepted diff against its spec and confirm the worker exited; (2) independently run focused tests plus relevant regression suites, syntax/lint checks, `git diff --check`, and `_agent_audit` (ShellCheck only applies to shell files); (3) if the worker left reviewed changes uncommitted, commit them on its isolated task branch; (4) run `bin/k3dm-codex-dispatch land --slug <slug> --test '<focused gates>' --allow-out-of-scope` only when any scope exceptions are explicitly allowed, otherwise stop and resolve scope; (5) push the release branch to origin; (6) update the canonical bug and memory-bank to `VERIFIED` with commit SHA and actual test results; (7) stop short of `LIVE-VERIFIED` until the operator supplies live evidence, and proactively give them the exact safe live check and ask them to report/screenshot its outcome. Once live evidence arrives, update the bug/memory and push that status change. `VERIFIED` means offline gates passed and fix is landed; `LIVE-VERIFIED` requires operator evidence from the deployed system.

If a local-server suite fails only because the sandbox cannot bind localhost, report that distinction and rerun with the required approved permission before judging the fix. Never infer live success from offline tests or let a passed offline test alone change status to `LIVE-VERIFIED`.

**Hub specs — operator dispatch go 2026-11-07; release order changed by Claude the same day.** `hub-deploy-ref-and-live-write-guard` moved to **v1.43.15 plan 5** (P1, dispatch first when v1.43.15 is cut); `claude-cost-task-attribution` moved to v1.43.16 plan 5; `dev-hub-vcluster` moved to **v1.43.16 plan 4**; `argocd-ha-zero-downtime-upgrade` is v1.43.17 plan 1. None can dispatch yet: v1.43.14 is at its cap and the dispatcher needs the release branch on origin. Operator prerequisite before the dev hub: OrbStack 16→24 GB on the M5. Split work panel: empty because the ledger has 0 `link`/`combine` events (feature never used), not a bug.
- 2026-11-10: hub-promote promoter-commits P2 intents E1/E2 approved; dispatched to Flash 3.8 (`hub-promote-keeps-promoter-commits`, spec `dcd115ea`). WIP 2/3 (+ `_run_parallel`). test-all-local reds investigated: 27 reproduce on the M4 from 6 bats files, all `No module named 'yaml'` from the direnv venv python3, and all pass with `/opt/homebrew/bin` first = known child C1 (`docs/bugs/2026-11-09-bats-python-yaml-picks-first-python3-on-path.md`), waiting on v1.43.16 dispatch. No new bug filed.
- 2026-11-10: C1 (`docs/bugs/2026-11-09-bats-python-yaml-picks-first-python3-on-path.md`) pulled into v1.43.15 on operator go; dispatched to Luna (`bats-python-yaml-helper`, spec `ffc45f20`; added the missing Files section and split the intent header so spec-intent parses). WIP 3/3 — no new dispatch until one lands. Parent C2–C4 stay on v1.43.16.
- 2026-11-10: plan verification sweep. hub-deploy-ref E2 VERIFIED from operator M5 output (ledger live_verified on 74cd3ca1); side finding: hub-promote-status 'ahead: 0' counts the M5's stale local branch, not origin. intent-verification E3 half seen, closes with the C1 verification report. cost-attribution: independent verifier (Acceptance-only, background subagent) started; its live E3 still owed.
- 2026-11-10: cost-attribution independent verifier 14/14 on HEAD, 9 red on pre-fix (Claude rerun matched); ledger offline_tested on 8153f9eb; live E3 waits on operator dashboard read. Note: tool reads K3DM_DISPATCH_PUSHGATEWAY_URL, not the PUSHGATEWAY_URL the plan interface lists.
- 2026-11-10: control-node-linux go to Flash 3.8 recorded; queued for the first free WIP slot (3/3 now: C1, hub-promote P2, _run_parallel). Cost-attribution live E3 read from operator screenshots: panels, unpriced note, 7d coverage 98.8%, guardian parent=missing 0 all match; 30d coverage 90.1% (spec said ~65%) and Ledger gaps $1.86 (spec said ~$0.50) do not, dashboard equals local exporter dry-run. Not marked live_verified.
- 2026-11-10: cost-attribution E3 ledger-gap cause found: 7 Codex subagent sessions ($1.31) of the acg-up-stalls dispatch are classed dispatch_unrecorded; the other 8 ($0.57) match the plan's ~$0.50. Filed P3 docs/bugs/2026-11-10-codex-subagent-sessions-counted-as-ledger-gaps.md. Label fix scheduled: P3 docs/bugs/2026-11-10-human-continuation-prompts-panel-counts-coordinator-resumes.md (rename step split out of v1.45.0 human-operator-turns). Both await intent approval; queue order after control-node-linux: rename, then subagent fix. cost-attribution stays not live_verified until the subagent fix's E2.
- 2026-11-10: operator approved intents + dispatch go for both P3s (rename → Flash 3.8 slug human-continuation-prompts-rename; subagent fix → Luna slug codex-subagent-ledger-gaps). Queue: control-node-linux, rename, subagent fix.
- 2026-11-10: filed P2 docs/bugs/2026-11-10-hub-loki-has-no-retention-and-local-path-ignores-size.md (Loki 3.7.3 retention off by default; local-path ignores 10Gi; proposed 14d default + 30d for dispatch-run/trivy-system/cicd; helm template + loki -verify-config proven offline). Awaits intent approval + operator disk measurements. Proposed queue: loki P2 first (bugs before features), then control-node, rename, subagent fix.
- 2026-11-10: Loki retention P2 intents approved + Flash 3.8 go (slug hub-loki-retention). Queue: hub-loki-retention, control-node-linux, human-continuation-prompts-rename, codex-subagent-ledger-gaps. Operator owes du/df baseline on M5 for E3.
- 2026-11-10: C1 bats-python-yaml-helper LANDED d96547df (pushed, origin matches); E5 make test running on M4. hub-loki-retention dispatched to Flash 3.8 (WIP 3/3: hub-promote P2, _run_parallel exited-not-landed, loki). Queue next: control-node-linux, rename, subagent fix.
- 2026-11-10: Loki baseline 297M/~10d (~30MB/day), node disk 743G free; Loki retention bug lowered P2→P3 by Claude (fix keeps running). Loki image is distroless: measure via docker exec on the k3d node.
- 2026-11-10: C1 E5 make test rc=0, 2033 ok, 0 not ok under the PyYAML-less direnv python; E4 counts unchanged. C1 LANDED, independent verifier owed.
- 2026-11-10: C1 VERIFIED (independent Sonnet verifier + Claude rerun). Found control-node impl already landed 4bd764b9 (2026-11-08); operator asked to run E3 (Vagrant) now, then E4 (Hostinger) depending on result.
- 2026-11-10: control-node-linux dropped from dispatch queue (already landed 4bd764b9). E3 Vagrant started: vagrant up --no-provision, then checksums, role, setup, make test in k3dm-control's clone at release head.

- 2026-11-11: CI lint red (runs 42939374114, 42947911553) diagnosed: repo-sync label unclassified + hub-sync test breaks under GNU make sub-make banner, both from f310b4d4. Filed docs/bugs/2026-11-11-ci-lint-red-repo-sync-unclassified-and-hub-sync-sub-make-banner.md (P2); fix in working tree, 21/21 Linux MAKELEVEL=1, 209/209 macOS; waiting on operator go to commit.
- 2026-11-11: CI fix 367d6caa pushed (CI watch running). Agent-cost + flash/fable P3 batch LANDED e7e1efd6 (Flash fix, Claude review; bats 49/49 with 5 red pre-fix; pytest 201). Waiting on hub-promote + live check. Next: hermes-approval review/land.
- 2026-11-11: Hermes approval dispatch review: REWORK. records_digest hashes whole records incl. per-cycle sampled_at, so every live approval would be refused (probe: digest unequal across cycles); worker also removed the repairs.py-unchanged guard; positive control reused the same records. Resumed Luna (--reason correction, prompt in scratchpad hermes-approval-correction.md).
- 2026-11-11: CI green on 446d2c49 (run 42952933807, lint + alertmanager-behaviour success); CI-fix bug VERIFIED.
- 2026-11-11 HANDOFF (before /clear): (1) Hermes approval dispatch resumed (resume 3, Luna) for rework: records_digest must cover only {sensor,status,data} of sensors each repair reads; restore repairs.py-unchanged guard; cross-cycle positive control. Re-review when `bin/k3dm-codex-dispatch open` shows it exited. (2) INVESTIGATION, no bug filed yet: TrivyCriticalVulnerabilityDetected firing since ~2026-11-11 01:19 for wilddog64/shopping-cart-frontend, cluster=ubuntu-hostinger, severity critical, remediation=cve-auto-patch (Prometheus ALERTS on hub). Hub job cve-auto-1794388764 Completed but logged frontend/order/payment/catalog deployed image as "<none>" tag and frontend "no HIGH/CRITICAL findings": scanner uses VulnerabilityReport row field 4 (tag) and fields 5/6 (crit/high) from _find_report_row (scripts/etc/argocd/platform-ops/app-cve-scan.sh:766-789). Suspect it picks a report whose tag is empty (digest-pinned image) with 0 counts, while trivy-operator metric for the live image says critical => auto-remediation silently skipped. Next: read _find_report_row, list Hostinger vulnerabilityreports for frontend (tag, digest, counts), confirm before filing. (3) Operator owes: make hub-promote REF=745abb50; make platform-ops; live checks Agent Cost + dispatch table. (4) e2e 2026-11-11 M2 PASS 90/102 no changes: unchanged baseline.
- 2026-11-11: Frontend CVE alert investigated: REAL. Hostinger frontend libxslt 1.1.43-r3 has CVE-2026-9947 (9.6) + CVE-2026-87636 (8.8), Trivy severity UNKNOWN; exporter severity_for promotes by CVSS -> alert; app-cve-scan uses summary counts (UNKNOWN excluded) -> no remediation. Filed docs/bugs/2026-11-11-app-cve-scan-ignores-unknown-severity-the-alert-counts.md (P2, OPEN, waiting on operator decision: intents + manual frontend rebuild?). Operator ran hub-promote (deploy/hub=745abb50) + platform-ops 2026-11-11; Agent Cost / dispatch-table live checks still owed.
- 2026-11-11: Agent Cost live check: E3 met (unpriced 0 all windows; Fable tokens priced into $455.03 7d), E6 data met (weekly_fable 0.01 = statusline 1%); only the Fable-row gauge screenshot owed. Dispatch-table Worker model column live check still owed.
- 2026-11-11: dispatch-table P3 VERIFIED live (Worker model column; cost-attribution-coverage worker gemini-3.8-flash-medium). Agent-cost P3 waits only on a Fable-row gauge screenshot.

- 2026-11-11: job 40d0e3dd (cluster-up aws) succeeded with the Keycloak bootout workaround (proven, doc bef89132); fix 3b0e6534 still needs a post-promote cluster-up. Added `make promote REF=` (df0f7c22: hub-promote → appsets-check → platform-ops, stops at first failure). Operator to run `make promote REF=df0f7c22` on M5 tmux this afternoon once CI is green.
