## Handoff — 2026-11-23 08:10 PST — hoverfocus v0.0.1 shipped; v0.0.2 planned; v1.45.0 PR #164 open — START HERE

**Operator:** at work today, home ~15:30 PT (only then: m2 live tests, hub promote). Batch every ask for that time.

**1. HoverFocus (repo `~/src/gitrepo/personal/hoverfocus`)**
- v0.0.1 SHIPPED: PR #1 merged `d426f18` (14:09Z), enforce_admins back on, tag `v0.0.1` + GitHub release with limitations.
- v0.0.2 plan: `docs/plans/hoverfocus-v0.0.2-bug-batches.md` — L1 Luna (`AppDelegate.swift`: reload fails open + watch
  trust without menu click), F1 Flash (Makefile/install_test/README: error-37 race, SSH `asuser` hint, sed/XML escaping,
  print `tccutil reset`), P1 live probe on m2 with operator ~15:30 (same-app key window without raise: AX
  `kAXMainAttribute`/`kAXFocusedAttribute`; check raise + terminal cursor), L2 Luna (`Controller.swift`/CSkyLight after
  P1 + AX element cache eviction). NOTHING dispatched.
- DONE 08:10: L1+F1 specs rev 2 (Fable reviewed, all findings applied), v0.0.2 branch pushed. Operator at home: approve intents, GUI `launchctl managername` on m2 (F1 gate), go. L1-EL gates the v0.0.2 merge. Was: write L1 and F1 child specs (Acceptance, must_not red on v0.0.1, `## Files`, intent lines
  `pending`), branch `v0.0.2` from `main` d426f18 on hoverfocus origin, Fable spec review. Then ask operator: approve
  intents + dispatch go. Open question for operator: create a local signing identity (stable TCC grant) or keep
  printing the reset step.
- Inputs: 3 bug docs `docs/bugs/2026-11-23-hoverfocus-*.md` (all `carry → v0.0.2`, Waiting on: dispatch) +
  `docs/issues/2026-11-23-argon-hoverfocus-pr1-review-findings.md` (3 confirmed, 2 speculative).
- Facts: grant is per-build (ad-hoc): after reinstall `tccutil reset Accessibility com.wilddog64.hoverfocus`, re-grant,
  `launchctl kickstart -k gui/$(id -u)/com.wilddog64.hoverfocus`. Over SSH bootstrap needs `sudo launchctl asuser`.
  iTerm "Focus follows mouse" handles panes and coexists with HoverFocus (operator-tested); not a bug.
- Rules: hoverfocus personal machines only; no AutoRaise/yabai code; Fable review before dispatch; sandbox-exec deny
  sudo/launchctl for any install_test run.

**2. v1.45.0 release — PR #164 (head `7e26d0ad`, mergeable; CI re-running on the docs push)**
- Done: blind Argon review (no change needed), CodeQL #38/#39 dismissed.
- Remaining in order: CI green on every check-run of head; `make hub-promote-status`; Claude read-only hub smoke;
  scope check; live 2d E11 + M2 (operator, home); then enforce_admins DELETE, operator merges, `/post-merge` tags v1.45.0.
- Every push to the branch restarts CI: batch docs commits.

**3. DR drill on the m2**
- V4 root cause filed `docs/bugs/2026-11-23-dr-drill-v4-ldap-admin-bind-err-exits-drill.md` (P2 proposed, Waiting on:
  operator decision): restored LDAP rejects drill admin bind (rc=49), and `_err` at `hub_data.sh:1000/1003` exits the
  whole drill (`_err` = print + `exit 1`, lib-foundation `system.sh:2114`).
- Kept `dr-drill` k3d cluster still up on m2: `k3d cluster delete dr-drill` (operator OK) before the next run.
- Then fix, rerun, `make dr-drill-publish`. Keychain bug priority also waits on operator.
- m2 remote shell is zsh: use `ssh m2 bash -s < script`, not `$VAR` word splitting.

**4. Owed specs / decisions**
- v1.45.1 spec: pin istioctl 1.31.4 (lib-foundation upstream first, then subtree pull). Not written.
- Carried: Argon classification of red-team + drill bugs; PR #158; weekly-live-check plan; E3 ordering; web-console B
  write-up (raw captures in `~/.local/share/k3d-manager/captures/2026-11-22-*`); delete probe branch; hub Istio ≥1.31.4;
  old m2 cluster on EOL Istio; v1.46.0 swaps for 3a/3b drafts.

**Dispatches:** 0 open (both review runs abandoned 2026-11-23 07:00).
**New:** `docs/bugs/2026-11-23-hoverfocus-safari-no-focus.md` — Safari never focuses; suspect 8-level AX parent walk in
`Controller.lookup`; add to P1 probe on m2 (tab bar vs page content; depth; `kAXWindowAttribute`), fix goes to L2.
agy.log read permission was one-off per run; ask again for a new review run.

**Standing facts:**
- Handoff guard: `.claude/hooks/handoff-on-clear.sh` reports STALE if commits land after this header; bump the time on edit.
- Older handoffs and logs, verbatim: `memory-bank/archive/activeContext-2026-11-23.md` (then `-2026-11-22.md`).
- Source of truth for open work: `docs/bugs/` Waiting-on lines, `bin/k3dm-codex-dispatch open`, plan Status lines.
- Known agent failure modes: Codex sandbox cannot commit; agents report suites they did not run; worker cd failures can
  delete untracked files in the main checkout; mutants can reach real sudo unless the suite stubs sudo/launchctl.
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
