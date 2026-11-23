## Handoff — 2026-11-23 08:55 PST — hoverfocus v0.0.1 shipped; v0.0.2 planned; v1.45.0 merged — START HERE

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

**2. v1.45.0 release — PR #164**
- Merged 0c27b830, tagged, enforce_admins restored; next branch k3d-manager-v1.45.1.

**3. DR drill on the m2**
- V4 root cause filed `docs/bugs/2026-11-23-dr-drill-v4-ldap-admin-bind-err-exits-drill.md` (P2 proposed, Waiting on:
  operator decision): restored LDAP rejects drill admin bind (rc=49), and `_err` at `hub_data.sh:1000/1003` exits the
  whole drill (`_err` = print + `exit 1`, lib-foundation `system.sh:2114`).
- Kept `dr-drill` k3d cluster still up on m2: `k3d cluster delete dr-drill` (operator OK) before the next run.
- Then fix, rerun, `make dr-drill-publish`. Keychain bug priority also waits on operator.
- m2 remote shell is zsh: use `ssh m2 bash -s < script`, not `$VAR` word splitting.

**4. Owed specs / decisions**
- v1.45.1 = security + DR release (operator 2026-11-23): R1-R4 red-team P2s + 3 DR-drill bugs. Flow: Claude specs → Fable blind review → operator intents → Luna (logic) / Flash (docs) dispatch.
  - R4 token-in-argv: spec rev 1 written in bug doc (kubeconfig 0600, E1-E6; Luna). Open q: refuse insecure TLS?
  - istioctl pin 1.31.4: spec rev 1 written (children A lib-foundation Luna → subtree pull → B k3d-manager Luna → C changelog Flash); 4 sha256 checked by Claude against release assets.
  - R3 TOTP: spec rev 1 written (children B RevokedKeys Luna → A lock/log/socket Luna → C collector+alerts Flash). Open: same-uid DoS limit, permanent vs 24h lock, cert validity probe.
  - R1 pins: spec rev 1 (services-git.yaml index/kindIs guard, applicationsSync create-update, clusters generator first; ArgoCD v3.5.5 proof). Open O1-O3.
  - DR empty age identity: spec rev 1 (preflight presence check). DR V4: spec rev 1 for defect 2 (_err→printf+return); defect 1 (which admin password wins) = operator decision, Claude recommends restore Secret from backup.
  - Specs committed 918a148d. Fable review DR/istioctl DONE: all NEEDS FIXES. V4 blocker (bind helper's _kubectl exits before the ||; fix: --no-exit at :1000 and :1014) and age-identity → rev 2 applied by Claude (uncommitted). istioctl rev 2 done (refusal → _err; N5; survey: hub 1.31.1 ok, m4 1.30.0 REFUSED after fix, m2 1.32.0 refused). DR/istioctl rev 2 committed 0945fff0. R1/R3/R4 Fable: R4 2 blockers (trap placement; missing current-context falls back to in-cluster hub API, proven in alpine/k8s:1.33.13), R3 2 blockers (socket chown; dropped, scope split: metrics/alerts → v1.46.0), R1 5 should-fix (mergo deep-merge proven at argo-cd v3.5.5; new R4 selector guard). All rev 2. Operator decisions 2026-11-23: all intents approved; R1 O1-O3 per recommendation; V4 defect 1 (a) restore Secret; istioctl keep override + delete local copy; R3 24h final lock, decay yes, NEW unlock via recovery codes (child A waits for spec rev 3 + review); R2 spec → Fable + Argon independent review.
  - 2026-11-23 reviews: R2 spec rev 1 (11df6067) Fable+Argon NEEDS FIXES; Claude reproduced CDPATH (bash -p 3.2 does NOT ignore it), SCRIPT_DIR env, DEVELOPER_DIR→xcrun hijack of /usr/bin/git, sudo timestamp_timeout=60 on m4-air (ticket reuse blocker). Rev 2 fork running: adopt bootstrap `run <commit> <tool>` mode (env -i allowlist in root-owned code) instead of in-installer guard. R3 rev 3 + totp-a committed 2adc7f60; Argon NEEDS FIXES (global 60 s recovery rate limit = attacker DoS, collides with 60 s prompt_timeout; recovery.json.tmp not cleaned at startup; gate buffer truncation; scrollback on abort; test stubs); Fable R3 review running.
  - 3 ideas rows filed 65aded2f (operator go): console TOTP failures carry cert serial (ExposeAuthInfo), Slack one-tap cert revoke via Hermes, short-lived hardware-backed console certs. All inbox; rank at next /release-groom. R3 rev 4 fork running (rate limit dropped, A1/A2 split).
  - R3 rev 4 committed a300dcba (A1 3 files, A2 4 files new spec; intents pending: A1 E1/E4/E6, A2 E8-E12+L2, A2 Approval exception). R2 rev 2 committed e350217d (bootstrap `run` mode, 12 files, children A/B/C Luna + D Flash; B waits totp-b, D waits totp-c; intent pending); Fable round-2 review of the new design running.
  - Operator approved R2 rev 2 + R3 A1/A2 intents and the A2 patch exception (02763433). R4, R1, V4 Luna dispatches all exited 0 (R4 5 files, R1 4+1 new bats, V4 2 files); 3 independent Acceptance verifiers running; land each after PASS. Verifiers: V4 PASS (committed bc9fbbfe on task branch; land blocked only by stray untracked run.7cS9d7/ in repo root, likely R4 verifier scratch — remove after it finishes, then land); R1 PASS with one vacuous test (in-cluster server stub) → Luna resume running. UPDATE: V4 landed da956fbd, R1 landed 5f7ef7be (vacuous test fixed + mutant-checked by Claude), both pushed. R4 verifier FAIL on test coverage only (E3-E7 missing; code OK) → Luna resume 2 running. Dispatched Luna: totp-b-revoked-keys, totp-a-lock-and-recovery (WIP 3/3). Fable R2 rev 2 round 2: NEEDS FIXES — B1 sudo ticket reachable (stage→run gap, rollout no sudo -k, C-z/STOP), B2 evidence not runnable (install -o root, ancestor walk under tmp, $0 self-check, Linux CI skip), S1-S8 (S8: cut to ~8 files, defer web hardening to P3). Operator decisions pending: S8 scope cut; TMUX refusal (Q9); P12 probe `sudo /usr/bin/sudo -V | grep -i timestamp` at home. UPDATE: operator chose S8 cut + tmux allowed with TSTP ignored; R2 rev 3 = 98a30c55 (8 files; deferred P3 docs/bugs/2026-11-23-installer-direct-run-hardening-deferred.md). Intent approved: pending — re-approval needed for E1-E5, E7, E9, E12, E15 (E6/E8/E13 removed). R2 rev 3 intents re-approved by operator (dc9ac8f5); R2-A dispatch gated on P12 probe (at home) + a WIP slot; R2 child plan files A-D still to write. dirused (OOB): M9b decline path live-checked 2026-11-23 (N → held logs skipped, 9.8G deleted, 94.1%→89.2%); y path not yet live. Operator: M10b one-time schedule first, then M10c recurring rules (pattern+folder+service, caps, 30-day expiry); read-only truncate-in-place probe on ffm01 approved. M10b spec rev 1 + M10c draft landed f5e34572. M10b blind reviews 2026-11-23: Fable NEEDS FIXES (4 blockers: exe not protected, list read twice, interrupted run invisible, E1 not runnable in Portable), Astra NEEDS FIXES (agrees on list double-read, demand start, interruption, E1; adds pre-stop checks incomplete + Tomcat stranded if process killed). Both: split the spec. Operator decisions 2026-11-23: scheduled runs skip Tomcat-held files (no unattended stop/start; that + growth relaxation move to a later milestone needing a kill-surviving recovery path); split M10b into sequential children b1 engine / b2 schedule+list+cancel / b3 runplan+COM+ACL / b4 docs (Flash); ordinary files keep exact match. Operator 2026-11-23 added schedule preview: /schedule without /confirm previews only (registers nothing), /confirm prompts y/N, /confirm /yes no prompt; resolves O4; goes in m10b2. Operator 2026-11-23 "schedule at the node we like" → both: M10b = node picked by the list's UNC host (one plan per node; O6 proposed: refuse multi-host lists); later milestone = option to register the task on the target node (S4U/SYSTEM, dirused installed on server, needs server-owner approval). 2026-11-23: b3 switched from COM to `schtasks /create /xml` (switches can't set EndBoundary/offset/demand-start/catch-up); operator probe on jump box pending: where dirused + icacls exe/folder, test task \dirused-probe\t1 /it /sc once 23:00 + /query /xml + disconnected-fire check. Rev 2 landed d2cb805d/c7e2bc3b; schtasks /xml revision f1d90cc8 (TaskXml pure fn, UTF-16 BOM, read-back compare, no /f, own-file status). Pending operator: intents (b1-b4), O2/O3/O6/O7/O8, 6 baseline-red exceptions, jump-box proofs P1-P7,P10-P12 + parts of P8; Claude: P9 + P8 docs. Quick probe 2026-11-23 (6b18d4e4): exe ACL inherited full control for a 2nd domain account + unresolved SID (B1 real; O7 would refuse); schtasks defaults confirmed (no offset/EndBoundary, demand start on, battery flags true); P1 fire check after 23:00 pending. Follow-up: the extra full-control entries are inherited from the profile root (C:\Users\cliang), so a planted-exe swap via delete-child on a parent defeats the plan-folder exe copy; O7 check must walk all ancestors; scheduling blocked on this jump box until profile ACL fixed (operator/domain admin call). Shell not elevated (Medium IL) → non-elevated user can create task folder (P10 part 1). Operator 2026-11-23: keep the sysadmin profile grants until IT confirms (nothing removed; /remove:g processed 0). Proposed O7 revision: trusted-principal acceptance at /schedule, recorded in plan, re-walked at /runplan; unresolved SID never accepted by default; ask IT about S-1-5-21-…-8249. Fork writing rev 2 + children. Then dispatch queue: totp-b, A1, istioctl-a, R2-A, R2-C (R2 dispatch after Fable round-2 findings applied; R2 child plan files not yet written).
  - Dispatched (Luna, 3/3 WIP): R4 token-argv, V4 drill exit, R1 cve-pins. Queue: totp-b revoked-keys (Luna), istioctl-a lib-foundation (Luna, --repo), P3 argocd-alert-regex (Luna); then age-identity (after V4, hub_data.sh), V4 defect 1, istioctl-b (after v0.5.8 tag + subtree pull), P3 sync-branch + preflight rename (after R1); Flash: istioctl-c changelog, totp-c guides.
  - **Operator at-home steps (remind when operator says they are home):** (1) replace m4-air istioctl 1.30.0 with 1.31.4; (2) raise hub istiod to 1.31.4; (3) after promote: `make install-web-console-sshd` and `make install-web-console-totp`; (4) R1 ruleset on `cve-pins/hub` (promoter only, no delete/force-push); (5) scope `GIT_WRITE_TOKEN` (platform-ops-git-writer) to this repo, contents write only; (6) R1 probes (ruleset state, token scope).
  - Need operator decisions: R2 design (root installers source checkout), DR V4 LDAP bind, DR empty age identity.
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
- 2026-11-23: R4, totp-a, totp-b exited 0; 3 Sonnet Acceptance verifiers running. Operator: dispatch whenever a slot frees (standing go). Kept sysadmin profile grants (no ACL change); O7 trusted-principal revision proposed, awaiting approval.
- 2026-11-23: R4 LANDED 4b831c81 (verify pass recorded; E9 live pending after promote). istioctl-a dispatched to lib-foundation release/v0.5.8 (first start misrouted to k3d-manager, abandoned; run dir kept as istioctl-a-lib-foundation.misrouted-k3dm.run). totp-a verifier PASS with gaps; resumed (correction): restore the distinct NO path in test_N1_N8_M4_failed_prompt_limit (Luna made NO identical to WAIT). Gaps to note at land: M4 enrol/rotate lock clear and non-root admin untested, M6 unlock line unasserted. totp-b verifier still running. WIP 3/3 (totp-a, totp-b, istioctl-a). Next: argocd-alert-regex, then totp-a2 after totp-a lands.
- 2026-11-23: totp-b LANDED d6e1e7a6 (verify pass; L1 live pending after promote + install-web-console-sshd). argocd-alert-regex start refused (no ## Files section); Files table added, dispatching. Next: totp-a2 after totp-a lands.
- 2026-11-23 post-compact: totp-a (resume 1, NO path restored via verifier.tick) and istioctl-a exited; independent Sonnet verifiers running on both. argocd-alert-regex still running.
- 2026-11-23: totp-a LANDED f1dca6e8, verify pass (gaps: M4 enrol/rotate clear + non-root UNLOCK, M6 unlock/first-refused lines, M9 source-grep). istioctl-a LANDED lib-foundation release/v0.5.8 12e58b6, verify pass, pushed (gap: N2 no dedicated negative test). Next: tag v0.5.8 + subtree pull before istioctl-b. Dispatching totp-a2.
- 2026-11-23: dispatched totp-a2 and age-identity (WIP 3 with argocd). V4 defect 2 held: shares hub_data.sh with age-identity, goes after it lands.
- 2026-11-23: filed P3 agy-dashboard-print-mode-label-unclear (display-only rename print→headless, label value kept); queued for next free slot.
- 2026-11-23: argocd-alert-regex LANDED 400041df (--allow-out-of-scope: servicemonitor bats grep pin; spec Files fixed b0159a81), verify pass; L1 live after promote. Dispatching mode-label spec (agy-dashboard-print-mode-label-unclear, intents approved).
- 2026-11-23: reopened P3 2026-11-10-human-continuation-prompts-panel-counts-coordinator-resumes on recurrence (operator: file the P3); rename to 'Coordinator → agent prompts', metric name kept; queued for next free slot (after mode-label/totp-a2/age-identity).
- 2026-11-23: v1.51.0 cve-post-remediation-rescan plan amended (operator go): fixed-CVE register + reintroduction detection (items 9-10, 4 DoD checks); build-time CVE regression gate added to docs/ideas.md. New intents need operator approval before dispatch.
- 2026-11-23: age-identity LANDED 77d5a836, Sonnet verify pass (gaps: M2/N1 not red pre-fix; E6 live pending). V4 spec: repaired two rev-2 truncations (Notes line, Routing fragment); dispatching V4 defect 2.
- 2026-11-23: correction: V4 defect 2 had already LANDED da956fbd (morning), the 'held' note above was wrong; a verifier PASSED it this morning (line 46) but the ledger verify event was never written; second Sonnet verifier running to produce the evidence file. Still queued for hub_data.sh: V4 defect 1 (restore openldap-admin Secret) needs a spec after a read-only inventory check.
- 2026-11-23: dispatched P3 preflight-appset-rename (Luna; Files section added fa258edf). WIP 3: totp-a2, mode-label, preflight. sync-branch P3 not ready: E1 needs a read-only capture of the live services-git ApplicationSet (operator/hub). Continuation rename waits for mode-label (shared agent_dispatch_dashboard.bats).
- 2026-11-23: V4 defect 2 verify recorded (second Sonnet verifier PASS; gaps: printf text change on 994/1003 not mutation-tested, spec line 1014 is 1013). Bug Waiting on: investigation (defect 1 inventory check).
- 2026-11-23: mode-label landed `9f953c0b` (Claude fixed the new test's `git show HEAD:` baseline, which would fail once committed; now absolute, red on pre-fix and on a 5th transformation), verify pass; L1 live pending. totp-a2 landed `93ecfb83`: Claude replaced a duplicate shadowed test with `test_recovery_wrong_code_not_logged` (mutation red); audit waiver on the spec-authorised `size == 20` change; verify pass; L2 live pending. Next: dispatch continuation-prompts rename (shared bats file now free); preflight rename still running.
- 2026-11-23: continuation-prompts rename dispatched (codex luna). Open dispatches: preflight rename (running), continuation-prompts (running).
- 2026-11-23: hub-deploy REF=7b690cd3 refused (CI red, run 45288874536): Linux-only test escapes from 77d5a836 (dr_drill secret-tool stub lacked age identity) and 4b831c81 (verifier TMPDIR under set -u). Claude fixed test-only 7a84f90d (Linux sim pre 25/35+5/9 red, fixed 0); bug doc 2026-11-23-v1-45-1-ci-red-linux-age-stub-and-verifier-tmpdir.md (P1 proposed). Next: green CI on the pushed head, then operator reruns hub-deploy with the new head.
