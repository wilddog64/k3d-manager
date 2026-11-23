## Update — 2026-11-22 ~19:30 PST — 2b LANDED e3eb53ca (code bb5b6aa9); CI pending on head

- 2b landed on k3d-manager-v1.45.0: c1def92c (Luna tree, Claude-committed), 44b37351 (E7 HEAD cmp removed), bb5b6aa9 (appsets source only on pinned path), e3eb53ca plan LANDED. Overrides: --allow-instruction-files (copilot-instructions), --allow-out-of-scope (3 E7 fixtures), both operator-approved and on the spec.
- Next: CI green on e3eb53ca, then operator runs make hub-deploy REF=e3eb53ca (tmux), then live check. Did NOT run make hub-sync (outward-facing; hub reads deploy/hub).
- Raw web-console B captures moved to ~/.local/share/k3d-manager/captures/2026-11-22-web-console-b-raw/ (24) and 2026-11-22-root-scratch/ (3); write-up still owed.
- Open: P3 docs/bugs/2026-11-22-hub-promote-tty-driver-10s-deadline-fails-under-load.md (triage). M1b landed (bef450c). M1a LANDED m1-base 4cbd377; awaiting operator OK for m2 install + E-L1. Operator 2026-11-22: tag hoverfocus v0.0.1 initial release with the M1 PR.

## Update — 2026-11-22 ~15:20 PST — order PR #109 ready to merge; 2b resume 6 running

- Order PR #109 (`227bbdbe`): Claude E1/E2 pass with red controls, blind Argon no findings, CI green (publish skipped on the PR). Operator merged 2026-11-22 23:07Z (`428e60de`); bug LANDED; E3 owed after the 01:00 PT scan (dispatch run on main, build-push success, promote commit, no FAILED line).
- 2b resume 5: 120/124. Rulings: 120 = script gap (`stop` must pass 75 at run-lock, promote, read-deploy-hub, read-promoted-ref per Behaviour 7); 116 test snapshot; 118 fixture needs `+` refspec; 34 G regression broken by the new guards. Resume 6 (correction) running, watcher armed.

## Update — 2026-11-22 ~15:30 PST — order CI fix dispatched; 2b resume 5 running

- Order CI (`docs/bugs/2026-11-22-order-ci-missing-workflow-dispatch.md`): operator chose "Fix now", route
  "Spec + Luna" (shopping-cart rule: no direct Claude edits). Fable spec review: needs changes, 5 should-fix + 2 nits,
  all applied (`7cf17dce`). Intents approved by operator. Base branch `fix/cve-manual-rebuild` created on order origin
  at `00c9fcd` (dispatcher refuses `--branch main`). Luna dispatched, slug `order-ci-workflow-dispatch`. Next: verify
  E1/E2 in the worktree, push, normal PR, blind Argon review, operator merges, Claude checks E3. Do not `land` into
  the order checkout (it is on `fix/automerge-app-token`).
- 2b: Claude's independent run of resume 4 = `hub_promote.bats` 71/71, shellcheck 0. Resume 5 (E4, sudo/launchctl
  guards, table) running; watcher armed.
- Restart-webhook transient-error P3 filed (`d576c5c9`). E6 sampler still running to ~15:41.

## Handoff — 2026-11-22 14:47 PST — promoted aa920a6f; Hostinger LIVE-VERIFIED; E6 sampling — START HERE

**Objective:** finish v1.45.0 (2b land, B captures, red-team gate, release PR); groom 2026-11-22 (Step 0 triage + ideas).

**Open dispatches 1 of 3 (all Luna, started 2026-11-22):**
- `remote-promote-2b-promote-wiring`: land may use `--allow-instruction-files` for `.github/copilot-instructions.md` only (`f12bcc16`).
- correlator P3 LANDED `f99f59f4`, VERIFIED (119 green; pre-fix 4 red; 2 mutants red); E2 live owed after hub runs it.
- `2026-11-09-hermes-reauth-lasts-24h-and-is-reusable` (slack-relay index.js; E2 intent approved `ea602bdc`).
- reauth P3 LANDED `e1972118`, VERIFIED (54 green; pre-fix 4 red; M4 mutant red after resume 2); E2 live after
  `make deploy-worker`. E2 wording changed to '10-minute' (operator 2026-11-22).
- 2b: resume 2 still incomplete (E5 4 tests + E7 2 done; E1 and E2 one test each; E3, E4, guards, table missing).
  It found and fixed a Makefile `$_got` escaping defect (M10). Resume 3 = E1+E3 only in hub_promote.bats; resume 4
  planned = E4 + sudo/launchctl guards + base/mutant table. Review the Makefile change at verify.
- Hostinger-status P3: verified offline, committed `fe64b3f7` on task branch (55 node / 10 bats / 46 pytest green;
  pre-fix 1+5+2 red; N2 mutant red). LANDED `8f6de4c1` (operator approved `--allow-out-of-scope` for
  webhook_make_targets.py), VERIFIED. Live: Slack entry removed + /cluster-status hostinger
  HEALTHY 21/0/0 (operator 2026-11-22); owed: `make deploy-worker`, then `/k3dm help`.
- 2b resume 4 running (correction): M8 misplaced `--approval` → exit 2 fix + 2 fixture fixes; resume 3 found it.
- On each exit: verify from git (not the worker's report), must_not red on old code, full land `--test` set under
  sandbox-exec (exclude machine_setup test 187: `tty_limited` `ps` denied, P3 `eef73df5`), push, then land; never commit
  on the release branch while a land runs (ff-only merge).

**Grooming 2026-11-22 (DONE, see docs/grooming/2026-11-22.md):**
- Argon classified the 53 unclassified OPEN bugs (committed `7ababe12`; 3a/3b drafts `2b15ede0`); 10
  Argon P3→P2; Claude would accept 3 (promote-waiting false alert, Hermes r7 first ESO group, ACG ssh config).
- 109 OPEN bugs: 8 P2, 101 P3; 36 P3 on second pass (close candidates); 15 carry a stale `carry → v1.44.0`.
- Fable blind ideas review done (ranks: weekly live-check session 1, verifier-first 2, stall watch for Claude jobs 3,
  promote CVE pin sync 4, ACG login 5, dev-hub gate 6; drops: sprint dashboard, CVE research, web console, /clear graph,
  WIP>3 row; v1.46.0: move out bounded-index + bug-lifecycle-metrics).
- Drafts (untracked, not reviewed): `docs/plans/remote-promote-3a-cloud-request-card.md` (Q1 early policy
  check location blocks dispatch) and `...-3b-relay-totp-signed-approval.md` (11 open questions; key hex-decode,
  id regex keeps `d`, skew window). Operator: draft now, implement on the release timeline.
- v1.46.0 is 7/5 before 3a/3b; needs swaps, operator decides.
- Carried agenda items (from 11-21): pre-commit `**Fix commit:**` rule; agy-quota-dashboard DRAFT placement; offline
  test-all P2 close C3/C4; pull `v1.51.0-bug-count-query-translation` forward with the ask-docs P2; out-of-band repo
  tracking (dirused) + per-project quota.

**Tonight (operator home):** PROMOTED 14:40: deploy/hub 4217648..aa920a6 (appsets ok, platform-ops ok); relay Worker version
  d6a3ac28. Bundle E6 sampling 1 h (14:41 first sample: PID '-', exit 0, success=1, last publish 14:27). Hostinger-status
  LIVE-VERIFIED (after `make restart-webhook`; new P2 filed: hub-deploy never restarts webhook on code change).
  Reauth E2: 10-minute reply confirmed; second-card reauth owed at next real incident.
  istio-ambient stale sandbox appset: P3, carry → v1.46.0 (operator). v1.46.0: bounded-index + bug-lifecycle-metrics moved
  to ordered backlog 10/11 (operator, grooming); v1.46.0 now 5 plans; 3a/3b need a swap to enter.

**v1.45.0 state:** remote-promote 1/2a/2c/2d/2e landed, 2b running; travel bundle, multi-project, stall-recovery landed;
web-console A live-verified, C LANDED `1026dbe2`/`c79c8ec0`, B = operator captures; make-up-app-none carried out.

**Waiting on the operator (home ~2 h from 2026-11-22 evening):**
- `make hub-sync` + `make hub-deploy REF=<release head>`, then Claude read-only checks (C, 2c, travel rev 2, bundle timeout E6).
- Slack relay Worker deploy + Hermes E2 checks after those fixes land; web-console B captures.
- Live checks owed: 2d E11; travel bundle E3/E5; test-all E3; stall C E8, B E9/E10; dirused M9b E2 (Mon 11-23, office).

**Standing facts:**
- Handoff guard: `.claude/hooks/handoff-on-clear.sh` reports STALE if commits land after this header; bump the time on edit.
- Older handoffs and logs, verbatim: `memory-bank/archive/activeContext-2026-11-22.md` (then `-2026-11-21.md`).
- Source of truth for open work: `docs/bugs/` Waiting-on lines, `bin/k3dm-codex-dispatch open`, plan Status lines.
- Known agent failure modes: Codex sandbox cannot commit; agents report suites they did not run; worker cd failures can
  delete untracked files in the main checkout (`git status` after each verifier run); mutants can reach real sudo
  unless the suite stubs sudo/launchctl in setup.
- Carried small items: ask-bash linked-worktree P3 unfiled; revoke the zshenv GitHub token; SHA-256 pin nit in
  agent_dispatch_dashboard.bats test 54; locked-Keychain WARNs in hub-deploy; M2 `~/.ssh/config` is a copy (ask first).

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

- 2026-11-22: memory-bank compressed (operator ask); previous file archived to `memory-bank/archive/activeContext-2026-11-22.md`.
- 2026-11-21: memory-bank compressed; log archived to `memory-bank/archive/activeContext-2026-11-21.md`.
- hoverfocus (new OOB repo, focus-follows-mouse without raise): M1 specs a5e315b8 (umbrella, M1a Luna core, M1b Flash shell, parallel split trial); Fable review running; repo name/visibility and intents pending operator.
- web-console C VERIFIED offline (E1-E9 PASS at 3fad525c, ladder offline_tested marked); E10-E11 live owed with part B. password-bundle hang bug LIVE-VERIFIED (E6). 2b resume 7 running: exit-75 allow-list made path-dependent per Part 1 B14 (resume-6 instruction lacked the approval-path qualifier).
- hoverfocus: public repo wilddog64/hoverfocus created, interface commit 007879f on main and m1-base (with Fable fixes 3/4/5/6: @MainActor FocusControlling, StartChecks probes, MonotonicClock, override and hf_ax_window_id decls); main branch protection on. Next: spec rev 2, operator focus probe, intents.
- hoverfocus intents approved by operator 2026-11-22 (rev 1 intent text, kept verbatim in rev 2). Dispatch still waits on spec rev 2 and the operator focus probe.
- 2b resume 7 checked by Claude: 131/131 under sandbox-exec (sudo/launchctl denied), shellcheck clean; stop() exit-75 condition now path-dependent per Part 1 B14. Next: independent verify from Acceptance, then land (--allow-instruction-files copilot-instructions only).
- hoverfocus icon concepts A/B/C on design canvas https://claude.ai/artifact/32Ju85vZ7YBvnzW2Uart3W; operator pick pending.
- hoverfocus: operator chose icon B Dwell; menu bar icon configurable via Config.menuBarIcon (auto|color|light|dark), interface 92ab158 on m1-base; preview board added to the icon canvas. Folds into spec rev 2.
- 2026-11-22: hoverfocus M1b rev 2 committed (088ec2d9: Fable fixes 2,4,10-14,17, icon B AppIcon.icns, Menu Bar Icon submenu, macos-26 CI). Flash dispatched as `hoverfocus-m1b-app-shell-r2` (project hoverfocus, ledger v0.0.1, base m1-base 92ab158); first start lacked --project, abandoned. `scripts/etc/projects.list` gains hoverfocus row. M1a waits on operator focus probe. Order entries (order-ci-workflow-dispatch, review-order-pr109) still open, need closing.
- 2026-11-22: hoverfocus focus probe pushed (hoverfocus branch probe/focus-flags a531a4a, variants A UserGenerated / B NoWindows / C A+make-key / D B+deactivate+make-key); operator to run on m2-air (personal console Mac). M1a rev 2 waits on its table.
- 2026-11-22: focus probe run 1 on m2-air (macOS 26.5.1 25F80): A UserGenerated typing n/raised n; B NoWindows typing y/raised n; C typing y but make-key records rc 1002 (layout suspect); D skipped. Earlier B over Safari raised. Probe 6c2e4b1 takes variant list; asked operator for B B B D D.
- 2026-11-22: focus probe run 2 (m2-air 26.5.1): B on TextEdit y,y (one n run targeted iTerm2 = invalid setup); D y,y but all records rc 1002 so D == B. Verdict for M1a rev 2: SetFront kCPSNoWindows only, no event records; never raised TextEdit; Safari raised itself once (app-side raise on activation = known limitation).
- 2026-11-22: operator "go with your recommendation": no hub-deploy now (deploy/hub aa920a6f current; only projects.list differs); next promote REF = 2b land commit. Order entries order-ci-workflow-dispatch, review-order-pr109 abandoned (finished out of band, PR #109). 2b independent verify agent started (Acceptance only, sandbox-exec).
- 2026-11-22: operator carried web-console part B out of v1.45.0 (roadmap close-out + B spec status updated); Claude runs agent-only captures C2, C6 unpriv, C8 offline, C10 on m4. Operator works from M2 via SSH into M4, rarely at M5.
- 2026-11-22: B agent-only captures (C2 schema, C6 unpriv, C8 offline, C10) recorded in the B spec; finding: Access apps delete-only (no disable), console reader _wc_check_routes defaults need a spec decision.
- 2026-11-22: 2b independent verify: E1-E7 offline PASS, but gaps (platform-ops superseded mapping untested, M2 exit-2 malformed->75 vs spec 2, E7 doc test partial, Makefile mutants not run). Ledger verify needs a landed task, so not recorded there. Luna resume 8 (correction) running. B captures recorded in B spec.
- 2026-11-22: Groom 2026-11-22: next release v1.46.0 5/5 (+2 travel exceptions; no swaps, 3a/3b to backlog 1-2); this week 2b land, red-team gate, v1.45.0 release PR; must-do 11 P2 carried to v1.46.0, 37 closed; ideas 1 promoted, 5 kept, 5 dropped. Recorded in docs/grooming/2026-11-22.md.
- 2026-11-22: ideas row added: CI shard balancing by runtime (operator go). PR #158 waits for v1.45.0 merge (main test-python red: fixed-date fixture in test_dispatch_metrics.py, fixed on release branch), then dependabot rebase, pin wranglerVersion.
- 2026-11-22: 2b resume 8 exited rc 0 (missed exit ~70 min); Claude rerunning the focused suites, then Makefile mutants. hoverfocus M1b r2 exited rc 0 (~1h45m earlier, missed); independent Acceptance-only verifier started.
