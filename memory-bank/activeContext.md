## Current state 2026-11-20 14:53 PST — v1.45.0 open — START HERE

Older handoffs and logs, verbatim: `memory-bank/archive/activeContext-2026-11-20.md` (compressed 2026-11-20, operator ask).
Source of truth for open work: `docs/bugs/` `**Waiting on:**` lines, the dispatch ledger (`bin/k3dm-codex-dispatch open`),
and plan Status lines in `docs/plans/v1.45.0-*.md`.

**Branch:** `k3d-manager-v1.45.0`, everything pushed. Hub `deploy/hub` = `5209b6b6` (promoted 2026-11-20 09:55 PST,
tag hub-promote/20261120T175509Z); 7 docs-only commits after it, no promote needed.

**Done today:** child B E9 + E10 LIVE-VERIFIED (72ab5903, 92fd27f7) after the P1 hermes approvals UA fix (970aeb23,
LIVE-VERIFIED on M5). dirused list local time (v0.0.24) and human sizes (v0.0.25) LIVE-VERIFIED.

**Dispatch WIP 3/3 (ledger), none running (2026-11-20 12:35):**
- `remote-promote-2c-root-daemon` (Luna, base d1ec381c contains 2d): 4 rounds, each ends after ~1-2 min with one partial
  file (daemon 74 lines, untracked). Same codex/model/effort as 2d (whose rounds ran ~20 min). Operator chose Astra 12:29:
  resumed on gpt-6.2-astra (resume 5, prompt scratchpad 2c-astra.md), running.
- `remote-promote-2e-cve-pin-branch` (Luna): rounds 1-3 lost to long-line truncation (23 spec lines > 400 chars; fixed
  with `fold -s -w 160`); round 4 wrote services-git.yaml only. Resumed on gpt-6.2-astra 12:29 (resume 5), running.
- `dirused-m9b-stop-delete-start` (agy Flash): test bug traced (1 GiB default /minsize; `/crit 0%` unparsed; /fromlist
  rejects /minsize and /crit). Flash round 5 fixed the first two; Claude fixed the /fromlist args (ced1c01). Windows CI
  then exit 1 instead of 3 at line 357 (step 1); Claude pushed 20b0949 making the assertion print stderr; stderr showed `/warn must be below /crit`; 61b7268 uses /warn 1 /crit 2; CI pending.
  PR wilddog64/dirused#39. Ledger VIOLATION = P3 false positive; closes via PR. Agy resume 4 replayed round 3 (no work).
- Web-console part C QUEUED: shares `Makefile` + `scripts/etc/machine/not-installed.list` with 2c (one dispatch per
  file) and WIP is full; start after 2c lands.

**M4 disk (2026-11-20):** manual cleanup 195 -> 202 GB free (5.5 GB old Claude scratch dirs, 2.9 GB brew cleanup); kept
628c342a (E8 evidence). Auto-cleanup = ideas.md row 74 (findings appended); monitoring already exists (v1.42.0 sensor).

**Handoff guard (2026-11-20, operator "go with your recommendation"):** `.claude/hooks/handoff-on-clear.sh` now appends a
computed Live state block (commits since the START HERE header line last changed, dirty tree, open dispatches, hub ref,
last 5 progress lines). Any edit to this section must also bump the header timestamp, or the hook reports STALE.

**NEXT (operator):**
1. Child C E8 (`docs/bugs/2026-11-14-dispatch-stall-c-diagnose.md`): diagnosis.md + correction.md printed to the operator
   2026-11-20 11:05 (files: session 628c342a scratchpad `e8root/v1.44.1/e8-toy-stall.run/stall-20261117T030605Z/`).
   LIVE-VERIFIED 2026-11-20 14:50 (Console $0.08 month = E1-E4 ~$0.03 + E9 $0.0015 + E8 $0.052646). Done.
2. APP=none rev 5 (`docs/plans/v1.45.0-make-up-app-none.md`): 3 intents (E1-E3) listed to operator 2026-11-20 12:20,
   APPROVED by operator 14:34 (recorded in spec). Dispatch blocked: Makefile shared with paused 2c (one dispatch per file) and Codex quota until 2026-11-24 07:32.
3. Web-console part A E11–E14 (`docs/plans/v1.45.0-web-console-a-console-sshd.md` lines 722-775): operator at the keyboard
   with sudo, M4 then M5, ~30-45 min. Claude first prepares the throwaway CA + certs (good, other-CA, wrong principal,
   expired) and the part B scratch sshd enabled control, captures P2-P5, then reads redacted output. Order E11 -> E12 ->
   E13 -> E14 (E14 revoke last; uninstall removes the test CA). Plan Status fixed to "verify recorded" 2026-11-20.

**Next dispatches (operator go given 2026-11-20 for C and remote-promote):** web-console C after 2c; 2b after 2c.
(Fast-line close-out trimmed v1.45.0; see roadmap.)

**Live checks owed:** web-console part A E11–E14; remote-promote 2d E11; travel bundle E3 (E2 LIVE-VERIFIED 14:50); travel bundle rev 2 add-laptop E5 (next laptop enroll);
test-all E3.

**Captured this session (P3, grooming):** `docs/bugs/2026-11-19-web-console-sshd-no-set-euo-pipefail.md` (also: its BATS
file is 555 s, the slowest; GitHub SSH keepalive now in dotfiles `ssh/m4-air/config`),
`docs/bugs/2026-11-20-machine-setup-antigravity-cli-refuses-unowned-agy.md`. M4 lacks `gemini-cli-api-key` (operator-
supplied; machine-setup exits 1 until added).

**Other open:** dirused M9a E2 LIVE-VERIFIED 2026-11-20; M9b PR wilddog64/dirused#39 merged a2d0508 (operator); dispatch record closed (abandon, reason landed via PR); v0.0.26 released (run 44823783100; win-x64/arm64 zips + .sha256); M9b E2 live check deferred by operator to Monday 2026-11-23 (team in office; no daytime prod Tomcat stop). Daytime-safe partial: preview + /confirm answer Enter (held logs skipped: in use, not confirmed; non-held old logs ARE deleted in pass 1). Full stop/delete/start still needs an outage window — tracked outside k3d-manager
releases. MEMORY.md over budget (compressing 2026-11-20). Triage due at grooming.

## Grooming 2026-11-22 agenda
- Pull `docs/plans/v1.51.0-bug-count-query-translation.md` forward into the next open minor, displacing a not-started plan (operator 2026-11-17 "sounds good"); triage `docs/bugs/2026-11-17-ask-docs-list-wording-answers-old-release.md` with it.
- Ideas rows 2026-11-17 (Task Forest): dispatch-ledger reconcile + review-child folding; one "needs you" view.
- Ideas rows 2026-11-16/17: Claude-API reviewer, Claude-API Hermes writer.
- How to manage out-of-band repos (dirused and other work-environment tools): no ideas backlog, direct spec + dispatch for now; decide tracking, ledger and dispatch home (operator 2026-11-17). Add: per-project workload/quota metrics (agent tokens per repo from session logs + dispatch ledger), since dirused shares the weekly quota and was hand-counted (operator 2026-11-19 "yes").
- P3s from 2026-11-18/19/20: run_parallel claim loop + file-lock signal cleanup (lib-foundation), web-console sshd `set -e` + slow BATS, machine-setup antigravity-cli, promote-to-dashboard lag, tokens-by-repo scratchpad label, plan-dashboard child specs.

## Standing rules (current)

- M5 is the hub; M4 is the dev node and this session's host (its kube context is dead: query the M5 over ssh).
- Every fix: Claude reviews the diff, independent verifier from the Acceptance block only (mutants per must_not, pre-fix
  red), Claude reproduces at least the top gap, land alone, then record. Record verify only from evidence captured now.
- Luna's sandbox has no network: put any upstream-source fact into the spec with its citation; never ask the worker to fetch.
- Push batching: each push cancels the in-flight CI run; push once per batch, then wait for green before giving a promote SHA.
- Fresh shells need `export SSH_AUTH_SOCK=/var/run/com.apple.launchd.uw3bpQR945/Listeners` to push; `cd` is broken by
  smartcd (use `git -C`, absolute paths, or `(builtin cd …)`).

## Dispatcher task closeout — standing workflow

When the operator asks to dispatch a bug and verify/land it, carry the task through these steps without asking for separate prompts: (1) inspect the task's accepted diff against its spec and confirm the worker exited; (2) independently run focused tests plus relevant regression suites, syntax/lint checks, `git diff --check`, and `_agent_audit` (ShellCheck only applies to shell files); (3) if the worker left reviewed changes uncommitted, commit them on its isolated task branch; (4) run `bin/k3dm-codex-dispatch land --slug <slug> --test '<focused gates>' --allow-out-of-scope` only when any scope exceptions are explicitly allowed, otherwise stop and resolve scope; (5) push the release branch to origin; (6) update the canonical bug and memory-bank to `VERIFIED` with commit SHA and actual test results; (7) stop short of `LIVE-VERIFIED` until the operator supplies live evidence, and proactively give them the exact safe live check and ask them to report/screenshot its outcome. Once live evidence arrives, update the bug/memory and push that status change. `VERIFIED` means offline gates passed and fix is landed; `LIVE-VERIFIED` requires operator evidence from the deployed system.

If a local-server suite fails only because the sandbox cannot bind localhost, report that distinction and rerun with the required approved permission before judging the fix. Never infer live success from offline tests or let a passed offline test alone change status to `LIVE-VERIFIED`.

## Log
- 2026-11-20 (morning): memory-bank compressed (operator ask): activeContext 165K -> ~8K, progress 81K -> ~4K; verbatim copies in archive/*-2026-11-20.md. 2d correction 412e59be (91 tests); Claude reran 6 gap mutants, all killed.
- 2026-11-20 (morning): 2d LANDED b42cb927 + 2c6a4cc5, VERIFIED (verify recorded). WIP 0/3. Push then promote after CI green.
- 2026-11-20 (morning): MEMORY.md 9063 -> 8662 bytes (3 pointers moved into hub_projects / hub_ref_observability, one line shortened; no pointer lost, no memory wrong or expired). Sonnet trial lines logged in progress.
- 2026-11-20 (morning): ideas row added (memory-bank size budget + /post-merge 7c recipe), operator ask.
- 2026-11-20 (morning): 3 ideas rows for grooming (rework_ratio + operator time, required reviewed field, weekly live-check slot), operator ask.
- 2026-11-20 (morning): CI lint red on 82d105e4 (6 pyflakes: 2 unused datetime imports in bin/k3dm-dispatch-recover from child B, 4 in test_promote_mover.py from Luna 412e59be). Claude miss: linted 2d before the correction and never ran pinned ruff on child B. Fixed (claude_edit after land); lint clean, 91 + 18 tests pass.
- 2026-11-20 (morning): "other" in Tokens by repo traced (6.45 M = one dispatch whose worktree version v1.44.0 differs from its ledger version v1.44.1); appended to the tokens-by-repo P3.
- 2026-11-20 06:49: CI green on 9d7973b6 (7/7). Promote SHA given to operator: 9d7973b62d04063c4af905da3909567fbcbaf596. Docs-only commits pushed after.
- 2026-11-20 07:23: promote 3d5fd9ef -> 9d7973b6 done by operator (tag hub-promote/20261120T152130Z; appsets-check ok, platform-ops ok, exporter rolled out). hub-deploy self-update E2 LIVE-VERIFIED from the pane. ArgoCD hub-grafana-dashboards still on 3d5fd9ef at 15:23Z (waiting on its poll) before checking the velocity tile.
- 2026-11-20 07:26: ArgoCD hub-grafana-dashboards synced 9d7973b6 on its own at 15:25:11Z (no refresh needed, ~3.5 min after promote). Velocity tile live: panel 34 Releases / 7 days, Prometheus count = 3 (v1.44.0, v1.44.1, v1.44.2); operator screenshot shows it.
- 2026-11-20 07:31: operator ran /hermes-auth 07:29 PST (24h). Handoff written; operator /clear next. Next session: child B E9/E10, child C E8 judgement, web-console A E11-E14.
- 2026-11-20 ~08:00: E9 staging incident: smartcd made `cd && export` skip the overrides, so toy `e9-toy-approve` started in the production root with the real Codex (gpt-6.1-terra); killed after ~15 s (143), worktree clean; abandoned (operator "go 0"); usage 45.9K in / 247 out in the production ledger. P3 filed: docs/bugs/2026-11-20-toy-dispatch-staged-in-production-root-real-codex.md. Finding: the stall watcher never calls the drain (child A N3; wiring = stall-recovery plan part 1, not written), so E9/E10 run the drain by hand; the watcher-driven half stays owed. Next: operator "go E9" (steps listed in session; all overrides inline).
- 2026-11-20 ~08:05: E9 card d1-9593afc1 posted (toy e9-approve, scratch root), but the drain cannot see clicks: Cloudflare 403 error 1010 on Python's default User-Agent (custom UA 200, wrong token 401). M4 drain token re-copied from M5 (works). P1 (operator) spec docs/bugs/2026-11-20-hermes-approvals-drain-blocked-by-cloudflare-user-agent.md; dispatch to Flash (gemini-3.8-flash-medium) after intent approval. Card left to expire 09:40 PST; E9 reruns on a fresh card after the fix lands. M5 Hermes approvals likely broken by the same path.
- 2026-11-20 ~08:15: dirused M9a E2 LIVE-VERIFIED (operator, jump box, v0.0.23): 2 held Tomcat85 redirect logs 'would delete after stopping Tomcat85', 11-03 log not held (plain would delete; spec expectation wrong, behaviour right), savelist/fromlist round trip same 3 rows. Plan Status fixed (offline VERIFIED 11-19 never recorded). Note for M9b: held file size from directory metadata was stale (117G -> 138G). Next: M9b spec.
- 2026-11-20 ~08:25: spec docs/plans/dirused-list-local-time.md (v0.0.24: delete list v2, lastWrite local time with offset + full fraction, v1 still read); operator asked to fold it into M9b and dispatch; Claude split it out because M9b is blocked (SEVERE-lines proof owed before its spec; medium risk = Fable + Astra review). Waiting on intent approval, then Flash/Luna (WIP 1/3).
- 2026-11-20 ~08:35: dirused-list-local-time dispatched to Flash (dirused branch list-local-time from 2ca49a2; ledger version v1.45.0, not v0.0.24). WIP 2/3 (P1 approvals UA + this).
- 2026-11-20: P1 approvals UA LANDED 970aeb23 (Sonnet verifier all pass); E4 live passed on M4 (no-UA 403 1010 vs UA 200; fetch_approvals empty queue). Pending E5: E9 fresh toy card + promote 970aeb23 for M5 Hermes. dirused list-local-time LANDED aa41dc0 (169/169, verifier mutants a-g red; CHANGELOG moved under Unreleased), PR wilddog64/dirused#37, Argon blind review running.
- 2026-11-20: dirused PR #37 merged 2e62aed, tag v0.0.24 (CI green, Argon clean). Pending operator E2 on jump box. P1 E5 pending: E9 toy card + promote 9c3345ba after CI.
- 2026-11-20: E9b staged: toy e9b-approve (scratchpad/e9b root, stub codex) card posted d1-a4a50fac, health probe passed (health_alert_at 0). Waiting on operator Approve, then Claude drains by hand.
- 2026-11-20: child B E9 PASS (e9b-approve d1-a4a50fac: one resume, Slack confirm line, relay queue empty). P1 E5 part 1 done; part 2 = promote + M5 Hermes r approval. Next: E10 Deny on old e9-approve card.
- 2026-11-20: child B E10 PASS (Deny d1-9593afc1: no resume, proposal stays proposed per spec :120, relay empty). Child B LIVE-VERIFIED. Toys e9-approve, e9b-approve abandoned in scratch roots. Open: P1 E5 part 2 (promote 72ab5903+, M5 Hermes r approval); dirused E2 (operator).
- 2026-11-20: dirused v0.0.24 E2 partial (operator 08:50 PST): /update 0.0.23->0.0.24, list v2 header, # created= and lastWrite in Pacific (-08:00) confirmed; /fromlist m9a2.txt and old m9a.txt replays not yet shown. Spec docs/plans/dirused-list-human-sizes.md written (v0.0.25: list v3, minsize=1GB, size column beside exact bytes); intents pending operator approval.
- 2026-11-20: dirused-list-human-sizes dispatched to Flash (dirused branch list-human-sizes from 2e62aed, v0.0.25; spec e83867d0). WIP 1/3.
- 2026-11-20: dirused-list-human-sizes Flash exit 0, 4 files in scope; Claude review: logic matches spec (v3 header, FormatMinSize exact units, size col via Format.Short, reader v1/v2/v3, bytes authoritative); note Flash reflowed the one-line Read/Write bodies (diff noise, behaviour same). dotnet test 188/188. Sonnet verifier from Acceptance running.
- 2026-11-20: dirused-list-human-sizes LANDED dirused@67ce6ee (verifier: M1-M4,N1-N3 pass, 12 pre-fix red, mutants red), PR #38 open; Windows CI + Argon blind review running.
- 2026-11-20: PR #38 Windows CI red: tests/Dirused.Tests/ProgramPurgeTests.cs:292 asserted 6 columns (Windows-only suite, missed in spec Contract readers = spec defect, not Flash). Claude fixed 6->7 in dirused@f491e45, pushed; Argon blind review: no findings. CI rerunning.
- 2026-11-20: dirused PR #38 merged c91e9b7 (CI 4/4 green on f491e45, Argon no findings); tag v0.0.25 pushed; release build running. Next: operator E2 on jump box.
- 2026-11-20: dirused v0.0.25 released (win-x64/arm64 zips + .sha256). Waiting on operator E2 (jump box).
- 2026-11-20: dirused v0.0.25 E2 steps 1-3 PASS (operator 09:16 PST): update 0.0.24->0.0.25, m9a3.txt v3, minsize=1GB, size col 138G/9.8G/8.5G beside exact bytes, /fromlist m9a3.txt /purge same 3 rows+statuses, 0 skipped. Outstanding: /fromlist m9a2.txt /purge (v2 replay) for both v0.0.24 and v0.0.25 E2.
- 2026-11-20: dirused v0.0.24 and v0.0.25 LIVE-VERIFIED: /fromlist m9a2.txt (v2) on 0.0.25 reads, same 3 rows, 0 skipped; v3 E2 passed earlier. Both plans closed.
- 2026-11-20: dirused M9b spec rev 1 written (docs/plans/dirused-m9b-stop-delete-start.md, v0.0.26, Flash, risk medium); /spec-review checklist fixes applied; Fable + Astra blind reviews running; dispatch waits on proof 6 (SEVERE lines, operator findstr), review adjudication, intent approval.
- 2026-11-20: M9b spec rev 2: Fable + Astra blind reviews adjudicated (20 rows; 1056/STOP_PENDING, ProbeHeld hold-back, warning containment, ENUMERATE_DEPENDENTS fixed); operator dropped catalina/SEVERE check (stop+start by SCM state only), proof 6 dropped; waiting on intent approval then Flash dispatch.
- 2026-11-20: M9b intents approved (operator); spec committed 5209b6b6; dirused branch m9b-stop-delete-start pushed at c91e9b7; dispatched to Flash (slug dirused-m9b-stop-delete-start). WIP: 1 open dispatch.
- 2026-11-20: CI 7/7 green on 5209b6b6 (272e4f64 run had test(2) cancelled by the push); operator asked to run make hub-deploy REF=5209b6b6 for P1 E5 part 2.
- 2026-11-20: P1 hermes approvals UA bug LIVE-VERIFIED (E5 part 2 on M5 after hub-deploy 5209b6b6: http 200 ua k3dm-hermes/1). Release PR no longer blocked by this P1.
- 2026-11-20: M9b Flash exit 0; 14 files all in table; Claude: portable 203/203, Windows test project builds; committed in worktree; Sonnet verifier next.
- 2026-11-20: M9b Sonnet verifier: 203 green but Start-skip defect (try opens after Stop, Purge.cs:671-741, Claude confirmed) + 6 surviving mutants, N3/N4/M10 gaps; correction round 1 resumed to Flash (task bgrcboffe).
- 2026-11-20: spec docs/plans/v1.46.0-make-up-app-none.md rev 1 written (v1.45.0 full); ideas.md row 81 updated + plug-in row added; Astra review: HOLD (wrappers at :942/:988 contain platform Steps 6/8/9 vault-bridge, ESO, ClusterSecretStore — confirmed by Claude; reused-hub shopping-cart-apps parent; OCI/GCP/Az providers; N4 not red pre-fix; 10f gateway). Fable review running.
- 2026-11-20: v1.45.0 fast-line close-out applied (operator: "let's do with your recomendation for fast line"): roadmap close-out paragraph; multi-project-records trimmed to M1+M2, dispatch-stall-recovery to A, D, child B, child C; M3/M4 + stall parts 1/3/5 carried to next /release-groom.
- 2026-11-20: APP=none spec rev 2 written (Fable + Astra both hold on rev 1; folded: platform Steps 6/8/9 called directly under none, _acg_app_step step ids, bin/k3dm-up-app-check with $(origin APP), stored app for resume, k3s-oci refused, reused-hub warn, golden default-step list). Awaiting operator intent approval + version placement before Luna dispatch.
- 2026-11-20: APP=none redesigned to bare nodes (operator: "we just want a empty nodes ... if we don't deploy shooping-cart then we don't need k3s"), v1.45.0 cap exception (plan 6, operator: "let make an exception for v1.45.0 as decoupling help future multiple project management"); spec renamed docs/plans/v1.45.0-make-up-app-none.md rev 3; OS=linux|win + NODE_COUNT 2-5 = separate follow-on plan. M9b correction round 1 exited 0, 211/211 portable green (Claude rerun); Sonnet mutant re-verify running. Fable + Astra blind review of rev 3 next.
- 2026-11-20: M9b mutant re-verify (Sonnet): 11/12 red; m05 SURVIVED (Flash claimed red — false), no Stop-throws test, and round 1 changed reclassified-row status to skipped (spec step 6 says failed: in use — my round-1 prompt wording caused it). Correction round 2 resumed to Flash (resume 3). APP=none rev 3 blind review: Fable + Astra running. Docs commit 861624f1 (push pending).
- 2026-11-20: operator "go with your recommendation": CLOUD= front-end (derive CLUSTER_PROVIDER, keep alias) added to ideas.md app plug-in row; APP=none rev 4 approach = remove rather than guard (no step-2-nodes checkpoint, no resume for none, stop at Makefile so observability/platform-ops never run). Astra r3: HOLD (8 findings; #1 Makefile:178-179 and #2 lifecycle.py:508-510 confirmed by Claude). Waiting on Fable r3 before writing rev 4.
- 2026-11-20: APP=none spec rev 4 written (Fable r3 + Astra r3 both HOLD, adjudicated): bare path moved out of bin/cluster-up into new bin/acg-up-nodes, picked by a Make conditional on $(origin APP)$(APP) (probed GNU Make 3.81: env APP ignored, value reaches recipe via env), so observability/platform-ops never run; bin/k3dm-up-app-check validates APP and refuses K3DM_RESUME after a bare run (bare-nodes marker); refuses over a recorded-active k3s-aws; no checkpoints; watcher/SSH failures fail the run; DRY_RUN makes no calls; cluster-up/down/refresh/lifecycle.py untouched. Next: short blind re-review + operator intent approval, then Luna dispatch.
- 2026-11-20: M9b correction round 2 (Flash) exited 0; Claude verified in scratch copy: base 213/213 green; mutants red: m05 (1056 handler off) -> M5_AfterStopTimeout_..., Stop-throws owned-stays-false -> StopThrows_QueryStateStopped_..., owned-always-true -> StopThrows_QueryStateRunning_..., reclass skip and key-only skip -> M7_... (expects failed: in use (held by a different service)). Next: commit, blind Argon review, PR, Windows CI. APP=none rev 4 committed 4f6a994d; Fable blind re-review running.
- 2026-11-20: M9b blind Argon review: CHANGES (4); Claude accepted #1 (throwing Stop aborts the run, rows null), #2 (finally pre-wait QueryState can throw past StartServiceW, spec step 10), #4 (M2 redirected-input test); rejected #3 (warning gated on control!=null: Program always passes control on Windows; spec section 8 keeps null-control M9a output). M9b round 2 committed 283eb4e in dirused worktree; correction round 3 resumed to Flash (resume 4, prompt scratchpad/m9b-correction-3.md). APP=none spec rev 5: Fable rev 4 re-review HOLD (no blocker, Make switch sound) - all 10 folded (_acg_ensure_sandbox_ttl copied, no sign-in step, marker first + N6, EXIT billable notice, uname/launchctl stubs, mkdir, Known limit for failed full build, readers lifecycle.py:257/365, Makefile:188/439, e2e.sh:176, hub_up.bats:115 + makefile_platform_ops.bats:6 layout constraint, .PHONY). Next: operator intent approval -> Luna dispatch.
