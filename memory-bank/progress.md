# Progress — v1.45.0 (older entries: `memory-bank/archive/progress-2026-11-22.md`, then `-2026-11-21.md`, `-2026-11-20.md`; open work lives in `docs/bugs/` Waiting-on lines and the dispatch ledger)
- 2026-11-23: session handoff rewritten (START HERE in activeContext; previous sections archived to `memory-bank/archive/activeContext-2026-11-23.md`).
- 2026-11-23: **hoverfocus v0.0.1 shipped** — PR #1 merged `d426f18` 14:09Z, enforce_admins re-enabled, tag v0.0.1 + GitHub release. v0.0.2 batches planned `docs/plans/hoverfocus-v0.0.2-bug-batches.md` (L1 Luna AppDelegate, F1 Flash Makefile/install, P1 live probe w/ operator ~15:30, L2 Luna Controller after P1); not dispatched, awaiting intent approval. Operator at work until ~15:30.
- 2026-11-23: hoverfocus PR #1 Argon review done (exit 0, read-only): 3 confirmed low/medium (reload fails open, AX element cache leak, Makefile sed escaping) carry → v0.0.2, 2 speculative; `docs/issues/2026-11-23-argon-hoverfocus-pr1-review-findings.md`. iTerm focus-follows-mouse coexists with HoverFocus (operator test). Next: CI on a4d9abb, operator merge, tag v0.0.1.
- 2026-11-23: hoverfocus PR #1 opened (m1-base → main, head a4d9abb, not draft); blind Argon review spec `docs/plans/review-hoverfocus-pr1-v0.0.1.md` dispatched (agy, role review).
- [ ] hoverfocus v0.0.1: PR m1-base → main, Argon blind review, merge, tag; bugs → v0.0.2.
- [ ] hoverfocus: E-L1 done 2026-11-23 (1-2 pass, 3 known limitation, bug filed); next M1 PR decision.
- [ ] hoverfocus E-L1: steps 1-2 pass 2026-11-23; step 3 pending; iTerm hollow-cursor P3 filed.
- [ ] dr-drill V4: LDAP admin bind mismatch after restore + `_err` exit (bug filed 2026-11-23, Waiting on operator decision); delete kept m2 `dr-drill` cluster before next run.

## v1.45.0 status (compressed 2026-11-22)

- **LIVE-VERIFIED:** remote-promote Part 1 (E9); 2e CVE-pin branch writer (E9); web-console part A (E11-E14);
  priv_open fix (E4); plan-quotas-beside-fable (E2); codex-row float-up (E2); dispatch-stall A and D; m5 PATH bug;
  land instruction-check P2 (E2, by the C r2 land, `ffc6f3ed`).
- **LANDED / VERIFIED, live owed:** travel bundle `ddd9329e` (E3), rev 2 `39a24a59` (E5); password-bundle Keychain P3
  `3971fa3f`; password-bundle timeout P2 `e3f2bcaf` (E6); test-all metrics `64a8de5c` (E3); dispatch-stall C (E8), B
  (E9/E10); remote-promote 2a, 2c `c17eae59`, 2d (E11); hub-deploy self-update `3b541f3b`; multi-project; agy repo/mode
  P3 `1e237612` (E6-E8); web-console C `1026dbe2`/`c79c8ec0` (live after hub-deploy). All need a hub-deploy first.
- **Running (Luna):** 2b promote wiring (resume 2). Correlator P3 `f99f59f4` and reauth P3 `e1972118` landed (E2 intent approved).
- **Carried out (operator 2026-11-22):** web-console B, to the next grooming; Claude runs C2/C6-unpriv/C8-offline/C10.
- **Not started:** red-team gate (intents approved, after 2b and B), release PR
  (Argon review; Copilot capped until 12-01).
- **Carried out of v1.45.0:** make-up-app-none (`93fe6b62`), to this grooming.
- **app-cve-scan auth fixed 2026-11-22:** classic PAT `k3dm-app-cve-scan` (repo, read:packages), expires 2027-02-20.
- **v1.46.0:** 7/5 (iPad SSH plan 6 intent approved; Tailscale plan 7 scope revision owed); 3a/3b drafts want in.

## Log

- 2026-11-22: order PR #109 open, verified, Argon no findings, CI green — operator merge owed. 2b resume 6 (4 reds) running.

- 2026-11-22: order CI spec Fable-reviewed and approved; Luna dispatched (`order-ci-workflow-dispatch`); 2b resume 4 verified 71/71, resume 5 running; restart-webhook P3 captured.

- 2026-11-22: promoted aa920a6f + relay d6a3ac28; Hostinger-status LIVE-VERIFIED; reauth E2 partial; P2 filed hub-deploy-leaves-webhook-on-stale-code.
- 2026-11-22: v1.46.0 cut to 5 (bounded-index, bug-lifecycle-metrics → backlog, operator); istio-ambient P3 → v1.46.0; CI green aa920a6f.
- 2026-11-22: CI reds fixed `aa920a6f`; kagent idea; P2 filed: istio-ambient ApplicationSet targets retired ubuntu-k3s, Hostinger Istio unmanaged by Argo.
- 2026-11-22: Hostinger E2 partial live: Slack entry removed, /cluster-status hostinger HEALTHY 21/0/0; deploy-worker + /k3dm help owed.
- 2026-11-22: Hostinger P3 LANDED `8f6de4c1`, VERIFIED (operator scope go); reauth-reply E2 wording → 10-minute (operator).
- 2026-11-22: Hostinger P3 verified offline (`fe64b3f7` task branch); land refused out-of-scope test file, operator go asked. 2b resume 4 (M8 fix) running.
- 2026-11-22: 2b resume 2 incomplete (E1-E4 thin, guards/table missing); resume 3 narrowed to E1+E3.
- 2026-11-22: Hostinger-status slash-command retirement P3 dispatched to Luna (2 of 3 open).
- 2026-11-22: Hermes reauth P3 LANDED `e1972118`, VERIFIED offline (resume 2 fixed M4 test gap); E2 after deploy-worker.
- 2026-11-22: Hermes correlator P3 LANDED `f99f59f4`, VERIFIED offline; Classified lines `7ababe12`, 3a/3b drafts `2b15ede0`.
- 2026-11-22: reauth worker exited 0, verify found M4 test gap + out-of-scope intent edit, resumed (correction); 2b exited 0 incomplete (tests missing), resumed (continue).
- 2026-11-22: memory-bank compressed (operator ask); full log archived to `memory-bank/archive/progress-2026-11-22.md`.
- 2026-11-22: grooming started: Argon classified 53 bugs; Fable ideas review done; remote-promote 3a/3b drafted (untracked).
- 2026-11-22: 2b, Hermes correlator, Hermes reauth dispatched to Luna (3 of 3).
- Order main CI after #109 merge green (run 45081470809, promote e64ae03b); E3 still waits for the 01:00 PT scan.
- hoverfocus (new OOB repo, focus-follows-mouse without raise): M1 specs a5e315b8 (umbrella, M1a Luna core, M1b Flash shell, parallel split trial); Fable review running; repo name/visibility and intents pending operator.
- web-console C VERIFIED offline (E1-E9 PASS at 3fad525c, ladder offline_tested marked); E10-E11 live owed with part B. password-bundle hang bug LIVE-VERIFIED (E6). 2b resume 7 running: exit-75 allow-list made path-dependent per Part 1 B14 (resume-6 instruction lacked the approval-path qualifier).
- hoverfocus: public repo wilddog64/hoverfocus created, interface commit 007879f on main and m1-base (with Fable fixes 3/4/5/6: @MainActor FocusControlling, StartChecks probes, MonotonicClock, override and hf_ax_window_id decls); main branch protection on. Next: spec rev 2, operator focus probe, intents.
- hoverfocus intents approved by operator 2026-11-22 (rev 1 intent text, kept verbatim in rev 2). Dispatch still waits on spec rev 2 and the operator focus probe.
- 2b resume 7 checked by Claude: 131/131 under sandbox-exec (sudo/launchctl denied), shellcheck clean; stop() exit-75 condition now path-dependent per Part 1 B14. Next: independent verify from Acceptance, then land (--allow-instruction-files copilot-instructions only).
- hoverfocus icon concepts A/B/C on design canvas https://claude.ai/artifact/32Ju85vZ7YBvnzW2Uart3W; operator pick pending.
- hoverfocus: operator chose icon B Dwell; menu bar icon configurable via Config.menuBarIcon (auto|color|light|dark), interface 92ab158 on m1-base; preview board added to the icon canvas. Folds into spec rev 2.
- [x] 2026-11-22 hoverfocus M1b rev 2 + Flash dispatch (`hoverfocus-m1b-app-shell-r2`); hoverfocus registered in projects.list
- [ ] hoverfocus M1a rev 2, operator focus probe, Luna dispatch
- 2026-11-22: operator "go with your recommendation": no hub-deploy now (deploy/hub aa920a6f current; only projects.list differs); next promote REF = 2b land commit. Order entries order-ci-workflow-dispatch, review-order-pr109 abandoned (finished out of band, PR #109). 2b independent verify agent started (Acceptance only, sandbox-exec).
- 2026-11-22: 2b independent verify: E1-E7 offline PASS, but gaps (platform-ops superseded mapping untested, M2 exit-2 malformed->75 vs spec 2, E7 doc test partial, Makefile mutants not run). Ledger verify needs a landed task, so not recorded there. Luna resume 8 (correction) running. B captures recorded in B spec.
- 2026-11-22: Groom 2026-11-22: next release v1.46.0 5/5 (+2 travel exceptions; no swaps, 3a/3b to backlog 1-2); this week 2b land, red-team gate, v1.45.0 release PR; must-do 11 P2 carried to v1.46.0, 37 closed; ideas 1 promoted, 5 kept, 5 dropped. Recorded in docs/grooming/2026-11-22.md.
- 2026-11-22: ideas row added: CI shard balancing by runtime (operator go). PR #158 waits for v1.45.0 merge (main test-python red: fixed-date fixture in test_dispatch_metrics.py, fixed on release branch), then dependabot rebase, pin wranglerVersion.
- 2026-11-22: 2b resume 8 exited rc 0 (missed exit ~70 min); Claude rerunning the focused suites, then Makefile mutants. hoverfocus M1b r2 exited rc 0 (~1h45m earlier, missed); independent Acceptance-only verifier started.
- 2026-11-22 2b land attempt: Claude mutants red (Makefile:1435/522 archive FETCH_HEAD killed by E5 tests 5/6; platform-ops raw exit 75 killed by E4 test 49). Luna left tree uncommitted (codex .git lock); Claude committed 5483e4ce in task worktree. Land refused: out-of-scope scripts/tests/fixtures/remote-promote-2b-docs/{rules,hub-promote,copilot-instructions}.md (not in spec Files). Found E7 test 2 ("pre-change documentation copies") cmp's fixtures against HEAD: — red once committed (fixtures == base f12bcc16, verified). Waiting on operator: --allow-out-of-scope for fixtures + who fixes E7 (drop 3 HEAD cmp lines).
- 2026-11-22 hoverfocus M1b r2 verifier PASS vs Acceptance (E1-E3; E-L1 live NOT RUN). Gaps: LICENSE (Claude added, uncommitted), MenuModel.loadConfig parses JSON itself and discards ConfigLoader.load result — carry to M1a rev 2.
- 2026-11-22 2b land #3: scope override accepted (operator); root untracked B captures moved to ~/.local/share/k3d-manager/captures/2026-11-22-{web-console-b-raw,root-scratch}/ (not deleted). Fast gate after rebase red: makefile_appsets.bats 1-2 — appsets-reapply now sources foundation system.sh on the manual (no APPSETS_SHA) path too; test scratch has no lib. Claude E7 fix 07c783f3. Waiting on operator: fix route.
- 2026-11-22 2b land #4: Claude fix 62aec55d (appsets source only on pinned path; makefile_appsets green). Land tests red once on hub_promote 34 (passed in land-test.1, 3 full runs, 5 isolated). Cause named: _run_promoter_tty 10s wall-clock deadline under load; P3 filed docs/bugs/2026-11-22-hub-promote-tty-driver-10s-deadline-fails-under-load.md. Rerunning land.
- 2026-11-22 2b LANDED e3eb53ca (attempt 5); pushed; CI pending. Hub-deploy REF after green: e3eb53ca.
- 2026-11-22 CI on e3eb53ca: 6/7 green; test-python red on 2 web_console_totp tests (connect before listen race, P3 docs/bugs/2026-11-22-web-console-totp-tests-connect-before-listen.md). Not 2b. Pushing docs commits re-runs CI on new head.
- 2026-11-22 CI 7/7 green on 948e5e7d (2b code = e3eb53ca + docs). Ask operator: make hub-deploy REF=948e5e7d, then Claude live check. hoverfocus M1b LANDED 87322d6 on m1-base (land 3; land test used scratch swift shim --disable-sandbox, nested sandbox_apply refused); pushed; hoverfocus CI running. Next: build as required check (operator go), M1a rev 2.
- 2026-11-22 ~20:00 PST: operator hub-deploy REF=948e5e7d (first attempt used stale history REF=74ff9a6f, 142 behind; promoter refused, no change). deploy/hub=948e5e7d, tag hub-promote/20261123T035950Z. Deploy steps running; live check after operator done.
- 2026-11-22 ~20:15 PST: 2b LIVE-VERIFIED (hub 948e5e7d clean; state appsets+launchd pinned 948e5e7d; 30/30 apps Synced/Healthy). Next: red-team gate, release PR (Argon).
- 2026-11-22: hoverfocus installed on m2 (operator go; clone m1-base 87322d6, make install, ~/Applications, agent running). Operator uninstalls from m4. Relicensed Apache-2.0 (was MIT), bef450c on m1-base (operator request); GitHub license badge appears after M1 merges to main.
- 2026-11-22: hoverfocus main protection: build required (operator go); PUT restated all other rules, read back unchanged (admins on, 0 approvals, conversation resolution, no force-push/deletion).
- 2026-11-22: hoverfocus M1a spec rev 2 written (variant B only, MenuModel.loadConfig via ConfigLoader, StartChecks order test, N5 no event records, selftest SkyLight check); Fable spec review next.
- 2026-11-22: hoverfocus M1a rev 2 pushed 4a26a803; Fable spec review agent running (read-only).
- 2026-11-22: v1.45.0 red-team gate started on 7dfb7238 (quota Fable 0.09 / Claude 0.25 / Codex 0.07); Fable + Astra blind, reports to scratchpad/redteam/. M1a Fable spec review still running.
- 2026-11-22: hoverfocus M1a Fable review of rev 2: needs rework (3 blockers: selftest cannot reach MenuModel, E2 grep vs selftest literals, untestable resolve-failed clause). All 19 findings verified against code and taken in rev 3 (public trial tap instead of CGPreflightListenEventAccess; AXFrontmost+AXRaise instead of activate()). Fable re-check of rev 3 next.
- 2026-11-22: red-team Astra report in (7dfb7238, 8/8 surfaces, 7 findings: 2 High CVE-pin provenance / bundle publisher PATH, 4 Medium recipient-removal race, mover green predicate, app-cluster token in argv, mirror fetches all heads; 1 Low bundle freshness). Transcript: only git show/grep + rg (N1 clean). Waiting on Fable report before adjudication.
- 2026-11-22: hoverfocus M1a Fable re-check of rev 3: ready after 1 should-fix (E2 -w grep missed SLPSPostEventRecordTo/kCPSUserGenerated; confirmed on fixture) + 6 nits; all taken, rev 4 READY.
- 2026-11-22: hoverfocus M1a rev 4 dispatched to Luna (gpt-6-luna) as hoverfocus-m1a-focus-core (project hoverfocus, ledger v0.1.0, from origin/m1-base bef450c). Operator: tag hoverfocus v0.0.1 as the initial release when the M1 PR is created (plan: tag the main merge commit + GitHub release).
- 2026-11-22: M1a Luna run 1 exited 0 but did not compile (9 errors, Controller.swift 52–61; Codex sandbox denied ~/.cache/clang ModuleCache so Luna never built). Claude proved CLANG_MODULE_CACHE_PATH=$PWD/.build/clang-mc + swift build --disable-sandbox builds with ~/.cache write-denied. Resumed (correction 1): compile fixes, reformat one-line functions, selftest ConfigLoader cases, menuOpen level check, NSLock state class.
- 2026-11-22: v1.45.0 red-team: Fable report in (H0 M3 L8 I2, no PoC run); Astra in (H2 M4 L1). Adjudication next.
- 2026-11-23: hoverfocus M1a LANDED on m1-base 4cbd377 (pushed, origin verified). Luna round 2 green; Claude independent check in sandboxed scratch copy: build, selftest 59/0 (56/0 skip-SkyLight), --print-config u/b/r rc 2 + partial rc 0 (dwellMs 300 kept), N6 red control rc 0 with base MenuModel, E2 greps empty, otool no SkyLight link, frozen files unchanged, 8 files only. Next: operator OK for `git pull && make install` on m2-air, then E-L1 live, then M1 PR m1-base→main and tag v0.0.1.
- 2026-11-23: red-team Fable report saved (harness blocked its file write; report delivered inline). Operator: Fable #3 (root installers source the writable checkout) = P2, doc + bug, does not block v1.45.0. No P0/P1 → red-team gate does not block the release PR; merged report + bug docs next.

- 2026-11-23: dr-drill on m2 failed at hub-up: Homebrew istioctl 1.32.0 (2026-11-12) rejects pinned k3s v1.32.0 (IST0142). Bug `docs/bugs/2026-11-23-dr-drill-hub-up-istioctl-1-32-rejects-k3s-1-32.md` (P2 proposed, operator decision). Explains daily DR freshness reds. hoverfocus make install on m2: bootstrap error 5; launchd log shows 37 EALREADY at 03:50:28 then service removed; BTM item enabled+allowed; manual retry from iTerm2 also error 5 and not in launchd log — cause still open.

- 2026-11-23: CORRECTION: live hub is m5-air (k3s v1.32.0, Istio 1.31.1); the m2 cluster (1.31.5 / Istio 1.28.3, EOL) is an older cluster. dr-drill bug triaged patch → v1.45.1 (operator), pin istioctl 1.31.4 to match hub. Red-team gate DONE (no P0/P1). v1.45.0 left: 2c verify, 2e independent verifier, release PR (CI, Argon review, smoke, scope check).

- 2026-11-23: ideas row added: self-diagnosing DR drill (headless Claude on API credit + Slack approve; operator yes). dr-drill workaround steps given to operator (istioctl 1.31.4 on PATH); Claude download on m2 was denied by permission classifier.

- 2026-11-23: operator go — independent Acceptance verifiers started for 2c (root daemon) and 2e (CVE-pin branch): Sonnet, worktree-isolated, sandbox-exec deny sudo/launchctl, scratch HOME. After both PASS: release PR (CI, Argon review, smoke, scope).

- 2026-11-23: 2c VERIFIED (independent Acceptance PASS; Claude re-ran 90 pytest + 9 bats on b036afc2). 2e verifier still running.

- 2026-11-23: 2e VERIFIED (independent Acceptance; M13 FAIL was stale spec text vs operator 2026-11-20 fail-loud decision — M13 amended). v1.45.0 ready for release PR.

- 2026-11-23: v1.45.0 CHANGELOG promoted (+promote, CVE pins, console, stall entries); README/releases rows; release PR opening. Owed live before merge: 2d E11, M2 live check (travel E3/E5 event-driven).

- 2026-11-23: PR #164 opened (v1.45.0 release, not draft). Argon review spec docs/plans/release-pr164-v1.45.0-review.md written; dispatching agy role review.

- 2026-11-23: CodeQL #38/#39 (totpctl enroll secret to /dev/tty) — false positive, operator approved dismissal; classifier blocked Claude dismissing → operator dismisses. Issue doc written. Argon review + CI running.

- 2026-11-23: hoverfocus bootstrap error 5 root cause = SSH pane is launchd Background session vs plist LimitLoadToSessionType Aqua. Claude sent `open HoverFocus.app` to m2 pane work:2.0 (operator asked): running pid 86349; E-L1 needs operator at m2 (Accessibility + hover test).

- 2026-11-23: hoverfocus agent loaded on m2 via sudo launchctl asuser bootstrap (operator typed password): state running pid 86556. E-L1 pending operator hover test.

- 2026-11-23: Argon PR #164 review read (operator OK): 2 low, both no-change (docs/issues/2026-11-23-argon-pr164-review-findings.md). Argon gate passed.

- 2026-11-23: CodeQL #38/#39 dismissed false positive by Claude (operator "yes"). Pushed 3810d909; CI pending.

- 2026-11-23: m2 dr-drill with istioctl 1.31.4: Phase 2 PASSED (istio pin confirmed); Phase 3 restore failed: empty age identity, login Keychain locked over SSH. Filed docs/bugs/2026-11-23-dr-drill-restore-empty-age-identity-locked-keychain.md. Workaround: security unlock-keychain then rerun.

- 2026-11-23: filed P3 docs/bugs/2026-11-23-dr-drill-teardown-ignores-failed-cluster-delete.md (operator go). Deleted leftover dr-drill cluster on m2; drill rerun in progress in work:2.0.

- 2026-11-23: m2 dr-drill run 3 (Keychain unlocked, leftover deleted): Phase 2 + Phase 3 PASS; Phase 4 printed V1-V3 true then script exited 1 during V4 (hub_data_verify_ldap) with no message and no report json; teardown clean. Last full pass 2026-11-04 (all V true). Next: diagnose V4 via DR_DRILL_KEEP=1 run (operator go needed).
- 2026-11-23: closed review runs release-pr164-v1.45.0-review and review-hoverfocus-pr1-v0.0.1 (abandon, worktrees clean). Filed docs/bugs/2026-11-23-hoverfocus-safari-no-focus.md (operator report; suspect 8-level AX parent walk in Controller.lookup; Waiting on: investigation, probe with P1).
- 2026-11-23: Safari bug update: operator screenshot shows hover focus works on Safari (video area, no raise); location-dependence still to check, else close not reproducible.
- 2026-11-23: B2 (hoverfocus window-not-key) recurrence: Cmd-W does nothing in Safari after hover focus; proposed P3→P2 (operator to confirm); folded into P1 probe.
- 2026-11-23: operator confirmed Cmd-W also fails in TextEdit after hover focus (general window-not-key gap, B2). Operator at work; live tests at home.
- 2026-11-23: hoverfocus v0.0.2: wrote L1 (AppCoordinator, reload fails closed, trust watch) and F1 (install wait/session/plutil/hint) specs rev 1, intents pending; launchctl proof captured on m4 (print missing rc 113, managername over SSH Background); pushed branch v0.0.2 at d426f18 on hoverfocus origin. Next: Fable spec review.
- 2026-11-23: Fable spec review of hoverfocus L1/F1 rev 1: both NEEDS FIXES (L1 blocker: E3 grep hits main.swift; F1 blocker: plutil -replace ProgramArguments.0 inserts and leaves __PROGRAM__). Claude reproduced both blockers + vacuous  grep; all findings applied as rev 2. F1 dispatch gate added: GUI launchctl managername capture on m2. Intents still pending.
