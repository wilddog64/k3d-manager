# Progress — v1.45.0 (older entries: `memory-bank/archive/progress-2026-11-22.md`, then `-2026-11-21.md`, `-2026-11-20.md`; open work lives in `docs/bugs/` Waiting-on lines and the dispatch ledger)

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
